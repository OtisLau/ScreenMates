import SwiftUI

// Shows the current user's screen time for today at the top of the dashboard.
// Kept intentionally simple — just a number, no goals or limits.
struct UserStatsCard: View {
    let minutesUsed: Int   // total screen time in minutes today
    let displayName: String

    var body: some View {
        VStack(spacing: 8) {
            Text("your screen time today")
                .font(.caption)
                .foregroundColor(.secondary)

            // Big bold minute count
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(minutesUsed)")
                    .font(.system(size: 56, weight: .bold))
                Text("min")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }

            Text(displayName)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.purple.opacity(0.08))
        .cornerRadius(16)
    }
}
