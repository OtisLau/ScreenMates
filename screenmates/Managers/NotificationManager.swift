import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    private let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)
    private init() {
        // Register default so existing users have notifications enabled
        UserDefaults.standard.register(defaults: ["notificationsEnabled": true])
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            print(" Notification permission request failed: \(error.localizedDescription)")
            return false
        }
    }

    var isAuthorized: Bool {
        get async {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return settings.authorizationStatus == .authorized
        }
    }

    // MARK: - Evaluate & Schedule

    // Called after every group data refresh. Checks all three scenarios
    // and schedules notifications if conditions are met.
    func evaluateAndSchedule(
        groupMembers: [MemberData],
        myUserID: String,
        goalMinutes: Int
    ) {
        // Respect user toggle
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else { return }
        guard !groupMembers.isEmpty else { return }

        Task {
            guard await isAuthorized else { return }

            cleanupSentKeysIfNewDay()

            if goalMinutes > 0 {
                scheduleOverLimitNotifications(members: groupMembers, goalMinutes: goalMinutes)
                scheduleEndOfDaySummary(members: groupMembers, goalMinutes: goalMinutes)
            }
            scheduleMorningDoomScroll(members: groupMembers)
        }
    }

    // MARK: - Scenario 1: Over Limit (immediate)

    private func scheduleOverLimitNotifications(members: [MemberData], goalMinutes: Int) {
        let today = todayString()
        var scheduled = 0

        for member in members {
            guard member.minutesUsed > goalMinutes else { continue }

            let dedupKey = "overLimit-\(member.userID)-\(today)"
            guard !hasAlreadySent(key: dedupKey) else { continue }

            let copy = NotificationCopy.randomOverLimit(name: member.displayName)
            let content = UNMutableNotificationContent()
            content.title = copy.title
            content.body = copy.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: dedupKey,
                content: content,
                trigger: nil // deliver immediately
            )

            UNUserNotificationCenter.current().add(request)
            markSent(key: dedupKey)
            scheduled += 1

            // Cap at 3 immediate notifications to avoid flooding
            if scheduled >= 3 { break }
        }
    }

    // MARK: - Scenario 2: End of Day Summary (10 PM)

    private func scheduleEndOfDaySummary(members: [MemberData], goalMinutes: Int) {
        let today = todayString()
        let dedupKey = "endOfDay-\(today)"
        guard !hasAlreadySent(key: dedupKey) else { return }

        let hour = Calendar.current.component(.hour, from: Date())
        // Only schedule/send after 10 PM
        guard hour >= 22 else { return }

        // Find members who are 1h+ over the limit
        let overBy60 = members.filter { $0.minutesUsed >= goalMinutes + 60 }
        guard !overBy60.isEmpty else { return }

        // Pick the worst offender for the notification
        let worst = overBy60.max(by: { $0.minutesUsed < $1.minutesUsed })!
        let time = NotificationCopy.formatTime(worst.minutesUsed)
        let copy = NotificationCopy.randomEndOfDay(name: worst.displayName, time: time)

        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: dedupKey,
            content: content,
            trigger: nil // deliver immediately since we're already past 10 PM
        )

        UNUserNotificationCenter.current().add(request)
        markSent(key: dedupKey)
    }

    // MARK: - Scenario 3: Morning Doom Scroll (9:30 AM)

    private func scheduleMorningDoomScroll(members: [MemberData]) {
        let today = todayString()
        let hour = Calendar.current.component(.hour, from: Date())

        // Between 6 AM and noon, check for late-night usage
        guard hour >= 6 && hour < 12 else { return }

        // Minimum 1h of post-midnight usage to trigger (4 blocks in prod, 60 in test)
        let minBlocks = 60 / AppConstants.currentBlockSize
        let doomScrollers = members.filter { $0.postMidnightBlocks >= minBlocks }
        guard !doomScrollers.isEmpty else { return }

        for member in doomScrollers {
            let dedupKey = "morning-\(member.userID)-\(today)"
            guard !hasAlreadySent(key: dedupKey) else { continue }

            let time = NotificationCopy.formatTime(member.postMidnightMinutes)
            let copy = NotificationCopy.randomMorningDoom(name: member.displayName, time: time)

            let content = UNMutableNotificationContent()
            content.title = copy.title
            content.body = copy.body
            content.sound = .default

            // If before 9:30 AM, schedule for 9:30 AM. Otherwise deliver immediately.
            let trigger: UNNotificationTrigger?
            let minute = Calendar.current.component(.minute, from: Date())
            if hour < 9 || (hour == 9 && minute < 30) {
                var dateComponents = DateComponents()
                dateComponents.hour = 9
                dateComponents.minute = 30
                trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            } else {
                trigger = nil
            }

            let request = UNNotificationRequest(
                identifier: dedupKey,
                content: content,
                trigger: trigger
            )

            UNUserNotificationCenter.current().add(request)
            markSent(key: dedupKey)
        }
    }

    // MARK: - Deduplication

    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func hasAlreadySent(key: String) -> Bool {
        let sent = UserDefaults.standard.stringArray(forKey: AppConstants.Keys.notificationsSentToday) ?? []
        return sent.contains(key)
    }

    private func markSent(key: String) {
        var sent = UserDefaults.standard.stringArray(forKey: AppConstants.Keys.notificationsSentToday) ?? []
        sent.append(key)
        UserDefaults.standard.set(sent, forKey: AppConstants.Keys.notificationsSentToday)
        UserDefaults.standard.set(todayString(), forKey: AppConstants.Keys.notificationsSentDate)
    }

    // Clear sent keys when a new day starts
    private func cleanupSentKeysIfNewDay() {
        let lastDate = UserDefaults.standard.string(forKey: AppConstants.Keys.notificationsSentDate) ?? ""
        if lastDate != todayString() {
            UserDefaults.standard.removeObject(forKey: AppConstants.Keys.notificationsSentToday)
            UserDefaults.standard.set(todayString(), forKey: AppConstants.Keys.notificationsSentDate)
        }
    }
}
