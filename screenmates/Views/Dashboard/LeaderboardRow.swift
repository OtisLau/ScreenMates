import SwiftUI

// One row in the group list — shows a person's name, how long they've been on their phone,
// and when we last got an update from them.
struct GroupMemberRow: View {
    let member: MemberData
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // Show "You" instead of your own name so it's clear which row is yours
                Text(isCurrentUser ? "You" : member.displayName)
                    .font(.headline)
                    .foregroundColor(isCurrentUser ? .purple : .primary)

                // Show how stale this data is
                Text("updated \(DateHelpers.relativeTime(from: member.lastUpdate))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Screen time in minutes, big and easy to read
            Text("\(member.minutesUsed) min")
                .font(.title3)
                .bold()
                .monospacedDigit()
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
    }
}
