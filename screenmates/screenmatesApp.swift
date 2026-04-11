import SwiftUI
import BackgroundTasks
import DeviceActivity

@main
struct ScreenMatesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var cloudManager = CloudKitManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Schedule background refresh after app launches
                    scheduleBackgroundRefresh()

                    // Ensure CloudKit subscription so other devices get silent updates.
                    cloudManager.ensureGroupSubscription()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, cloudManager.isSetupDone else { return }
                    ensureMonitoringActive(context: "foreground")
                }
        }
        .backgroundTask(.appRefresh(AppConstants.backgroundTaskIdentifier)) {
            print(" Background task triggered at \(Date())")
            await MainActor.run { ensureMonitoringActive(context: "background") }

            let result = await cloudManager.performBackgroundCheckDetailed()

            // Fetch group data and evaluate notifications in background
            if let members = try? await cloudManager.fetchGroupMembersAsync() {
                NotificationManager.shared.evaluateAndSchedule(
                    groupMembers: members,
                    myUserID: cloudManager.myID,
                    goalMinutes: cloudManager.groupGoalMinutes
                )
            }

            print(result.success ? " Background check succeeded" : " Background check failed")
            
            // Re-schedule for next time
            await MainActor.run {
                scheduleBackgroundRefresh()
            }
        }
    }
    
    // Debounce concurrent calls (e.g. background task + foreground activation).
    private static var lastRestartDate: Date = .distantPast

    // Check that DeviceActivity monitoring is running and the current batch isn't
    // exhausted. Called on every foreground activation and background task wake.
    private func ensureMonitoringActive(context: String) {
        // Skip if we already restarted within the last 5 seconds to prevent
        // concurrent foreground + background calls from double-restarting.
        guard Date().timeIntervalSince(Self.lastRestartDate) > 5 else {
            print(" Skipping ensureMonitoringActive (\(context)) — restart still settling")
            return
        }

        if MonitoringManager.shared.performHardDayRolloverResetIfNeeded() {
            print(" New day detected (\(context)) — rolling over and restarting monitoring")
            Self.lastRestartDate = Date()
            MonitoringManager.shared.restartMonitoring()
            return
        }

        let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)

        let activities = DeviceActivityCenter().activities

        guard activities.contains(DeviceActivityName("dailyTracking")) else {
            print(" Monitoring dead (\(context)) — auto-restarting")
            Self.lastRestartDate = Date()
            MonitoringManager.shared.restartMonitoring()
            return
        }

        let lastIndex = sharedDefaults?.integer(forKey: AppConstants.Keys.lastThresholdIndex) ?? 0
        let lastAutoRollover = sharedDefaults?.integer(forKey: AppConstants.Keys.lastAutoBatchRolloverIndex) ?? 0
        let exhaustedBatch = lastIndex > 0 &&
            lastIndex % AppConstants.eventsPerMonitoringBatch == 0 &&
            lastIndex < AppConstants.maxTrackableBlocksPerDay

        if exhaustedBatch && lastAutoRollover != lastIndex {
            print(" Batch exhausted at block_\(lastIndex) (\(context)) — rolling over")
            sharedDefaults?.set(lastIndex, forKey: AppConstants.Keys.lastAutoBatchRolloverIndex)
            Self.lastRestartDate = Date()
            MonitoringManager.shared.restartMonitoring()
        }
    }

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: AppConstants.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: AppConstants.backgroundTaskInterval)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print(" Background refresh scheduled for ~15 min from now")
        } catch {
            print(" Failed to schedule background refresh: \(error)")
        }
    }
    
}
