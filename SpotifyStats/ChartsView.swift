import SwiftUI
import Charts

/// グラフの1本分
struct BarItem: Identifiable {
    var id: String { label }
    var label: String       // 選択の識別と読み上げ表示に使う
    var value: Int
    var sub: String = ""    // 読み上げ表示の補足（例：再生回数）
}

/// タップで値が大きく表示される棒グラフ（Web版のタップ表示をネイティブで再現）
struct SimpleBarChart: View {
    var items: [BarItem]
    var valueFormat: (Int) -> String
    var showAxisLabels: Bool = true
    @State private var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(items) { item in
                BarMark(
                    x: .value("項目", item.label),
                    y: .value("値", item.value)
                )
                .foregroundStyle(selected == item.label ? Color.orange : Color.spotifyGreen)
                .cornerRadius(3)
            }
            .chartXSelection(value: $selected)
            .chartXAxis(showAxisLabels ? .automatic : .hidden)
            .frame(height: 170)

            if let sel = items.first(where: { $0.label == selected }) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(sel.label)
                        .fontWeight(.black)
                    Text(valueFormat(sel.value))
                        .fontWeight(.black)
                        .foregroundStyle(Color.spotifyGreen)
                    if !sel.sub.isEmpty {
                        Text(sel.sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            } else {
                Text("グラフをタップすると、その項目の値がここに大きく表示されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

/// 月ごと／日ごと／時間帯／曜日別のグラフタブ
struct ChartsView: View {
    @EnvironmentObject private var store: StatsStore
    @EnvironmentObject private var model: AppModel
    @State private var daySort: Int = 0   // 0=日付が新しい順 1=再生時間順 2=再生回数順
    @State private var dayShown: Int = 31

    private var list: [PlayEntry] { model.filtered(store.entries) }
    private var scoped: [PlayEntry] {
        model.artist.isEmpty ? list : list.filter { $0.artist == model.artist }
    }

    var body: some View {
        let months = monthItems
        let days = dayItems
        let hours = hourItems
        let weekdays = weekdayItems
        let dayRows = sortedDayRows
        let note = dayNote
        return NavigationStack {
            List {
                if !model.artist.isEmpty {
                    Section {
                        Text("アーティスト「\(model.artist)」で絞り込み中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("月ごとの再生時間") {
                    SimpleBarChart(items: months, valueFormat: { Fmt.dur(ms: $0) })
                    if let best = months.max(by: { $0.value < $1.value }) {
                        Text("最も多かった月：\(best.label)（\(Fmt.dur(ms: best.value))）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("日ごとの再生") {
                    SimpleBarChart(items: days, valueFormat: { Fmt.dur(ms: $0) }, showAxisLabels: days.count <= 62)
                    Picker("並び替え", selection: $daySort) {
                        Text("日付が新しい順").tag(0)
                        Text("再生時間順").tag(1)
                        Text("再生回数順").tag(2)
                    }
                    .pickerStyle(.segmented)
                    ForEach(Array(dayRows.prefix(dayShown).enumerated()), id: \.offset) { _, row in
                        DayRowView(row: row)
                    }
                    if dayRows.count > dayShown {
                        Button("もっと見る（残り \(Fmt.num(dayRows.count - dayShown)) 日）") {
                            dayShown += 62
                        }
                    }
                    if let note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("時間帯ごとの再生回数") {
                    SimpleBarChart(items: hours, valueFormat: { "\(Fmt.num($0)) 回" })
                    if let peak = hours.max(by: { $0.value < $1.value }) {
                        Text("ピークは \(peak.label)（\(Fmt.num(peak.value))回）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("曜日ごとの再生時間") {
                    SimpleBarChart(items: weekdays, valueFormat: { Fmt.dur(ms: $0) })
                }
            }
            .navigationTitle("グラフ")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 集計

    private var monthItems: [BarItem] {
        var map: [String: Int] = [:]
        var order: [String] = []
        for e in scoped {
            let label = Fmt.monthLabel(e.date)
            if map[label] == nil { order.append(label) }
            map[label, default: 0] += e.ms
        }
        // entriesは時系列順なので、出現順＝月順になる
        return order.map { BarItem(label: $0, value: map[$0] ?? 0) }
    }

    private var filled: [DayAgg] { DayAggregator.filledDays(scoped) }

    private var dayItems: [BarItem] {
        filled.map { row in
            BarItem(label: Fmt.date(row.date), value: row.ms, sub: "\(Fmt.num(row.plays)) 回")
        }
    }

    private var sortedDayRows: [DayAgg] {
        let rows = DayAggregator.daysPresent(scoped)
        switch daySort {
        case 1: return rows.sorted { $0.ms != $1.ms ? $0.ms > $1.ms : $0.plays > $1.plays }
        case 2: return rows.sorted { $0.plays != $1.plays ? $0.plays > $1.plays : $0.ms > $1.ms }
        default: return rows.sorted { $0.date > $1.date }
        }
    }

    private var dayNote: String? {
        let rows = filled
        guard !rows.isEmpty, let best = rows.max(by: { $0.ms < $1.ms }) else { return nil }
        let total = rows.reduce(0) { $0 + $1.ms }
        let avg = rows.isEmpty ? 0 : total / rows.count
        let active = rows.filter { $0.plays > 0 }.count
        return "最も多かった日：\(Fmt.date(best.date))（\(Fmt.dur(ms: best.ms)) ／ \(Fmt.num(best.plays))回）／ 1日平均 \(Fmt.dur(ms: avg)) ／ 聴いた日 \(Fmt.num(active))日（期間 \(Fmt.num(rows.count))日中）"
    }

    private var hourItems: [BarItem] {
        var plays = [Int](repeating: 0, count: 24)
        for e in scoped {
            plays[Calendar.current.component(.hour, from: e.date)] += 1
        }
        return (0..<24).map { BarItem(label: "\($0)時台", value: plays[$0]) }
    }

    private var weekdayItems: [BarItem] {
        var ms = [Int](repeating: 0, count: 7)
        for e in scoped {
            ms[Calendar.current.component(.weekday, from: e.date) - 1] += e.ms
        }
        return (0..<7).map { BarItem(label: Fmt.weekdayNames[$0] + "曜日", value: ms[$0]) }
    }
}
