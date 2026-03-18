import SwiftUI

// Your screen time hero card — big time, soft progress ring, name below.
struct UserStatsCard: View {
    let minutesUsed: Int
    let displayName: String
    let goalMinutes: Int   // 0 = no goal set

    private var hoursUsed: Int    { minutesUsed / 60 }
    private var remainingMin: Int { minutesUsed % 60 }
    private var hasGoal: Bool     { goalMinutes > 0 }
    private var isOverGoal: Bool  { hasGoal && minutesUsed >= goalMinutes }

    // 0.0 – 1.0 clamped progress toward goal (or gentle pulse if no goal)
    private var progress: Double {
        guard hasGoal, goalMinutes > 0 else { return 0 }
        return min(Double(minutesUsed) / Double(goalMinutes), 1.0)
    }

    private var goalText: String {
        guard hasGoal else { return "no goal set" }
        let h = goalMinutes / 60
        let m = goalMinutes % 60
        if h > 0 && m > 0 { return "goal \(h)h \(m)m" }
        else if h > 0      { return "goal \(h)h" }
        else               { return "goal \(m)m" }
    }

    private var ringColor: Color {
        if !hasGoal { return AppTheme.accent.opacity(0.6) }
        if isOverGoal { return Color(UIColor.systemRed) }
        if progress > 0.75 { return Color(UIColor.systemOrange) }
        return AppTheme.accent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Name
            Text(displayName.isEmpty ? "You" : displayName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)

            // Ring + time
            ZStack {
                // Track ring
                Circle()
                    .stroke(Color.primary.opacity(0.07), lineWidth: 10)
                    .frame(width: 160, height: 160)

                // Progress ring
                Circle()
                    .trim(from: 0, to: hasGoal ? progress : 0)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: progress)

                // Time readout
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        if hoursUsed > 0 {
                            Text("\(hoursUsed)")
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                            Text("h")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 1)
                        }
                        Text("\(remainingMin)")
                            .font(.system(size: hoursUsed > 0 ? 30 : 38, weight: .bold, design: .rounded))
                        Text("m")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)

                    if hasGoal {
                        Text(goalText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isOverGoal ? Color(UIColor.systemRed) : Color.secondary)
                    }
                }
            }

            if !hasGoal {
                Text("no goal set")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 14)
            } else {
                Spacer().frame(height: 14)
            }
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
}
