import SwiftUI

/// Card showing the current user's stats at the top of dashboard
struct UserStatsCard: View {
    let blocksUsed: Int
    let dailyGoal: Int
    let streak: Int
    
    private var timeUsed: Int {
        blocksUsed * AppConstants.currentBlockSize
    }
    
    private var timeGoal: Int {
        dailyGoal * AppConstants.currentBlockSize
    }
    
    private var isUnderLimit: Bool {
        blocksUsed < dailyGoal
    }
    
    private var percentage: Double {
        guard dailyGoal > 0 else { return 0 }
        return Double(blocksUsed) / Double(dailyGoal)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Title
            Text("Your Stats Today")
                .font(.headline)
                .foregroundColor(.secondary)
            
            // Main time display
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(timeUsed)")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(statusColor)
                
                Text("/ \(timeGoal) min")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            // Status indicator
            Text(statusMessage)
                .font(.subheadline)
                .foregroundColor(statusColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.1))
                .cornerRadius(8)
            
            Divider()
            
            // Additional stats
            HStack(spacing: 30) {
                // Streak
                VStack(spacing: 4) {
                    Text("\(streak)")
                        .font(.title2)
                        .bold()
                    Text("Day Streak")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                    .frame(height: 40)
                
                // Time until midnight
                VStack(spacing: 4) {
                    Text(DateHelpers.timeUntilMidnight())
                        .font(.title2)
                        .bold()
                    Text("Until Reset")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                    .frame(height: 40)
                
                // Progress percentage
                VStack(spacing: 4) {
                    Text("\(Int(percentage * 100))%")
                        .font(.title2)
                        .bold()
                    Text("Used")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
        .background(Color.purple.opacity(0.1))
        .cornerRadius(16)
    }
    
    private var statusColor: Color {
        if !isUnderLimit {
            return .red
        } else if percentage >= 0.9 {
            return .red
        } else if percentage >= 0.75 {
            return .orange
        } else {
            return .green
        }
    }
    
    private var statusMessage: String {
        if !isUnderLimit {
            return "Over Limit"
        } else if percentage >= 0.9 {
            return "Almost at Limit!"
        } else if percentage >= 0.75 {
            return "Approaching Limit"
        } else {
            return "Under Limit ✓"
        }
    }
}
