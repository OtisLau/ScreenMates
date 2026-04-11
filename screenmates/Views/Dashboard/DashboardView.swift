import SwiftUI
import Combine

// Main dashboard — your time at top, group leaderboard below.
struct DashboardView: View {
    @ObservedObject var cloudManager = CloudKitManager.shared
    @State private var showingSettings = false

    let timer = Timer.publish(every: AppConstants.dashboardRefreshInterval, on: .main, in: .common).autoconnect()

    private var myMinutesUsed: Int {
        cloudManager.currentBlocksUsed * AppConstants.currentBlockSize
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Dot grid sits behind everything
                DotGridBackground()

                ScrollView {
                    VStack(spacing: 0) {

                        // Your stats — hero section, no card border
                        UserStatsCard(
                            minutesUsed: myMinutesUsed,
                            displayName: cloudManager.myDisplayName,
                            goalMinutes: cloudManager.groupGoalMinutes
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                        // Divider before group
                        Rectangle()
                            .fill(Color.primary.opacity(0.07))
                            .frame(height: 1)
                            .padding(.horizontal, 24)
                            .padding(.top, 4)

                        // Group section
                        VStack(spacing: 0) {
                            // Leaderboard header
                            Text("LEADERBOARD")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .kerning(1.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.top, 24)
                                .padding(.bottom, 12)

                            // Member rows inside one contained glass card
                            if cloudManager.isLoading && cloudManager.groupMembers.isEmpty {
                                ProgressView()
                                    .padding(40)
                            } else if cloudManager.groupMembers.isEmpty {
                                emptyState
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(cloudManager.groupMembers.enumerated()), id: \.element.id) { index, member in
                                        GroupMemberRow(
                                            member: member,
                                            isCurrentUser: member.userID == cloudManager.myID,
                                            rank: index + 1
                                        )

                                        if index < cloudManager.groupMembers.count - 1 {
                                            Rectangle()
                                                .fill(Color.primary.opacity(0.06))
                                                .frame(height: 1)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                                .glassCard(cornerRadius: AppTheme.cornerRadiusLarge)
                                .padding(.horizontal, 24)
                            }
                        }

                        // Sync footer
                        if let lastSync = cloudManager.lastSyncTime {
                            Text("synced \(DateHelpers.relativeTime(from: lastSync))")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 20)
                        }

                        Spacer(minLength: 60)
                    }
                }
                .refreshable {
                    await cloudManager.refreshGroupNow(reason: "pull-to-refresh")
                }
            }
            .navigationTitle("ScreenMates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .onAppear {
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No one here yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Share your group code to invite friends.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
