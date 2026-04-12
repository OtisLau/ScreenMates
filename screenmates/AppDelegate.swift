import UIKit
import CloudKit
import UserNotifications

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
        // Check if this is a friend-request subscription push.
        if let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo),
           let subscriptionID = ckNotification.subscriptionID,
           subscriptionID.hasPrefix("friend-request-incoming-"),
           let queryNotification = ckNotification as? CKQueryNotification,
           let requesterID = queryNotification.recordFields?["requester_user_id"] as? String {
            Task {
                let name = await CloudKitManager.shared.fetchDisplayName(forUserID: requesterID) ?? "Someone"
                let content = UNMutableNotificationContent()
                content.title = "New friend request"
                content.body = "\(name) wants to be your ScreenMate"
                content.sound = .default
                let request = UNNotificationRequest(
                    identifier: "friend-request-\(requesterID)",
                    content: content,
                    trigger: nil
                )
                try? await UNUserNotificationCenter.current().add(request)
                await CloudKitManager.shared.refreshGroupNow(reason: "friend-request-push")
            }
            completionHandler(.newData)
            return
        }

        // Default: treat any other CloudKit push as a leaderboard refresh signal.
        Task { @MainActor in
            await CloudKitManager.shared.refreshGroupNow(reason: "silent-push")
        }
        completionHandler(.newData)
    }
}

