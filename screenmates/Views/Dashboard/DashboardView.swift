import SwiftUI
import Combine

/// Main dashboard showing user stats and leaderboard
struct DashboardView: View {
    @StateObject var cloudManager = CloudKitManager.shared
    @StateObject var streakManager = StreakManager.shared
    
    @State private var showingSettings = false
    
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    private var currentBlocks: Int {
        cloudManager.currentBlocksUsed
    }
    
    private var dailyGoal: Int {
        cloudManager.currentGroup?.dailyGoalBlocks ?? AppConstants.defaultDailyGoalBlocks
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 20) {
                        // Group ID display
                        VStack(spacing: 4) {
                            Text("GROUP ID")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(cloudManager.myGroupID)
                                .font(.title)
                                .bold()
                                .kerning(2)
                        }
                        .padding()
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(12)
                        
                        // User stats card
                        UserStatsCard(
                            blocksUsed: currentBlocks,
                            dailyGoal: dailyGoal,
                            streak: streakManager.currentStreak
                        )
                        .padding(.horizontal)
                        
                        // Leaderboard section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("LEADERBOARD")
                                .font(.caption)
                                .bold()
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            if cloudManager.isLoading && cloudManager.groupMembers.isEmpty {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else if cloudManager.groupMembers.isEmpty {
                                emptyState
                            } else {
                                leaderboardList
                            }
                        }
                        
                        // Last sync info
                        if let lastSync = cloudManager.lastSyncTime {
                            Text("Last updated: \(DateHelpers.relativeTime(from: lastSync))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        }
                        
                        // Test mode indicator
                        if AppConstants.isTestMode {
                            Text("TEST MODE: 1 min = 1 block (max \(AppConstants.maxDailyCheckpoints) blocks/day)")
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(.top, 4)

                            if currentBlocks >= AppConstants.maxDailyCheckpoints {
                                Text("Reached test-mode tracking cap (\(AppConstants.maxDailyCheckpoints)). This happens because we only register \(AppConstants.maxDailyCheckpoints) daily checkpoints with Screen Time.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical)
                }
                .refreshable {
                    await refreshData()
                }
            }
            .navigationTitle("ScreenMates")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .onAppear {
                print("📱 Dashboard appeared")
                Task { @MainActor in
                    await cloudManager.refreshGroupNow(reason: "appear")
                }
            }
            .onReceive(timer) { _ in
                Task { @MainActor in
                    await cloudManager.refreshGroupNow(reason: "timer")
                }
            }
        }
    }
    
    private var leaderboardList: some View {
        ForEach(cloudManager.groupMembers) { member in
            LeaderboardRow(
                member: member,
                isCurrentUser: member.userID == cloudManager.myID,
                dailyGoal: dailyGoal
            )
            .padding(.horizontal)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("No Members Yet")
                .font(.headline)
            
            Text("Share your group code with friends to get started!")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Troubleshooting hint
            VStack(spacing: 8) {
                Text("Not seeing yourself?")
                    .font(.caption2)
                    .foregroundColor(.orange)
                
                Button {
                    // Force refresh
                    cloudManager.updateMyProfile {
                        cloudManager.fetchGroupData(useCache: false)
                    }
                } label: {
                    Label("Refresh Now", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private func loadData() {
        cloudManager.fetchGroupData()
        cloudManager.fetchGroupDetails()
        cloudManager.updateMyProfile()
    }
    
    private func refreshData() async {
        await cloudManager.refreshGroupNow(reason: "pull-to-refresh")
    }
}
