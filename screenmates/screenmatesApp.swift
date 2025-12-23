import SwiftUI
import BackgroundTasks

@main
struct ScreenMatesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var cloudManager = CloudKitManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Schedule background refresh after app launches
                    scheduleBackgroundRefresh()

                    // Ensure CloudKit subscription so other devices get silent updates.
                    cloudManager.ensureGroupSubscription()
                }
        }
        .backgroundTask(.appRefresh(AppConstants.backgroundTaskIdentifier)) {
            print("🌙 Background task triggered at \(Date())")
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
            
            print(result.success ? "✅ Background check succeeded" : "❌ Background check failed")
            
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
            print("✅ Background refresh scheduled for ~15 min from now")
        } catch {
            print("❌ Failed to schedule background refresh: \(error)")
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
