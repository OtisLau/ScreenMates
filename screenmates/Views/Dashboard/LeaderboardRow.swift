import SwiftUI

/// Single row in the leaderboard showing a member's stats
struct LeaderboardRow: View {
    let member: MemberData
    let isCurrentUser: Bool
    let dailyGoal: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // User info
            VStack(alignment: .leading, spacing: 4) {
                Text(isCurrentUser ? "You" : member.displayName)
                    .font(.headline)
                    .foregroundColor(isCurrentUser ? .purple : .primary)
                
                HStack(spacing: 8) {
                    // Last update time
                    Text(DateHelpers.relativeTime(from: member.lastUpdate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Streak indicator
                    if member.streak > 0 {
                        Text("🔥 \(member.streak)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            // Blocks/time used
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(member.blocks * AppConstants.currentBlockSize) min")
                    .font(.title3)
                    .bold()
                    .foregroundColor(statusColor)
                
                Text(member.status(goal: dailyGoal).displayText)
                    .font(.caption2)
                    .foregroundColor(statusColor)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
    }
    
    private var statusColor: Color {
        switch member.status(goal: dailyGoal) {
        case .safe: return .green
        case .warning: return .orange
        case .danger: return .red
        case .overLimit: return .red
        }
    }
}
