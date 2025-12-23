import Foundation
import Combine
import UserNotifications

/// Manages local notifications for the app
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    
    private let center = UNUserNotificationCenter.current()
    
    private init() {
        checkAuthorization()
    }
    
    // MARK: - Permission Management
    
    /// Request notification permissions
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run {
                self.isAuthorized = granted
            }
            return granted
        } catch {
            print("❌ Notification permission error: \(error)")
            return false
        }
    }
    
    /// Check current authorization status
    func checkAuthorization() {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
    
    // MARK: - Notification Scheduling
    
    /// Schedule or update notifications based on current blocks usage
    func updateNotifications(blocksUsed: Int, dailyGoal: Int) {
        guard isAuthorized else { return }
        
        // Clear existing notifications
        center.removeAllPendingNotificationRequests()
        
        let percentage = Double(blocksUsed) / Double(dailyGoal)
        
        // 75% warning
        if percentage < 0.75 {
            let blocksAt75 = Int(Double(dailyGoal) * 0.75)
            scheduleThresholdNotification(
                identifier: "warning-75",
                title: "Approaching Your Limit",
                body: "You've used \(blocksAt75) of \(dailyGoal) blocks today (75%)",
                threshold: blocksAt75
            )
        }
        
        // 90% warning
        if percentage < 0.90 {
            let blocksAt90 = Int(Double(dailyGoal) * 0.90)
            scheduleThresholdNotification(
                identifier: "warning-90",
                title: "Almost at Your Limit!",
                body: "You've used \(blocksAt90) of \(dailyGoal) blocks today (90%)",
                threshold: blocksAt90
            )
        }
        
        // Over limit warning
        if blocksUsed < dailyGoal {
            scheduleThresholdNotification(
                identifier: "over-limit",
                title: "Over Your Daily Limit",
                body: "You went over today's limit of \(dailyGoal) blocks",
                threshold: dailyGoal
            )
        }
    }
    
    /// Schedule a notification for a specific threshold
    private func scheduleThresholdNotification(identifier: String, title: String, body: String, threshold: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        // Trigger immediately (in practice, this would be triggered by the extension)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                print("❌ Failed to schedule notification: \(error)")
            } else {
                print("✅ Scheduled notification: \(identifier)")
            }
        }
    }
    
    /// Schedule daily reset notification
    func scheduleDailyResetNotification(wasUnderLimit: Bool, streak: Int) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "New Day!"
        
        if wasUnderLimit && streak > 0 {
            content.body = "Your \(streak) day streak continues! 🔥"
        } else if wasUnderLimit {
            content.body = "You stayed under your limit yesterday! Keep it up! ✨"
        } else {
            content.body = "Fresh start today! You've got this! 💪"
        }
        
        content.sound = .default
        
        // Schedule for next midnight
        var dateComponents = DateComponents()
        dateComponents.hour = 0
        dateComponents.minute = 1
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "daily-reset", content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                print("❌ Failed to schedule daily notification: \(error)")
            } else {
                print("✅ Scheduled daily reset notification")
            }
        }
    }
    
    /// Send immediate notification (for testing)
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Test Notification"
        content.body = "This is a test from ScreenMates"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "test", content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                print("❌ Test notification failed: \(error)")
            }
        }
    }
    
    // MARK: - Settings
    
    var notificationsEnabled: Bool {
        get {
            // Use shared UserDefaults so extension can read it
            let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)
            // Check if it's been set before
            if sharedDefaults?.object(forKey: AppConstants.Keys.notificationsEnabled) == nil {
                // Default to true if never set
                return true
            }
            return sharedDefaults?.bool(forKey: AppConstants.Keys.notificationsEnabled) ?? true
        }
        set {
            // Use shared UserDefaults so extension can read it
            let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)
            sharedDefaults?.set(newValue, forKey: AppConstants.Keys.notificationsEnabled)
            if !newValue {
                center.removeAllPendingNotificationRequests()
            }
        }
    }
}
