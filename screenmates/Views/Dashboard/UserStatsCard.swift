import SwiftUI

// Your screen time hero card — ring drains as you burn through your daily limit.
struct UserStatsCard: View {
    let minutesUsed: Int
    let displayName: String
    let goalMinutes: Int   // 0 = no limit set

    private var hoursUsed: Int    { minutesUsed / 60 }
    private var remainingMin: Int { minutesUsed % 60 }
    private var hasLimit: Bool    { goalMinutes > 0 }
    private var isOverLimit: Bool { hasLimit && minutesUsed >= goalMinutes }

    // Fraction of limit *remaining* — ring is full at 0 usage, empty at limit.
    private var remaining: Double {
        guard hasLimit, goalMinutes > 0 else { return 0 }
        let used = min(Double(minutesUsed) / Double(goalMinutes), 1.0)
        return 1.0 - used
    }

    private var limitText: String {
        guard hasLimit else { return "no limit set" }
        let h = goalMinutes / 60
        let m = goalMinutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m limit" }
        else if h > 0      { return "\(h)h limit" }
        else               { return "\(m)m limit" }
    }

    // Ring color: neutral when no limit, fades to muted red only when over
    private var ringColor: Color {
        if !hasLimit { return Color.primary.opacity(0.2) }
        if isOverLimit { return Color(UIColor.systemRed).opacity(0.7) }
        // Smoothly desaturate as the ring drains
        if remaining < 0.25 { return Color(UIColor.systemOrange).opacity(0.8) }
        return AppTheme.accent.opacity(0.85)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Name
            Text(displayName.isEmpty ? "You" : displayName)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)

            // Ring + time
            ZStack {
                // Track
                Circle()
                    .stroke(Color.primary.opacity(0.06), lineWidth: 9)
                    .frame(width: 164, height: 164)

                // Remaining ring — starts at top, drains clockwise
                Circle()
                    .trim(from: 0, to: hasLimit ? remaining : 0)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .frame(width: 164, height: 164)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: remaining)

                // Time readout
                VStack(spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        if hoursUsed > 0 {
                            Text("\(hoursUsed)")
                                .font(.system(size: 36, weight: .semibold, design: .rounded))
                            Text("h")
                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 2)
                        }
                        Text("\(remainingMin)")
                            .font(.system(size: hoursUsed > 0 ? 28 : 36, weight: .semibold, design: .rounded))
                        Text("m")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)

                    if hasLimit {
                        Text(isOverLimit ? "over limit" : limitText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isOverLimit ? Color(UIColor.systemRed).opacity(0.8) : Color.secondary)
                            .padding(.top, 1)
                    }
                }
            }

            Text(hasLimit ? "" : "no limit set")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 16)
                .frame(height: 20)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
}
