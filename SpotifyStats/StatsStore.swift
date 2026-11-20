import Foundation
import ZIPFoundation

/// 読み込んだ再生履歴の保持・保存・追加読み込みを担当する。
/// データはアプリ内のDocumentsにJSONで保存され、次回起動時もそのまま見られる（Web版との違い）。
@MainActor
final class StatsStore: ObservableObject {
    @Published var entries: [PlayEntry] = []   // 時系列順（古い→新しい）
    @Published var isBusy = false
    @Published var statusText: String = ""
    @Published var progressText: String = ""
    private var didLoadSaved = false

    var dataMin: Date? { entries.first?.date }
    var dataMax: Date? { entries.last?.date }

    private var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("spotify-stats-data.json")
    }

    func loadSaved() {
        guard !didLoadSaved else { return }
        didLoadSaved = true
        let url = saveURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        isBusy = true
        statusText = "保存済みデータを読み込み中…"
        Task.detached(priority: .userInitiated) {
            let decoded = Self.loadEntriesFromDisk(url: url)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.entries = decoded
                self.isBusy = false
                self.progressText = ""
                self.statusText = decoded.isEmpty ? "" : "保存済みデータを読み込みました（\(Fmt.num(decoded.count)) 件）"
            }
        }
    }

    /// 保存済みデータの読み出し。保存形式はJSON Lines（1行=1件）。
    /// 旧形式（PlayEntry配列のJSON）が残っていたら読み替えて移行する。
    /// ※旧実装は [PlayEntry] 全体をJSONDecoderで復元しており、起動のたびに
    ///   重い処理が走って初回画面がなかなか出なかったため、行単位の軽量パースに変更した。
    nonisolated private static func loadEntriesFromDisk(url: URL) -> [PlayEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") {
            if let data = text.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([PlayEntry].self, from: data) {
                // v1.0形式の保存データには派生値がないので計算し直す
                var fixed: [PlayEntry] = []
                fixed.reserveCapacity(decoded.count)
                for var e in decoded { e.refreshDerived(); fixed.append(e) }
                return fixed
            }
            return []
        }
        var out: [PlayEntry] = []
        out.reserveCapacity(160000)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let e = parseLine(line) { out.append(e) }
        }
        return out
    }

    /// 1行のJSONオブジェクトから必要な項目だけを取り出す（文字列スキャンのみで軽量）
    nonisolated private static func parseLine(_ line: Substring) -> PlayEntry? {
        guard let t = jsonInt(line, key: "t"),
              let ms = jsonInt(line, key: "ms"),
              let track = jsonString(line, key: "track"),
              let artist = jsonString(line, key: "artist"),
              let album = jsonString(line, key: "album"),
              let key = jsonString(line, key: "key") else { return nil }
        return PlayEntry(t: t, ms: Int(ms), track: track, artist: artist,
                         album: album, key: key,
                         ep: line.range(of: "\"ep\":true") != nil)
    }

    nonisolated private static func jsonInt(_ line: Substring, key: String) -> Int64? {
        guard let r = line.range(of: "\"\(key)\":") else { return nil }
        var v: Int64 = 0
        var any = false
        var i = r.upperBound
        while i < line.endIndex {
            let c = line[i]
            if c >= "0" && c <= "9" {
                v = v * 10 + Int64(c.unicodeScalars.first!.value - 48)
                any = true
                i = line.index(after: i)
            } else { break }
        }
        return any ? v : nil
    }

    /// 文字列値の取り出し。\uXXXX はデコードせず残す（JSONEncoderはデフォルトで
    /// 非ASCIIをエスケープしないため、保存データに \u 形式は現れない）
    nonisolated private static func jsonString(_ line: Substring, key: String) -> String? {
        guard let r = line.range(of: "\"\(key)\":\"") else { return nil }
        var out = ""
        var i = r.upperBound
        while i < line.endIndex {
            let c = line[i]
            if c == "\\" {
                let j = line.index(after: i)
                if j >= line.endIndex { break }
                let e = line[j]
                switch e {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "/": out.append("/")
                case "\\": out.append("\\")
                case "\"": out.append("\"")
                default: out.append(e)
                }
                i = line.index(after: j)
            } else if c == "\"" {
                return out
            } else {
                out.append(c)
                i = line.index(after: i)
            }
        }
        return nil
    }

    /// ZIP／JSONを取り込む。既存データとは重複を除いてマージされるので、
    /// 新しいZIPをそのまま読み直しても二重に数えられない。
    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty, !isBusy else { return }
        isBusy = true
        statusText = "読み込み中…"
        progressText = "開始しています…"
        let reporter: @Sendable (String) -> Void = { [weak self] msg in
            Task { @MainActor in self?.progressText = msg }
        }
        Task.detached(priority: .userInitiated) {
            var fresh: [PlayEntry] = []
            for url in urls {
                switch url.pathExtension.lowercased() {
                case "zip":
                    fresh += Self.parseZip(url, progress: reporter)
                case "json":
                    if let data = try? Data(contentsOf: url) {
                        fresh += StreamingHistoryParser.parse(data: data)
                    }
                default:
                    break
                }
            }
            // マージ（重複除去＋並べ替え）も重い処理なので、メインスレッドではなく
            // ここ（バックグラウンド）で済ませてから結果だけを渡す。
            // ※v1.1まではこの処理をメインスレッドで実行しており、進捗表示が
            //   14/14 のまま固まって見えた
            let existing = await MainActor.run { [weak self] in self?.entries ?? [] }
            let merged = Self.mergeEntries(existing: existing, fresh: fresh)
            // 14/14の直後、ホーム画面の準備に入ったことが分かるようにする
            reporter("集計中…")
            await MainActor.run { [weak self] in
                guard let self else { return }
                if fresh.isEmpty {
                    self.statusText = "再生履歴のJSONが見つかりませんでした。Spotifyの「拡張ストリーミング履歴」のzipかどうか確認してください。"
                } else {
                    self.entries = merged.entries
                    self.saveSnapshot(merged.entries)
                    self.statusText = merged.added > 0
                        ? "\(Fmt.num(merged.added)) 件を追加しました（全 \(Fmt.num(merged.entries.count)) 件）"
                        : "新しい再生履歴はありませんでした（全 \(Fmt.num(merged.entries.count)) 件）"
                }
                self.isBusy = false
                self.progressText = ""
            }
        }
    }

    func deleteAllData() {
        entries = []
        statusText = ""
        try? FileManager.default.removeItem(at: saveURL)
    }

    private func saveSnapshot(_ snapshot: [PlayEntry]) {
        let url = saveURL
        Task.detached(priority: .utility) {
            // JSON Lines形式（1行=1件）で保存する。起動時の読み戻しを軽くするため
            var text = ""
            text.reserveCapacity(snapshot.count * 160)
            let enc = JSONEncoder()
            for e in snapshot {
                if let d = try? enc.encode(e), let line = String(data: d, encoding: .utf8) {
                    text += line
                    text += "\n"
                }
            }
            try? text.data(using: .utf8)?.write(to: url, options: .atomic)
        }
    }

    nonisolated private static func parseZip(_ url: URL, progress: (@Sendable (String) -> Void)? = nil) -> [PlayEntry] {
        guard let archive = try? Archive(url: url, accessMode: .read) else { return [] }
        let targets = archive.filter { $0.type == .file && HistoryParser.isHistoryJson($0.path) }
        var out: [PlayEntry] = []
        var done = 0
        for entry in targets {
            var data = Data()
            _ = try? archive.extract(entry) { chunk in
                data.append(chunk)
            }
            out += StreamingHistoryParser.parse(data: data)
            done += 1
            progress?("読み込み中… \(done) / \(targets.count) ファイル（\(Fmt.num(out.count)) 件）")
        }
        return out
    }

    /// 重複判定のキー。文字列を作らず構造体で持つ（14万件分の文字列生成を避ける）
    private struct DedupKey: Hashable {
        let t: Int64
        let key: String
        let ms: Int
    }

    /// 既存データと新規データを重複除去してマージし、時系列順に並べ替える
    nonisolated private static func mergeEntries(existing: [PlayEntry], fresh: [PlayEntry]) -> (entries: [PlayEntry], added: Int) {
        var seen = Set(existing.map { DedupKey(t: $0.t, key: $0.key, ms: $0.ms) })
        var result = existing
        var added = 0
        for e in fresh {
            let k = DedupKey(t: e.t, key: e.key, ms: e.ms)
            if !seen.contains(k) {
                seen.insert(k)
                result.append(e)
                added += 1
            }
        }
        result.sort { $0.t < $1.t }
        return (result, added)
    }
}
