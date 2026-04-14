import SwiftUI

struct DashboardView: View {
    @ObservedObject var cloudManager = CloudKitManager.shared
    @State private var showingSettings = false
    @State private var showingFriends  = false

    private var myMinutesUsed: Int {
        cloudManager.currentBlocksUsed * AppConstants.currentBlockSize
    }

    private var friendsButtonAccessibilityLabel: String {
        let count = cloudManager.pendingRequests.count
        guard count > 0 else { return "Friends" }
        let requestText = count == 1 ? "pending friend request" : "pending friend requests"
        return "Friends, \(count) \(requestText)"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                DotGridBackground()

                ScrollView {
                    VStack(spacing: 0) {

                        // Hero — your own stats
                        UserStatsCard(
                            minutesUsed: myMinutesUsed,
                            displayName: cloudManager.myDisplayName,
                            goalMinutes: cloudManager.myPersonalGoalMinutes
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                        Rectangle()
                            .fill(Color.primary.opacity(0.07))
                            .frame(height: 1)
                            .padding(.horizontal, 24)
                            .padding(.top, 4)

                        // Friends leaderboard
                        VStack(spacing: 0) {
                            Text("LEADERBOARD")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .kerning(1.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.top, 24)
                                .padding(.bottom, 12)

                            if cloudManager.isLoading && cloudManager.friends.isEmpty {
                                ProgressView()
                                    .padding(40)
                            } else if cloudManager.friends.isEmpty {
                                emptyState
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(cloudManager.friends.enumerated()), id: \.element.id) { index, member in
                                        GroupMemberRow(
                                            member: member,
                                            isCurrentUser: member.userID == cloudManager.myID,
                                            rank: index + 1
                                        )

                                        if index < cloudManager.friends.count - 1 {
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
                    await cloudManager.refreshFriendsNow(reason: "pull-to-refresh")
                }
            }
            .navigationTitle("ScreenMates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingFriends = true
                    } label: {
                        Image(systemName: "person.2.fill")
                            .overlay(alignment: .topTrailing) {
                                if cloudManager.pendingRequests.count > 0 {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 9, height: 9)
                                        .overlay {
                                            Circle()
                                                .stroke(Color.white, lineWidth: 1.5)
                                        }
                                        .offset(x: 2, y: -2)
                                        .accessibilityHidden(true)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(friendsButtonAccessibilityLabel)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showingFriends) {
                FriendsView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .task {
                await cloudManager.refreshFriendsNow(reason: "appear")
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(AppConstants.dashboardRefreshInterval))
                    guard !Task.isCancelled else { break }
                    await cloudManager.refreshFriendsNow(reason: "timer")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No friends yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Tap the friends button to add someone.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
