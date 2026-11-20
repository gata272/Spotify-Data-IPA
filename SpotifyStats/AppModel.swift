import Foundation

/// 期間・条件・アーティスト絞り込みと、選択中タブの状態
final class AppModel: ObservableObject {
    @Published var tab: Int = 0
    @Published var preset: String = "all"
    @Published var from: Date = Date()
    @Published var to: Date = Date()
    @Published var minPlay30: Bool = false
    @Published var includePodcast: Bool = false
    @Published var artist: String = ""
    /// データ初回読み込み時に期間を全期間へ初期化したかどうか
    var periodInitialized = false
    /// タブ画面を表示してよい状態か。データの読み戻しが終わってから
    /// trueにし、重い集計は画面表示後に走らせる
    @Published var ready = false

    var minMs: Int { minPlay30 ? 30000 : 0 }

    /// Web版 setPreset と同じ計算（日単位）
    func applyPreset(_ p: String, dataMin: Date, dataMax: Date) {
        preset = p
        let cal = Calendar.current
        let minDay = DayCalc.dayStart(dataMin)
        let maxDay = DayCalc.dayStart(dataMax)
        var f = minDay
        var t = maxDay
        if p == "30d" || p == "90d" || p == "180d" || p == "365d" {
            let days = Int(p.dropLast()) ?? 30
            f = cal.date(byAdding: .day, value: -(days - 1), to: maxDay) ?? maxDay
            if f < minDay { f = minDay }
        } else if p == "ytd" {
            f = cal.date(from: DateComponents(year: cal.component(.year, from: dataMax), month: 1, day: 1)) ?? minDay
            if f < minDay { f = minDay }
        } else if p.hasPrefix("year:") {
            let yr = Int(p.dropFirst(5)) ?? 0
            f = cal.date(from: DateComponents(year: yr, month: 1, day: 1)) ?? minDay
            t = cal.date(from: DateComponents(year: yr, month: 12, day: 31)) ?? maxDay
            if f < minDay { f = minDay }
            if t > maxDay { t = maxDay }
        }
        from = f
        to = t
    }

    /// 現在の期間・条件で絞った再生（アーティスト絞り込みは含まない）
    func filtered(_ entries: [PlayEntry]) -> [PlayEntry] {
        let fromT = Int64(DayCalc.dayStart(from).timeIntervalSince1970 * 1000)
        let toT = Int64(DayCalc.dayStart(to).timeIntervalSince1970 * 1000) + 86_400_000 - 1
        return entries.filter {
            $0.t >= fromT && $0.t <= toT && $0.ms >= minMs && (includePodcast || !$0.ep)
        }
    }

    func years(in entries: [PlayEntry]) -> [Int] {
        var set = Set<Int>()
        for e in entries { set.insert(Calendar.current.component(.year, from: e.date)) }
        return set.sorted()
    }
}
