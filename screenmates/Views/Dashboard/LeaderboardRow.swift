import SwiftUI

// One leaderboard row — flat, clean, no color theatrics.
struct GroupMemberRow: View {
    let member: MemberData
    let isCurrentUser: Bool
    let rank: Int

    private var hoursUsed: Int { member.minutesUsed / 60 }
    private var minsUsed: Int  { member.minutesUsed % 60 }

    var body: some View {
        HStack(spacing: 14) {
            // Rank — small monospaced number, no colored badge
            Text("\(rank)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .center)

            // Name
            Text(isCurrentUser ? "You" : member.displayName)
                .font(.system(size: 15, weight: isCurrentUser ? .semibold : .regular))
                .foregroundStyle(isCurrentUser ? Color.primary : Color.primary.opacity(0.8))
                .lineLimit(1)

            Spacer()

            // Time
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if hoursUsed > 0 {
                    Text("\(hoursUsed)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("h")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 1)
                }
                Text("\(minsUsed)")
                    .font(.system(size: hoursUsed > 0 ? 13 : 15, weight: .semibold, design: .rounded))
                Text("m")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
    }
}
