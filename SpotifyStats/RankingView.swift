import SwiftUI

struct RankingView: View {
    @EnvironmentObject private var store: StatsStore
    @EnvironmentObject private var model: AppModel
    @State private var target: Int = 0    // 0=アーティスト 1=曲
    @State private var byTime: Bool = false
    @State private var query: String = ""
    @State private var shown: Int = 50

    private var list: [PlayEntry] { model.filtered(store.entries) }

    var body: some View {
        let rows = self.rows
        return NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Picker("対象", selection: $target) {
                            Text("アーティスト").tag(0)
                            Text("曲").tag(1)
                        }
                        .pickerStyle(.segmented)
                        Picker("並び替え", selection: $byTime) {
                            Text("再生回数順").tag(false)
                            Text("再生時間順").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    TextField("名前で絞り込む…", text: $query)
                        .textFieldStyle(.roundedBorder)
                    if target == 0 {
                        Text("アーティスト名をタップすると、そのアーティストの詳細が見られます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
                .background(Color(.systemGroupedBackground))

                List {
                    if rows.isEmpty {
                        Text("この期間・条件に一致する再生履歴がありません。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(rows.prefix(shown).enumerated()), id: \.offset) { i, row in
                        if target == 0 {
                            Button {
                                model.artist = row.name
                                model.tab = 3
                            } label: {
                                RankRowView(rank: i + 1, name: row.name, sub: row.sub,
                                            big: row.big, small: row.small, fraction: row.fraction)
                            }
                            .buttonStyle(.plain)
                        } else {
                            RankRowView(rank: i + 1, name: row.name, sub: row.sub,
                                        big: row.big, small: row.small, fraction: row.fraction)
                        }
                    }
                    if rows.count > shown {
                        Button("もっと見る（残り \(Fmt.num(rows.count - shown)) 件）") {
                            shown += 100
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("ランキング")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: target) { _, _ in shown = 50 }
            .onChange(of: byTime) { _, _ in shown = 50 }
            .onChange(of: query) { _, _ in shown = 50 }
        }
    }

    private struct Row {
        var name: String
        var sub: String
        var big: String
        var small: String
        var fraction: Double
    }

    private var rows: [Row] {
        let agg = Aggregator.aggregate(list)
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if target == 0 {
            var arr = Aggregator.sortArtists(agg.artists, byTime: byTime)
            if !q.isEmpty { arr = arr.filter { $0.name.lowercased().contains(q) } }
            let maxVal = arr.first.map { byTime ? $0.ms : $0.plays } ?? 0
            return arr.map { a in
                Row(name: a.name,
                    sub: "\(Fmt.num(a.trackKeys.count)) 曲",
                    big: byTime ? Fmt.dur(ms: a.ms) : "\(Fmt.num(a.plays)) 回",
                    small: byTime ? "\(Fmt.num(a.plays)) 回" : Fmt.dur(ms: a.ms),
                    fraction: maxVal > 0 ? Double(byTime ? a.ms : a.plays) / Double(maxVal) : 0)
            }
        } else {
            var arr = Aggregator.sortTracks(agg.tracks, byTime: byTime)
            if !q.isEmpty {
                arr = arr.filter {
                    $0.name.lowercased().contains(q) || $0.artist.lowercased().contains(q) || $0.album.lowercased().contains(q)
                }
            }
            let maxVal = arr.first.map { byTime ? $0.ms : $0.plays } ?? 0
            return arr.map { t in
                Row(name: t.name,
                    sub: t.artist + (t.album.isEmpty ? "" : " ・ " + t.album),
                    big: byTime ? Fmt.dur(ms: t.ms) : "\(Fmt.num(t.plays)) 回",
                    small: byTime ? "\(Fmt.num(t.plays)) 回" : Fmt.dur(ms: t.ms),
                    fraction: maxVal > 0 ? Double(byTime ? t.ms : t.plays) / Double(maxVal) : 0)
            }
        }
    }
}
