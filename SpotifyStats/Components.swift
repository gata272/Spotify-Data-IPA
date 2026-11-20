import SwiftUI

/// Spotifyグリーン
extension Color {
    static let spotifyGreen = Color(red: 0.12, green: 0.84, blue: 0.38)
}

/// サマリー用の数値カード
struct StatCardView: View {
    var title: String
    var value: String
    var sub: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !sub.isEmpty {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// ハイライト用のカード
struct InsightCardView: View {
    var title: String
    var value: String
    var sub: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .fontWeight(.black)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if !sub.isEmpty {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// ランキングの1行（アーティスト／曲 共用）。行を独立したViewにして型チェックを軽くする
struct RankRowView: View {
    var rank: Int
    var name: String
    var sub: String
    var big: String
    var small: String
    var fraction: Double   // 1位を1としたバーの割合

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(rank)")
                    .font(.body)
                    .fontWeight(.black)
                    .foregroundStyle(rankColor)
                    .frame(width: 30, alignment: .trailing)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .fontWeight(.bold)
                        .lineLimit(1)
                    if !sub.isEmpty {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(big)
                        .fontWeight(.black)
                    Text(small)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.spotifyGreen)
                        .frame(width: geo.size.width * CGFloat(min(max(fraction, 0.015), 1)))
                }
            }
            .frame(height: 5)
            .padding(.leading, 40)
        }
        .padding(.vertical, 4)
    }

    private var rankColor: Color {
        switch rank {
        case 1: return Color(red: 0.72, green: 0.53, blue: 0.04)
        case 2: return Color(red: 0.49, green: 0.54, blue: 0.58)
        case 3: return Color(red: 0.63, green: 0.36, blue: 0.17)
        default: return .secondary
        }
    }
}

/// 日ごとのリストの1行
struct DayRowView: View {
    var row: DayAgg

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Fmt.date(row.date))
                .fontWeight(.bold)
            Text("（\(Fmt.weekdayNames[Calendar.current.component(.weekday, from: row.date) - 1])）")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(Fmt.dur(ms: row.ms))
                    .fontWeight(.black)
                Text("\(Fmt.num(row.plays)) 回")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
