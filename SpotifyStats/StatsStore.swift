import Foundation
import ZIPFoundation

/// 読み込んだ再生履歴の保持・保存・追加読み込みを担当する。
/// データはアプリ内のDocumentsにJSONで保存され、次回起動時もそのまま見られる（Web版との違い）。
@MainActor
final class StatsStore: ObservableObject {
    @Published var entries: [PlayEntry] = []   // 時系列順（古い→新しい）
    @Published var isBusy = false
    @Published var statusText: String = ""
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
            let decoded = (try? Data(contentsOf: url))
                .flatMap { try? JSONDecoder().decode([PlayEntry].self, from: $0) } ?? []
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.entries = decoded
                self.isBusy = false
                self.statusText = decoded.isEmpty ? "" : "保存済みデータを読み込みました（\(Fmt.num(decoded.count)) 件）"
            }
        }
    }

    /// ZIP／JSONを取り込む。既存データとは重複を除いてマージされるので、
    /// 新しいZIPをそのまま読み直しても二重に数えられない。
    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty, !isBusy else { return }
        isBusy = true
        statusText = "読み込み中…"
        Task.detached(priority: .userInitiated) {
            var fresh: [PlayEntry] = []
            for url in urls {
                switch url.pathExtension.lowercased() {
                case "zip":
                    fresh += Self.parseZip(url)
                case "json":
                    if let data = try? Data(contentsOf: url) {
                        fresh += HistoryParser.parse(data: data)
                    }
                default:
                    break
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if fresh.isEmpty {
                    self.statusText = "再生履歴のJSONが見つかりませんでした。Spotifyの「拡張ストリーミング履歴」のzipかどうか確認してください。"
                } else {
                    var seen = Set(self.entries.map { "\($0.t)|\($0.key)|\($0.ms)" })
                    var added = 0
                    for e in fresh {
                        let k = "\(e.t)|\(e.key)|\(e.ms)"
                        if !seen.contains(k) {
                            seen.insert(k)
                            self.entries.append(e)
                            added += 1
                        }
                    }
                    self.entries.sort { $0.t < $1.t }
                    self.saveSnapshot(self.entries)
                    self.statusText = added > 0
                        ? "\(Fmt.num(added)) 件を追加しました（全 \(Fmt.num(self.entries.count)) 件）"
                        : "新しい再生履歴はありませんでした（全 \(Fmt.num(self.entries.count)) 件）"
                }
                self.isBusy = false
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
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    nonisolated private static func parseZip(_ url: URL) -> [PlayEntry] {
        guard let archive = try? Archive(url: url, accessMode: .read) else { return [] }
        var out: [PlayEntry] = []
        for entry in archive where entry.type == .file && HistoryParser.isHistoryJson(entry.path) {
            var data = Data()
            _ = try? archive.extract(entry) { chunk in
                data.append(chunk)
            }
            out += HistoryParser.parse(data: data)
        }
        return out
    }
}
