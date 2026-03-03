import SwiftUI

// The main screen — shows your screen time and your group's screen time side by side.
// Refreshes automatically every 60 seconds and whenever a silent push comes in.
struct DashboardView: View {
    @StateObject var cloudManager = CloudKitManager.shared

    @State private var showingSettings = false

    // Refresh the group data on a timer while the app is open.
    // Interval is controlled by AppConstants — shorter in test mode, longer in production.
    let timer = Timer.publish(every: AppConstants.dashboardRefreshInterval, on: .main, in: .common).autoconnect()

    // How many minutes the current user has used their phone today
    private var myMinutesUsed: Int {
        cloudManager.currentBlocksUsed * AppConstants.currentBlockSize
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    // Your own stats at the top
                    UserStatsCard(
                        minutesUsed: myMinutesUsed,
                        displayName: cloudManager.myDisplayName
                    )
                    .padding(.horizontal)

                    // Group code so people can share it easily
                    VStack(spacing: 4) {
                        Text("group code")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(cloudManager.myGroupID)
                            .font(.title2)
                            .bold()
                            .kerning(2)
                    }
                    .padding()
                    .background(Color.purple.opacity(0.08))
                    .cornerRadius(12)

                    // Everyone in the group
                    VStack(alignment: .leading, spacing: 12) {
                        Text("GROUP")
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
                            memberList
                        }
                    }

                    // Show when we last got fresh data
                    if let lastSync = cloudManager.lastSyncTime {
                        Text("last updated \(DateHelpers.relativeTime(from: lastSync))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical)
            }
            .refreshable {
                await cloudManager.refreshGroupNow(reason: "pull-to-refresh")
            }
            .navigationTitle("ScreenMates")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                    }
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

    // List of all group members sorted by most screen time
    private var memberList: some View {
        ForEach(cloudManager.groupMembers) { member in
            GroupMemberRow(
                member: member,
                isCurrentUser: member.userID == cloudManager.myID
            )
            .padding(.horizontal)
        }
    }

    // Shown when no group data has loaded yet
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("No one here yet")
                .font(.headline)

            Text("Share your group code with friends to get started.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                cloudManager.updateMyProfile {
                    cloudManager.fetchGroupData(useCache: false)
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
