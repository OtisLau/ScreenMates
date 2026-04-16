import UIKit
import CloudKit
import UserNotifications

/// Handles APNs registration + silent CloudKit pushes.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    // Show banners + play sound even while the app is in the foreground.
    // Without this, immediate notifications (trigger: nil) are silently dropped
    // and scheduled notifications that fire while the app is open are invisible.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
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
                do {
                    try await UNUserNotificationCenter.current().add(request)
                } catch {
                    print("Friend request notification add failed: \(error.localizedDescription)")
                }
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
