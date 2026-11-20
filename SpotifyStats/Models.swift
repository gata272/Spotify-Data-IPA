import Foundation

// MARK: - データモデル

/// Spotify拡張ストリーミング履歴の1件分の再生記録
struct PlayEntry: Codable {
    var t: Int64      // 再生終了時刻（エポックミリ秒）
    var ms: Int       // 再生時間（ミリ秒）
    var track: String
    var artist: String
    var album: String
    var key: String   // spotify_track_uri、無ければ track|artist
    var ep: Bool      // ポッドキャスト／オーディオブック

    var date: Date { Date(timeIntervalSince1970: Double(t) / 1000.0) }
}

// MARK: - 表示用フォーマット（Web版と表記をそろえる）

enum Fmt {
    private static let numFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    static func num(_ n: Int) -> String {
        numFmt.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// 4523000ms -> "75時間23分" / "23分45秒" / "45秒"
    static func dur(ms: Int) -> String {
        let s = (ms + 500) / 1000
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return num(h) + "時間" + (m > 0 ? "\(m)分" : "") }
        if m > 0 { return "\(m)分" + (sec > 0 ? "\(sec)秒" : "") }
        return "\(sec)秒"
    }

    static func date(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)年\(c.month ?? 0)月\(c.day ?? 0)日"
    }

    static func monthLabel(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: d)
        return "\(c.year ?? 0)年\(c.month ?? 0)月"
    }

    static let weekdayNames = ["日", "月", "火", "水", "木", "金", "土"] // 0=日曜
}

// MARK: - 日付計算

enum DayCalc {
    /// 日単位の連番（連続日数＝ストリーク計算用）。days_from_civil アルゴリズム
    static func ordinal(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        var y = c.year ?? 1970
        let m = c.month ?? 1
        let day = c.day ?? 1
        if m <= 2 { y -= 1 }
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    static func dayStart(_ d: Date) -> Date {
        Calendar.current.startOfDay(for: d)
    }
}

// MARK: - JSONパース

enum HistoryParser {
    /// 拡張履歴のJSONファイル名かどうか（Web版の判定と同一）
    static func isHistoryJson(_ name: String) -> Bool {
        let base = (name as NSString).lastPathComponent.lowercased()
        guard base.hasSuffix(".json") else { return false }
        return base.hasPrefix("streaming_history_audio_")
            || base.hasPrefix("streaming_history_video_")
            || base.hasPrefix("endsong")
            || base.hasPrefix("streaminghistory")
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// 旧形式の endTime（"2023-02-19 12:34"、UTCとして解釈する。Web版と同一）
    private static let legacyFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func parseISO(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    /// 履歴オブジェクト1件をPlayEntryに変換する（parse本体とストリーミング版で共用）
    static func convertOne(_ d: [String: Any]) -> PlayEntry? {
        let single = convert([d])
        return single.first
    }

    static func parse(data: Data) -> [PlayEntry] {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let arr = obj as? [[String: Any]] else { return [] }
        return convert(arr)
    }

    private static func convert(_ arr: [[String: Any]]) -> [PlayEntry] {
        var out: [PlayEntry] = []
        out.reserveCapacity(arr.count)
        for d in arr {
            if let ts = d["ts"] as? String {
                guard let date = parseISO(ts) else { continue }
                let ms = (d["ms_played"] as? NSNumber)?.intValue ?? 0
                let t = Int64(date.timeIntervalSince1970 * 1000)
                if let track = d["master_metadata_track_name"] as? String {
                    let artist = d["master_metadata_album_artist_name"] as? String
                    out.append(PlayEntry(
                        t: t, ms: ms, track: track,
                        artist: artist ?? "（不明なアーティスト）",
                        album: d["master_metadata_album_album_name"] as? String ?? "",
                        key: d["spotify_track_uri"] as? String ?? (track + "|" + (artist ?? "")),
                        ep: false))
                } else if let epName = d["episode_name"] as? String {
                    let show = d["episode_show_name"] as? String
                    out.append(PlayEntry(
                        t: t, ms: ms, track: epName,
                        artist: show ?? "（不明な番組）",
                        album: "",
                        key: d["spotify_episode_uri"] as? String ?? (epName + "|" + (show ?? "")),
                        ep: true))
                } else if let abTitle = d["audiobook_title"] as? String {
                    out.append(PlayEntry(
                        t: t, ms: ms,
                        track: d["audiobook_chapter_title"] as? String ?? abTitle,
                        artist: abTitle,
                        album: "",
                        key: d["audiobook_uri"] as? String ?? abTitle,
                        ep: true))
                }
            } else if let endTime = d["endTime"] as? String,
                      let track = d["trackName"] as? String {
                guard let date = legacyFmt.date(from: endTime + ":00") else { continue }
                let artist = d["artistName"] as? String
                out.append(PlayEntry(
                    t: Int64(date.timeIntervalSince1970 * 1000),
                    ms: (d["msPlayed"] as? NSNumber)?.intValue ?? 0,
                    track: track,
                    artist: artist ?? "（不明なアーティスト）",
                    album: "",
                    key: track + "|" + (artist ?? ""),
                    ep: false))
            }
        }
        return out
    }
}

/// ストリーミング読み込み：トップレベルの配列要素を1件ずつ切り出して変換する。
/// ファイル全体をJSONSerializationで変換すると、元の履歴オブジェクト（1件あたり
/// 約25項目）を全件分メモリに抱えることになり、LiveContainer内では処理が
/// 事実上止まって見える。ここでは変換済みの小さなPlayEntryだけを保持し、
/// 元のオブジェクトはその場で捨てる。進捗コールバックつき。
enum StreamingHistoryParser {
    static func parse(data: Data, progress: ((Int) -> Void)? = nil) -> [PlayEntry] {
        guard let text = String(data: data, encoding: .utf8) else {
            return HistoryParser.parse(data: data)
        }
        let scalars = Array(text.unicodeScalars)
        let n = scalars.count
        var out: [PlayEntry] = []
        out.reserveCapacity(20000)
        var i = 0
        while i < n && scalars[i] != "[" { i += 1 }
        i += 1
        var depth = 0
        var inStr = false
        var esc = false
        var start = -1
        var converted = 0
        while i < n {
            let c = scalars[i]
            if inStr {
                if esc { esc = false }
                else if c == "\\" { esc = true }
                else if c == "\"" { inStr = false }
                i += 1
                continue
            }
            if c == "\"" { inStr = true; i += 1; continue }
            if c == "{" {
                if depth == 0 { start = i }
                depth += 1; i += 1; continue
            }
            if c == "}" {
                depth -= 1
                i += 1
                if depth == 0 && start >= 0 {
                    let slice = String(String.UnicodeScalarView(scalars[start..<i]))
                    if let d = slice.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: d),
                       let dict = obj as? [String: Any],
                       let e = HistoryParser.convertOne(dict) {
                        out.append(e)
                    }
                    start = -1
                    converted += 1
                    if converted % 2000 == 0 { progress?(out.count) }
                }
                continue
            }
            if c == "]" && depth == 0 { break }
            i += 1
        }
        if out.isEmpty && (text.contains("\"ts\"") || text.contains("\"endTime\"")) {
            return HistoryParser.parse(data: data) // 念のための従来方式フォールバック
        }
        return out
    }
}

// MARK: - 集計

struct ArtistAgg {
    var name: String
    var plays: Int = 0
    var ms: Int = 0
    var trackKeys: Set<String> = []
}

struct TrackAgg {
    var key: String
    var name: String
    var artist: String
    var album: String
    var plays: Int = 0
    var ms: Int = 0
}

enum Aggregator {
    static func aggregate(_ list: [PlayEntry]) -> (artists: [String: ArtistAgg], tracks: [String: TrackAgg]) {
        var artists: [String: ArtistAgg] = [:]
        var tracks: [String: TrackAgg] = [:]
        for e in list {
            var a = artists[e.artist] ?? ArtistAgg(name: e.artist)
            a.plays += 1
            a.ms += e.ms
            a.trackKeys.insert(e.key)
            artists[e.artist] = a

            var tr = tracks[e.key] ?? TrackAgg(key: e.key, name: e.track, artist: e.artist, album: e.album)
            tr.plays += 1
            tr.ms += e.ms
            tracks[e.key] = tr
        }
        return (artists, tracks)
    }

    static func sortArtists(_ map: [String: ArtistAgg], byTime: Bool) -> [ArtistAgg] {
        map.values.sorted { a, b in
            let d = byTime ? a.ms - b.ms : a.plays - b.plays
            if d != 0 { return d > 0 }
            return byTime ? a.plays > b.plays : a.ms > b.ms
        }
    }

    static func sortTracks(_ map: [String: TrackAgg], byTime: Bool) -> [TrackAgg] {
        map.values.sorted { a, b in
            let d = byTime ? a.ms - b.ms : a.plays - b.plays
            if d != 0 { return d > 0 }
            return byTime ? a.plays > b.plays : a.ms > b.ms
        }
    }
}

// MARK: - 日ごと集計

struct DayAgg {
    var date: Date
    var ms: Int = 0
    var plays: Int = 0
}

enum DayAggregator {
    /// 再生があった日だけ（昇順）
    static func daysPresent(_ list: [PlayEntry]) -> [DayAgg] {
        var map: [Int: DayAgg] = [:]
        for e in list {
            let ord = DayCalc.ordinal(e.date)
            var r = map[ord] ?? DayAgg(date: DayCalc.dayStart(e.date))
            r.ms += e.ms
            r.plays += 1
            map[ord] = r
        }
        return map.values.sorted { $0.date < $1.date }
    }

    /// 最初から最後まで全日（再生0の日も含む、昇順）
    static func filledDays(_ list: [PlayEntry]) -> [DayAgg] {
        guard let first = list.first, let last = list.last else { return [] }
        var map: [Int: DayAgg] = [:]
        for e in list {
            let ord = DayCalc.ordinal(e.date)
            var r = map[ord] ?? DayAgg(date: DayCalc.dayStart(e.date))
            r.ms += e.ms
            r.plays += 1
            map[ord] = r
        }
        let startOrd = DayCalc.ordinal(first.date)
        let endOrd = DayCalc.ordinal(last.date)
        var out: [DayAgg] = []
        out.reserveCapacity(endOrd - startOrd + 1)
        var d = DayCalc.dayStart(first.date)
        for ord in startOrd...endOrd {
            out.append(map[ord] ?? DayAgg(date: d))
            d = Calendar.current.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return out
    }
}

// MARK: - ハイライト（全体）

struct Insights {
    var bestDay: Date
    var bestDayMs: Int
    var bestDayPlays: Int
    var peakHour: Int
    var peakHourPlays: Int
    var topWeekday: Int        // 0=日曜
    var topWeekdayShare: Int   // %
    var streak: Int            // 連続で聴いた最長日数
    var discoveries: Int       // 期間内に初めて聴いた曲数
    var repeatRate: Int        // %
    var activeDays: Int
    var lateNightShare: Int    // 0〜4時台の再生時間割合 %
    var topArtistName: String?
    var topArtistShare: Int    // %

    /// list: 期間で絞った再生、all: 読み込んだ全再生（時系列順）
    static func compute(list: [PlayEntry], all: [PlayEntry]) -> Insights? {
        guard !list.isEmpty else { return nil }
        var totalMs = 0
        var hourPlays = [Int](repeating: 0, count: 24)
        var wdMs = [Int](repeating: 0, count: 7)
        var dayMs: [Int: Int] = [:]
        var dayPlays: [Int: Int] = [:]
        var dayDate: [Int: Date] = [:]
        var trackPlays: [String: Int] = [:]
        var firstPlay: [String: Int64] = [:]
        var lateMs = 0
        let cal = Calendar.current
        for e in list {
            totalMs += e.ms
            let d = e.date
            let hour = cal.component(.hour, from: d)
            hourPlays[hour] += 1
            wdMs[cal.component(.weekday, from: d) - 1] += e.ms
            let ord = DayCalc.ordinal(d)
            dayMs[ord, default: 0] += e.ms
            dayPlays[ord, default: 0] += 1
            dayDate[ord] = DayCalc.dayStart(d)
            trackPlays[e.key, default: 0] += 1
            if firstPlay[e.key] == nil || e.t < firstPlay[e.key]! { firstPlay[e.key] = e.t }
            if hour < 5 { lateMs += e.ms }
        }

        var bestOrd = -1, bestMs = -1
        for (k, v) in dayMs where v > bestMs { bestMs = v; bestOrd = k }
        var peakHour = 0
        for h in 1..<24 where hourPlays[h] > hourPlays[peakHour] { peakHour = h }
        var topWd = 0
        for w in 1..<7 where wdMs[w] > wdMs[topWd] { topWd = w }
        let wdShare = totalMs > 0 ? Int((Double(wdMs[topWd]) / Double(totalMs) * 100).rounded()) : 0

        let ords = dayMs.keys.sorted()
        var streak = 0, run = 0, prev = Int.min
        for o in ords {
            run = (o == prev + 1) ? run + 1 : 1
            streak = max(streak, run)
            prev = o
        }

        var firstEver: [String: Int64] = [:]
        for e in all where firstEver[e.key] == nil { firstEver[e.key] = e.t }
        var discoveries = 0
        for (k, fp) in firstPlay where firstEver[k] == fp { discoveries += 1 }

        let repeatRate = Int((Double(list.count - trackPlays.count) / Double(max(list.count, 1)) * 100).rounded())
        let lateShare = totalMs > 0 ? Int((Double(lateMs) / Double(totalMs) * 100).rounded()) : 0

        let agg = Aggregator.aggregate(list)
        let topA = Aggregator.sortArtists(agg.artists, byTime: true).first
        let topShare = (topA != nil && totalMs > 0) ? Int((Double(topA!.ms) / Double(totalMs) * 100).rounded()) : 0

        return Insights(
            bestDay: dayDate[bestOrd] ?? list[0].date,
            bestDayMs: max(bestMs, 0),
            bestDayPlays: dayPlays[bestOrd] ?? 0,
            peakHour: peakHour,
            peakHourPlays: hourPlays[peakHour],
            topWeekday: topWd,
            topWeekdayShare: wdShare,
            streak: streak,
            discoveries: discoveries,
            repeatRate: repeatRate,
            activeDays: ords.count,
            lateNightShare: lateShare,
            topArtistName: topA?.name,
            topArtistShare: topShare)
    }
}

// MARK: - ハイライト（アーティスト別）

struct ArtistInsights {
    var bestDay: Date
    var bestDayMs: Int
    var bestDayPlays: Int
    var peakHour: Int
    var peakHourPlays: Int
    var topWeekday: Int
    var topWeekdayShare: Int
    var topTrackName: String?
    var topTrackPlays: Int
    var topTrackMs: Int
    var streak: Int
    var repeatRate: Int
    var firstEver: Date?
    var periodFirst: Date?

    static func compute(list: [PlayEntry], all: [PlayEntry], artist: String) -> ArtistInsights? {
        guard !list.isEmpty else { return nil }
        var totalMs = 0
        var hourPlays = [Int](repeating: 0, count: 24)
        var wdMs = [Int](repeating: 0, count: 7)
        var dayMs: [Int: Int] = [:]
        var dayPlays: [Int: Int] = [:]
        var dayDate: [Int: Date] = [:]
        var trackAgg: [String: (name: String, plays: Int, ms: Int)] = [:]
        let cal = Calendar.current
        for e in list {
            totalMs += e.ms
            let d = e.date
            hourPlays[cal.component(.hour, from: d)] += 1
            wdMs[cal.component(.weekday, from: d) - 1] += e.ms
            let ord = DayCalc.ordinal(d)
            dayMs[ord, default: 0] += e.ms
            dayPlays[ord, default: 0] += 1
            dayDate[ord] = DayCalc.dayStart(d)
            var tr = trackAgg[e.key] ?? (name: e.track, plays: 0, ms: 0)
            tr.plays += 1
            tr.ms += e.ms
            trackAgg[e.key] = tr
        }

        var bestOrd = -1, bestMs = -1
        for (k, v) in dayMs where v > bestMs { bestMs = v; bestOrd = k }
        var peakHour = 0
        for h in 1..<24 where hourPlays[h] > hourPlays[peakHour] { peakHour = h }
        var topWd = 0
        for w in 1..<7 where wdMs[w] > wdMs[topWd] { topWd = w }
        let wdShare = totalMs > 0 ? Int((Double(wdMs[topWd]) / Double(totalMs) * 100).rounded()) : 0

        let ords = dayMs.keys.sorted()
        var streak = 0, run = 0, prev = Int.min
        for o in ords {
            run = (o == prev + 1) ? run + 1 : 1
            streak = max(streak, run)
            prev = o
        }

        let topTrack = trackAgg.values.max { $0.plays < $1.plays }
        let repeatRate = Int((Double(list.count - trackAgg.count) / Double(max(list.count, 1)) * 100).rounded())
        let firstEver = all.first { $0.artist == artist }?.date

        return ArtistInsights(
            bestDay: dayDate[bestOrd] ?? list[0].date,
            bestDayMs: max(bestMs, 0),
            bestDayPlays: dayPlays[bestOrd] ?? 0,
            peakHour: peakHour,
            peakHourPlays: hourPlays[peakHour],
            topWeekday: topWd,
            topWeekdayShare: wdShare,
            topTrackName: topTrack?.name,
            topTrackPlays: topTrack?.plays ?? 0,
            topTrackMs: topTrack?.ms ?? 0,
            streak: streak,
            repeatRate: repeatRate,
            firstEver: firstEver,
            periodFirst: list.first?.date)
    }
}

// MARK: - 前期間との比較

struct PeriodComparison {
    var curMs: Int
    var prevMs: Int
    var curPlays: Int
    var prevPlays: Int
    var curTopArtist: String?
    var prevTopArtist: String?
    var hasPrev: Bool
}

enum Comparator {
    /// 選択期間と、その直前の同じ日数の期間を比べる（30秒／ポッドキャスト条件は同じ、アーティスト絞り込みは除く）
    static func compare(entries: [PlayEntry], from: Date, to: Date, minMs: Int, includePodcast: Bool) -> PeriodComparison {
        let cal = Calendar.current
        let fromStart = DayCalc.dayStart(from)
        let toStart = DayCalc.dayStart(to)
        let spanDays = DayCalc.ordinal(toStart) - DayCalc.ordinal(fromStart) + 1
        let curFrom = Int64(fromStart.timeIntervalSince1970 * 1000)
        let curTo = Int64(toStart.timeIntervalSince1970 * 1000) + 86_400_000 - 1
        let prevTo = curFrom - 1
        let prevFrom = curFrom - Int64(spanDays) * 86_400_000

        var curMs = 0, prevMs = 0, curPlays = 0, prevPlays = 0
        var curArtists: [String: Int] = [:]
        var prevArtists: [String: Int] = [:]
        for e in entries {
            if e.ms < minMs || (!includePodcast && e.ep) { continue }
            if e.t >= curFrom && e.t <= curTo {
                curMs += e.ms; curPlays += 1; curArtists[e.artist, default: 0] += e.ms
            } else if e.t >= prevFrom && e.t <= prevTo {
                prevMs += e.ms; prevPlays += 1; prevArtists[e.artist, default: 0] += e.ms
            }
        }
        _ = cal
        return PeriodComparison(
            curMs: curMs, prevMs: prevMs,
            curPlays: curPlays, prevPlays: prevPlays,
            curTopArtist: curArtists.max { $0.value < $1.value }?.key,
            prevTopArtist: prevArtists.max { $0.value < $1.value }?.key,
            hasPrev: prevPlays > 0)
    }
}
