import UIKit

/// Handles APNs registration + silent CloudKit pushes.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // CloudKit sends silent pushes for subscriptions. Treat any received push as a signal
        // to refresh leaderboard cache (best-effort).
        DispatchQueue.main.async {
            Task { @MainActor in
                await CloudKitManager.shared.refreshGroupNow(reason: "silent-push")
            }
        }
        completionHandler(.newData)
    }
}

