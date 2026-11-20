import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: StatsStore
    @EnvironmentObject private var model: AppModel
    @State private var showDeleteConfirm = false
    @State private var shareItem: ShareableImage?

    private var list: [PlayEntry] { model.filtered(store.entries) }

    var body: some View {
        // 集計はbodyの入口でまとめて1回だけ行う。各セクションが個別に
        // 全件走査すると、画面が表示されるまで固まって見えるため
        let list = self.list
        let agg = Aggregator.aggregate(list)
        let topArtist = Aggregator.sortArtists(agg.artists, byTime: true).first
        let insights = Insights.compute(list: list, all: store.entries, topArtist: topArtist)
        let comparison = Comparator.compare(entries: store.entries, from: model.from, to: model.to,
                                            minMs: model.minMs, includePodcast: model.includePodcast)
        return NavigationStack {
            List {
                periodSection
                summarySection(list: list, agg: agg)
                insightsSection(insights: insights)
                compareSection(comparison: comparison)
                shareSection(list: list, agg: agg, insights: insights)
                dataSection
            }
            .navigationTitle("Spotify統計")
            .navigationBarTitleDisplayMode(.inline)
            .alert("データをすべて削除しますか？", isPresented: $showDeleteConfirm) {
                Button("削除する", role: .destructive) {
                    store.deleteAllData()
                    model.artist = ""
                    model.periodInitialized = false
                    model.ready = false
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("読み込んだ再生履歴がすべて消えます。再度zipを読み込めば復元できます。")
            }
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.image])
            }
        }
    }

    // MARK: - 期間

    private var periodSection: some View {
        Section("期間") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(presetList, id: \.key) { p in
                        Button(p.label) {
                            if let mn = store.dataMin, let mx = store.dataMax {
                                model.applyPreset(p.key, dataMin: mn, dataMax: mx)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(model.preset == p.key ? .green : .gray)
                    }
                }
                .padding(.vertical, 2)
            }
            DatePicker("開始日", selection: $model.from, displayedComponents: .date)
                .onChange(of: model.from) { _, _ in model.preset = "custom" }
            DatePicker("終了日", selection: $model.to, displayedComponents: .date)
                .onChange(of: model.to) { _, _ in model.preset = "custom" }
            Toggle("30秒未満の再生を数えない", isOn: $model.minPlay30)
            Toggle("ポッドキャストも含める", isOn: $model.includePodcast)
        }
    }

    private var presetList: [(key: String, label: String)] {
        var base: [(key: String, label: String)] = [
            ("all", "全期間"), ("30d", "直近30日"), ("90d", "直近3か月"),
            ("180d", "直近6か月"), ("365d", "直近1年"), ("ytd", "今年"),
        ]
        for y in model.years(in: store.entries) {
            base.append(("year:\(y)", "\(y)年"))
        }
        return base
    }

    // MARK: - サマリー

    private func summarySection(list: [PlayEntry], agg: (artists: [String: ArtistAgg], tracks: [String: TrackAgg])) -> some View {
        Section("サマリー") {
            let totalMs = list.reduce(0) { $0 + $1.ms }
            let days = list.isEmpty ? 0 : max(1, Int((Double(list[list.count - 1].t - list[0].t) / 86_400_000).rounded()) + 1)
            let top = Aggregator.sortArtists(agg.artists, byTime: true).first
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatCardView(title: "総再生時間", value: Fmt.dur(ms: totalMs),
                             sub: "1日平均 " + Fmt.dur(ms: days > 0 ? totalMs / days : 0))
                StatCardView(title: "総再生回数", value: "\(Fmt.num(list.count)) 回",
                             sub: "1日平均 " + (days > 0 ? Fmt.num(list.count / days) : "0") + " 回")
                StatCardView(title: "アーティスト数", value: "\(Fmt.num(agg.artists.count)) 組")
                StatCardView(title: "曲数", value: "\(Fmt.num(agg.tracks.count)) 曲",
                             sub: top.map { "最頻：" + $0.name } ?? "")
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        }
    }

    // MARK: - ハイライト

    private func insightsSection(insights: Insights?) -> some View {
        Section("この期間のハイライト") {
            if let ins = insights {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    InsightCardView(title: "いちばん聴いた日", value: Fmt.date(ins.bestDay),
                                    sub: "\(Fmt.dur(ms: ins.bestDayMs)) ／ \(Fmt.num(ins.bestDayPlays))回聴きました")
                    InsightCardView(title: "よく聴く時間帯", value: "\(ins.peakHour)時台",
                                    sub: "この期間に \(Fmt.num(ins.peakHourPlays)) 回再生")
                    InsightCardView(title: "いちばん聴く曜日", value: Fmt.weekdayNames[ins.topWeekday] + "曜日",
                                    sub: "全再生時間の \(ins.topWeekdayShare)%")
                    InsightCardView(title: "連続で聴いた最長記録", value: "\(Fmt.num(ins.streak)) 日連続",
                                    sub: "毎日欠かさず聴いた期間")
                    InsightCardView(title: "この期間に初めて聴いた曲", value: "\(Fmt.num(ins.discoveries)) 曲",
                                    sub: "全履歴の中で初再生だった曲")
                    InsightCardView(title: "リピート率", value: "\(ins.repeatRate)%",
                                    sub: "同じ曲の2回目以降の再生の割合")
                    InsightCardView(title: "深夜（0〜4時）の再生割合", value: "\(ins.lateNightShare)%",
                                    sub: "夜ふかし度")
                    InsightCardView(title: "トップアーティスト集中度", value: "\(ins.topArtistShare)%",
                                    sub: ins.topArtistName.map { "\($0) の再生時間割合" } ?? "")
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            } else {
                Text("この期間・条件に一致する再生履歴がありません。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 前期間との比較

    private func compareSection(comparison: PeriodComparison) -> some View {
        Section("前期間との比較") {
            let cmp = comparison
            if cmp.hasPrev {
                compareRow(title: "総再生時間", now: Fmt.dur(ms: cmp.curMs), prev: Fmt.dur(ms: cmp.prevMs),
                           pct: pctChange(cur: cmp.curMs, prev: cmp.prevMs))
                compareRow(title: "総再生回数", now: "\(Fmt.num(cmp.curPlays)) 回", prev: "\(Fmt.num(cmp.prevPlays)) 回",
                           pct: pctChange(cur: cmp.curPlays, prev: cmp.prevPlays))
                if let p = cmp.prevTopArtist, let c = cmp.curTopArtist {
                    HStack {
                        Text("トップアーティスト")
                        Spacer()
                        Text(c == p ? c : "\(p) → \(c)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("直前の同じ日数の期間にデータがないため、比較できません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func compareRow(title: String, now: String, prev: String, pct: Int?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("前 \(prev)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(now)
                .fontWeight(.bold)
            if let pct {
                Text(pct >= 0 ? "▲\(pct)%" : "▼\(abs(pct))%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(pct >= 0 ? Color.spotifyGreen : Color.red)
            }
        }
    }

    private func pctChange(cur: Int, prev: Int) -> Int? {
        guard prev > 0 else { return nil }
        return Int((Double(cur - prev) / Double(prev) * 100).rounded())
    }

    // MARK: - まとめカード

    private func shareSection(list: [PlayEntry], agg: (artists: [String: ArtistAgg], tracks: [String: TrackAgg]), insights: Insights?) -> some View {
        Section("まとめカード") {
            Button {
                makeShareImage(list: list, agg: agg, insights: insights)
            } label: {
                Label("この期間のまとめを画像でシェア", systemImage: "square.and.arrow.up")
            }
            Text("トップアーティスト・トップ曲・総再生時間を1枚の画像にして共有できます。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func makeShareImage(list: [PlayEntry], agg: (artists: [String: ArtistAgg], tracks: [String: TrackAgg]), insights: Insights?) {
        let ins = insights
        let card = ShareCardView(
            periodLabel: "\(Fmt.date(model.from)) 〜 \(Fmt.date(model.to))",
            totalMs: list.reduce(0) { $0 + $1.ms },
            totalPlays: list.count,
            topArtists: Aggregator.sortArtists(agg.artists, byTime: true),
            topTracks: Aggregator.sortTracks(agg.tracks, byTime: false),
            streak: ins?.streak ?? 0,
            bestDayLabel: ins.map { Fmt.date($0.bestDay) } ?? "—")
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let image = renderer.uiImage {
            shareItem = ShareableImage(image: image)
        }
    }

    // MARK: - データ

    private var dataSection: some View {
        Section("データ") {
            if let mn = store.dataMin, let mx = store.dataMax {
                LabeledContent("読み込み済み", value: "\(Fmt.num(store.entries.count)) 件")
                LabeledContent("履歴の期間", value: "\(Fmt.date(mn)) 〜 \(Fmt.date(mx))")
            }
            ImportButton(title: "追加で読み込む")
            if store.isBusy {
                HStack {
                    ProgressView()
                    Text(store.progressText.isEmpty ? "処理中…" : store.progressText)
                        .foregroundStyle(.secondary)
                }
            }
            if !store.statusText.isEmpty {
                Text(store.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("データをすべて削除", role: .destructive) {
                showDeleteConfirm = true
            }
        }
    }
}
