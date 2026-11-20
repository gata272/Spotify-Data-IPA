import SwiftUI

struct ContentView: View {
    @StateObject private var store = StatsStore()
    @StateObject private var model = AppModel()

    var body: some View {
        Group {
            if store.entries.isEmpty {
                ImportView()
            } else {
                TabView(selection: $model.tab) {
                    HomeView()
                        .tabItem { Label("ホーム", systemImage: "house") }
                        .tag(0)
                    RankingView()
                        .tabItem { Label("ランキング", systemImage: "list.number") }
                        .tag(1)
                    ChartsView()
                        .tabItem { Label("グラフ", systemImage: "chart.bar") }
                        .tag(2)
                    ArtistView()
                        .tabItem { Label("アーティスト", systemImage: "music.mic") }
                        .tag(3)
                }
            }
        }
        .environmentObject(store)
        .environmentObject(model)
        .onAppear { store.loadSaved() }
        .onChange(of: store.entries.count) { _, _ in
            if !model.periodInitialized, let mn = store.dataMin, let mx = store.dataMax {
                model.from = mn
                model.to = mx
                model.preset = "all"
                model.periodInitialized = true
            }
        }
    }
}

/// データ未読み込み時の最初の画面
struct ImportView: View {
    @EnvironmentObject private var store: StatsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Spotify統計")
                        .font(.largeTitle)
                        .fontWeight(.black)
                    Text("Spotifyからダウンロードした「拡張ストリーミング履歴」のzipファイルを読み込むと、期間を指定してアーティスト・曲ごとの再生回数と再生時間のランキングが見られます。月ごと・日ごと・時間帯ごと・曜日ごとの統計や、アーティスト別のハイライトも見られます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.green)
                    Text("zipファイルを読み込む")
                        .fontWeight(.bold)
                    Text("Streaming_History_Audio_*.json を含むzip／JSONファイル単体でも可")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    ImportButton(title: "ファイルを選ぶ")
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    if store.isBusy {
                        ProgressView()
                    }
                    if !store.statusText.isEmpty {
                        Text(store.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 6) {
                    Text("データの扱い")
                        .fontWeight(.bold)
                    Text("読み込んだデータはこのアプリの中だけに保存され、外部に送信されることはありません。新しいzipを入手したら「追加で読み込む」から取り込めます（重複は自動で除かれます）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("zipファイルの入手方法")
                        .fontWeight(.bold)
                    Text("1. Spotifyのサイト／アプリで「アカウント」→「プライバシー設定」を開く\n2. 「データをダウンロードする」の「拡張ストリーミング履歴」をリクエストする\n3. 数日後に届くメールからダウンロードしたzipを、そのままここに読み込む")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}
