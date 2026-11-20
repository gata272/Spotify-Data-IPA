import SwiftUI
import UIKit

/// シェア用のまとめカード（Wrapped風）。ImageRendererで画像化して共有する
struct ShareCardView: View {
    var periodLabel: String
    var totalMs: Int
    var totalPlays: Int
    var topArtists: [ArtistAgg]
    var topTracks: [TrackAgg]
    var streak: Int
    var bestDayLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("私のSpotify統計")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.white)
                Text(periodLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.spotifyGreen)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("総再生時間")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.gray)
                Text(Fmt.dur(ms: totalMs))
                    .font(.system(size: 40, weight: .black))
                    .foregroundStyle(.white)
                Text("\(Fmt.num(totalPlays)) 回再生")
                    .font(.system(size: 13))
                    .foregroundStyle(.gray)
            }

            cardSection(title: "よく聴いたアーティスト") {
                ForEach(Array(topArtists.prefix(5).enumerated()), id: \.offset) { i, a in
                    cardRow(rank: i + 1, name: a.name, value: Fmt.dur(ms: a.ms))
                }
            }

            cardSection(title: "よく聴いた曲") {
                ForEach(Array(topTracks.prefix(5).enumerated()), id: \.offset) { i, t in
                    cardRow(rank: i + 1, name: t.name, value: "\(Fmt.num(t.plays)) 回")
                }
            }

            HStack(spacing: 16) {
                Label("最長 \(Fmt.num(streak)) 日連続", systemImage: "flame.fill")
                Label("いちばん聴いた日 \(bestDayLabel)", systemImage: "calendar")
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.gray)
        }
        .padding(22)
        .frame(width: 360, height: 500, alignment: .topLeading)
        .background(Color(red: 0.04, green: 0.05, blue: 0.04))
    }

    private func cardSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.spotifyGreen)
            content()
        }
    }

    private func cardRow(rank: Int, name: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(Color.spotifyGreen)
                .frame(width: 18, alignment: .trailing)
            Text(name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.gray)
        }
    }
}

/// .sheet(item:) で渡すための共有画像
struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// UIActivityViewController のラッパー
struct ActivityView: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
