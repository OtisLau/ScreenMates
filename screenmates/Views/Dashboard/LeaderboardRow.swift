import SwiftUI

// One leaderboard row — flat, airy, no heavy card per row.
struct GroupMemberRow: View {
    let member: MemberData
    let isCurrentUser: Bool
    let rank: Int

    private var hoursUsed: Int { member.minutesUsed / 60 }
    private var minsUsed: Int  { member.minutesUsed % 60 }

    // Soft dot color by rank position
    private var rankDotColor: Color {
        switch rank {
        case 1: return Color(UIColor.systemYellow)
        case 2: return Color(UIColor.systemGray3)
        case 3: return Color(UIColor.systemBrown).opacity(0.7)
        default: return Color.primary.opacity(0.12)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Rank dot
            ZStack {
                Circle()
                    .fill(rankDotColor)
                    .frame(width: 28, height: 28)
                Text("\(rank)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(rank <= 3 ? Color.black.opacity(0.6) : Color.secondary)
            }

            // Name
            Text(isCurrentUser ? "You" : member.displayName)
                .font(.system(size: 15, weight: isCurrentUser ? .semibold : .regular))
                .foregroundStyle(isCurrentUser ? AppTheme.accent : Color.primary)
                .lineLimit(1)

            Spacer()

            // Time
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if hoursUsed > 0 {
                    Text("\(hoursUsed)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("h")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 1)
                }
                Text("\(minsUsed)")
                    .font(.system(size: hoursUsed > 0 ? 14 : 16, weight: .bold, design: .rounded))
                Text("m")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
    }
}
