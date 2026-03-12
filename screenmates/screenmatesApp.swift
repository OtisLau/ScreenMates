import SwiftUI
import BackgroundTasks
import DeviceActivity

@main
struct ScreenMatesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var cloudManager = CloudKitManager.shared
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
                .onChange(of: scenePhase) { phase in
                    guard phase == .active, cloudManager.isSetupDone else { return }
                    // Every time the app comes to the foreground, check whether the OS
                    // killed the DeviceActivity monitoring session while we were away.
                    // If it did, silently restart it so tracking resumes immediately.
                    let activities = DeviceActivityCenter().activities
                    if !activities.contains(DeviceActivityName("dailyTracking")) {
                        print(" Monitoring was dead on foreground — auto-restarting")
                        MonitoringManager.shared.restartMonitoring()
                        return
                    }

                    // If the currently registered batch is exhausted (e.g. block 96/192
                    // in 96-event mode), auto-register the next batch so tracking
                    // doesn't silently stall.
                    let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)
                    let lastIndex = sharedDefaults?.integer(forKey: "LastThresholdIndex") ?? 0
                    let lastAutoRollover = sharedDefaults?.integer(forKey: AppConstants.Keys.lastAutoBatchRolloverIndex) ?? 0

                    let exhaustedBatch = lastIndex > 0 &&
                        lastIndex % AppConstants.eventsPerMonitoringBatch == 0 &&
                        lastIndex < AppConstants.maxTrackableBlocksPerDay

                    if exhaustedBatch && lastAutoRollover != lastIndex {
                        print(" Batch exhausted at block_\(lastIndex) — auto-registering next batch")
                        sharedDefaults?.set(lastIndex, forKey: AppConstants.Keys.lastAutoBatchRolloverIndex)
                        MonitoringManager.shared.restartMonitoring()
                    }
                }
        }
        .backgroundTask(.appRefresh(AppConstants.backgroundTaskIdentifier)) {
            print(" Background task triggered at \(Date())")

            // Mirror the foreground exhausted-batch check so tracking doesn't stall
            // when the user never brings the app to foreground after block_96.
            let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)
            let lastIndex = sharedDefaults?.integer(forKey: "LastThresholdIndex") ?? 0
            let lastAutoRollover = sharedDefaults?.integer(forKey: AppConstants.Keys.lastAutoBatchRolloverIndex) ?? 0
            let activities = DeviceActivityCenter().activities

            if !activities.contains(DeviceActivityName("dailyTracking")) {
                print(" Monitoring dead in background — auto-restarting")
                MonitoringManager.shared.restartMonitoring()
            } else {
                let exhaustedBatch = lastIndex > 0 &&
                    lastIndex % AppConstants.eventsPerMonitoringBatch == 0 &&
                    lastIndex < AppConstants.maxTrackableBlocksPerDay

                if exhaustedBatch && lastAutoRollover != lastIndex {
                    print(" Batch exhausted at block_\(lastIndex) in background — rolling over")
                    sharedDefaults?.set(lastIndex, forKey: AppConstants.Keys.lastAutoBatchRolloverIndex)
                    MonitoringManager.shared.restartMonitoring()
                }
            }

            let result = await cloudManager.performBackgroundCheckDetailed()
            
            // Log this background sync attempt
            await MainActor.run {
                logBackgroundSync(
                    success: result.success,
                    errorMessage: result.errorMessage,
                    ckErrorCode: result.ckErrorCode,
                    retryAfterSeconds: result.retryAfterSeconds
                )
            }
            
            print(result.success ? " Background check succeeded" : " Background check failed")
            
            // Re-schedule for next time
            await MainActor.run {
                scheduleBackgroundRefresh()
            }
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
    
    private func logBackgroundSync(success: Bool, errorMessage: String?, ckErrorCode: Int?, retryAfterSeconds: Double?) {
        let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)
        
        // Save last sync time
        sharedDefaults?.set(Date(), forKey: AppConstants.Keys.lastBackgroundSync)
        
        // Add to history (keep last 20)
        var history = sharedDefaults?.array(forKey: AppConstants.Keys.backgroundSyncHistory) as? [[String: Any]] ?? []
        
        var entry: [String: Any] = [
            "timestamp": Date(),
            "success": success,
            "blocks": sharedDefaults?.integer(forKey: AppConstants.Keys.dailyBlocksUsed) ?? 0
        ]

        // Attach useful diagnostics for failures (and optional info for successes)
        if let errorMessage, !errorMessage.isEmpty {
            entry["error"] = errorMessage
        }
        if let ckErrorCode {
            entry["ckErrorCode"] = ckErrorCode
        }
        if let retryAfterSeconds {
            entry["retryAfterSeconds"] = retryAfterSeconds
        }
        
        history.insert(entry, at: 0)
        
        // Keep only last 20 entries
        if history.count > 20 {
            history = Array(history.prefix(20))
        }
        
        sharedDefaults?.set(history, forKey: AppConstants.Keys.backgroundSyncHistory)
    }
}
