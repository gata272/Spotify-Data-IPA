import SwiftUI

struct ArtistView: View {
    @EnvironmentObject private var store: StatsStore
    @EnvironmentObject private var model: AppModel

    private var list: [PlayEntry] { model.filtered(store.entries) }

    var body: some View {
        NavigationStack {
            if model.artist.isEmpty {
                artistPicker
            } else {
                artistDetail
            }
        }
    }

    // MARK: - アーティスト選択

    private var artistPicker: some View {
        let agg = Aggregator.aggregate(list)
        let artists = Aggregator.sortArtists(agg.artists, byTime: false)
        return List {
            Section {
                Text("アーティストを選ぶと、そのアーティストの曲ランキング・ハイライト・月ごと／日ごと／時間帯ごとの統計が見られます。ランキングタブでアーティスト名をタップしても開けます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("アーティスト（再生回数順）") {
                ForEach(Array(artists.prefix(200).enumerated()), id: \.offset) { i, a in
                    Button {
                        model.artist = a.name
                    } label: {
                        RankRowView(rank: i + 1, name: a.name,
                                    sub: "\(Fmt.num(a.trackKeys.count)) 曲",
                                    big: "\(Fmt.num(a.plays)) 回",
                                    small: Fmt.dur(ms: a.ms),
                                    fraction: artists.first.map { Double(a.plays) / Double(max($0.plays, 1)) } ?? 0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("アーティスト")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - アーティスト詳細

    @State private var byTime: Bool = false
    @State private var shown: Int = 50

    private var mine: [PlayEntry] { list.filter { $0.artist == model.artist } }

    private var artistDetail: some View {
        let trows = trackRows
        return List {
            Section {
                HStack {
                    Text(model.artist)
                        .font(.title3)
                        .fontWeight(.black)
                        .lineLimit(2)
                    Spacer()
                    Button("絞り込みを解除") {
                        model.artist = ""
                    }
                    .font(.subheadline)
                }
                artistStats
            }

            Section("曲ランキング") {
                Picker("並び替え", selection: $byTime) {
                    Text("再生回数順").tag(false)
                    Text("再生時間順").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                if trows.isEmpty {
                    Text("この期間にこのアーティストの再生履歴がありません。")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(trows.prefix(shown).enumerated()), id: \.offset) { i, row in
                    RankRowView(rank: i + 1, name: row.name, sub: row.sub,
                                big: row.big, small: row.small, fraction: row.fraction)
                }
                if trows.count > shown {
                    Button("もっと見る（残り \(Fmt.num(trows.count - shown)) 件）") {
                        shown += 100
                    }
                }
            }

            if let ins = ArtistInsights.compute(list: mine, all: store.entries, artist: model.artist) {
                Section("\(model.artist) のハイライト") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        InsightCardView(title: "いちばん聴いた日", value: Fmt.date(ins.bestDay),
                                        sub: "\(Fmt.dur(ms: ins.bestDayMs)) ／ \(Fmt.num(ins.bestDayPlays))回聴きました")
                        InsightCardView(title: "よく聴く時間帯", value: "\(ins.peakHour)時台",
                                        sub: "この期間に \(Fmt.num(ins.peakHourPlays)) 回再生")
                        InsightCardView(title: "いちばん聴く曜日", value: Fmt.weekdayNames[ins.topWeekday] + "曜日",
                                        sub: "このアーティストの再生時間の \(ins.topWeekdayShare)%")
                        InsightCardView(title: "最も聴いた曲", value: ins.topTrackName ?? "—",
                                        sub: "\(Fmt.num(ins.topTrackPlays))回 ／ \(Fmt.dur(ms: ins.topTrackMs))")
                        InsightCardView(title: "連続で聴いた最長記録", value: "\(Fmt.num(ins.streak)) 日連続",
                                        sub: "リピート率 \(ins.repeatRate)%")
                        InsightCardView(title: "初めて聴いた日", value: ins.firstEver.map { Fmt.date($0) } ?? "—",
                                        sub: ins.periodFirst.map { "この期間の初回は " + Fmt.date($0) } ?? "")
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
            }

            Section("\(model.artist) ・ 月ごとの再生時間") {
                SimpleBarChart(items: monthItems, valueFormat: { Fmt.dur(ms: $0) })
            }
            Section("\(model.artist) ・ 日ごとの再生時間") {
                SimpleBarChart(items: dayItems, valueFormat: { Fmt.dur(ms: $0) }, showAxisLabels: dayItems.count <= 62)
            }
            Section("\(model.artist) ・ 時間帯ごとの再生回数") {
                SimpleBarChart(items: hourItems, valueFormat: { "\(Fmt.num($0)) 回" })
            }
        }
        .navigationTitle("アーティスト")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.artist) { _, _ in shown = 50 }
    }

    private var artistStats: some View {
        let totalMs = list.reduce(0) { $0 + $1.ms }
        let myMs = mine.reduce(0) { $0 + $1.ms }
        let agg = Aggregator.aggregate(mine)
        let albums = Set(mine.map { $0.album }).subtracting([""]).count
        let share = totalMs > 0 ? Double(myMs) / Double(totalMs) * 100 : 0
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            StatCardView(title: "再生回数", value: "\(Fmt.num(mine.count)) 回")
            StatCardView(title: "再生時間", value: Fmt.dur(ms: myMs))
            StatCardView(title: "全体に占める割合", value: String(format: "%.1f%%", share))
            StatCardView(title: "曲数", value: "\(Fmt.num(agg.tracks.count)) 曲")
            StatCardView(title: "アルバム数", value: "\(Fmt.num(albums)) 枚")
            StatCardView(title: "この期間の初回再生", value: mine.first.map { Fmt.date($0.date) } ?? "—")
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
    }

    private struct TRow {
        var name: String
        var sub: String
        var big: String
        var small: String
        var fraction: Double
    }

    private var trackRows: [TRow] {
        let agg = Aggregator.aggregate(mine)
        let arr = Aggregator.sortTracks(agg.tracks, byTime: byTime)
        let maxVal = arr.first.map { byTime ? $0.ms : $0.plays } ?? 0
        return arr.map { t in
            TRow(name: t.name,
                 sub: t.album,
                 big: byTime ? Fmt.dur(ms: t.ms) : "\(Fmt.num(t.plays)) 回",
                 small: byTime ? "\(Fmt.num(t.plays)) 回" : Fmt.dur(ms: t.ms),
                 fraction: maxVal > 0 ? Double(byTime ? t.ms : t.plays) / Double(maxVal) : 0)
        }
    }

    private var monthItems: [BarItem] {
        var map: [String: Int] = [:]
        var order: [String] = []
        for e in mine {
            let label = Fmt.monthLabel(e.date)
            if map[label] == nil { order.append(label) }
            map[label, default: 0] += e.ms
        }
        return order.map { BarItem(label: $0, value: map[$0] ?? 0) }
    }

    private var dayItems: [BarItem] {
        DayAggregator.filledDays(mine).map { row in
            BarItem(label: Fmt.date(row.date), value: row.ms, sub: "\(Fmt.num(row.plays)) 回")
        }
    }

    private var hourItems: [BarItem] {
        var plays = [Int](repeating: 0, count: 24)
        for e in mine {
            plays[Calendar.current.component(.hour, from: e.date)] += 1
        }
        return (0..<24).map { BarItem(label: "\($0)時台", value: plays[$0]) }
    }
}
