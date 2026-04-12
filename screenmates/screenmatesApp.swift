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
                    scheduleBackgroundRefresh()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, cloudManager.isSetupDone else { return }
                    ensureMonitoringActive(context: "foreground")
                    Task { await cloudManager.registerFriendRequestSubscription() }
                }
        }
        .backgroundTask(.appRefresh(AppConstants.backgroundTaskIdentifier)) {
            print(" Background task triggered at \(Date())")
            await MainActor.run { ensureMonitoringActive(context: "background") }

            let result = await cloudManager.performBackgroundCheckDetailed()

            // Fetch friends leaderboard and evaluate notifications in background
            if let members = try? await cloudManager.fetchFriendsAsync() {
                let myUserID = await MainActor.run { cloudManager.myID }
                await NotificationManager.shared.evaluateAndSchedule(
                    members: members,
                    myUserID: myUserID
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
    nonisolated(unsafe) private static var lastRestartDate: Date = .distantPast
    nonisolated private static let restartStateQueue = DispatchQueue(label: "com.otishlau.screenmates.monitoringRestartState")

    // Check that DeviceActivity monitoring is running and the current batch isn't
    // exhausted. Called on every foreground activation and background task wake.
    private func ensureMonitoringActive(context: String) {
        Task.detached(priority: .utility) {
            Self.ensureMonitoringActiveInBackground(context: context)
        }
    }

    nonisolated private static func ensureMonitoringActiveInBackground(context: String) {
        if MonitoringManager.shared.performHardDayRolloverResetIfNeeded() {
            guard reserveRestartSlotIfNeeded(context: context) else { return }
            print(" New day detected (\(context)) — rolling over and restarting monitoring")
            restartMonitoring(reason: "day rollover", context: context)
            return
        }

        let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)

        let activities = DeviceActivityCenter().activities

        guard activities.contains(DeviceActivityName("dailyTracking")) else {
            guard reserveRestartSlotIfNeeded(context: context) else { return }
            print(" Monitoring dead (\(context)) — auto-restarting")
            restartMonitoring(reason: "inactive monitor", context: context)
            return
        }

        let lastIndex = sharedDefaults?.integer(forKey: AppConstants.Keys.lastThresholdIndex) ?? 0
        let lastAutoRollover = sharedDefaults?.integer(forKey: AppConstants.Keys.lastAutoBatchRolloverIndex) ?? 0
        let exhaustedBatch = lastIndex > 0 &&
            lastIndex % AppConstants.eventsPerMonitoringBatch == 0 &&
            lastIndex < AppConstants.maxTrackableBlocksPerDay

        if exhaustedBatch && lastAutoRollover != lastIndex {
            guard reserveRestartSlotIfNeeded(context: context) else { return }
            print(" Batch exhausted at block_\(lastIndex) (\(context)) — rolling over")
            sharedDefaults?.set(lastIndex, forKey: AppConstants.Keys.lastAutoBatchRolloverIndex)
            restartMonitoring(reason: "batch exhausted", context: context)
        }
    }

    nonisolated private static func restartMonitoring(reason: String, context: String) {
        let restarted = MonitoringManager.shared.restartMonitoring()
        if !restarted {
            print(" Monitoring restart failed (\(reason), \(context))")
        }
    }

    nonisolated private static func reserveRestartSlotIfNeeded(context: String) -> Bool {
        let reserved = restartStateQueue.sync {
            let now = Date()
            guard now.timeIntervalSince(Self.lastRestartDate) > 5 else { return false }
            Self.lastRestartDate = now
            return true
        }
        if !reserved {
            print(" Skipping ensureMonitoringActive (\(context)) — restart still settling")
        }
        return reserved
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
