import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    private init() {
        UserDefaults.standard.register(defaults: ["notificationsEnabled": true])
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            print("Notification permission request failed: \(error.localizedDescription)")
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

    // Called after every friends refresh. Each member's usage is checked against
    // their own personal limit — no shared group goal.
    func evaluateAndSchedule(members: [MemberData], myUserID: String) {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else { return }
        guard !members.isEmpty else { return }

        Task {
            guard await isAuthorized else { return }
            cleanupSentKeysIfNewDay()
            scheduleOverLimitNotifications(members: members)
            scheduleEndOfDaySummary(members: members)
            scheduleMorningDoomScroll(members: members)
        }
    }

    // MARK: - Scenario 1: Over Limit (immediate)

    // Fires when any friend exceeds their own personal limit.
    // Skips members whose limit is 0 (no limit set).
    private func scheduleOverLimitNotifications(members: [MemberData]) {
        let today = todayString()

        for member in members {
            let limit = member.personalGoalMinutes
            guard limit > 0 else { continue }
            guard member.minutesUsed > limit else { continue }

            let dedupKey = "overLimit-\(member.userID)-\(today)"
            guard !hasAlreadySent(key: dedupKey) else { continue }

            let copy = NotificationCopy.randomOverLimit(
                name: member.displayName,
                usedMinutes: member.minutesUsed,
                goalMinutes: limit
            )
            let content = UNMutableNotificationContent()
            content.title = copy.title
            content.body = copy.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: dedupKey,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
            markSent(key: dedupKey)
        }
    }

    // MARK: - Scenario 2: End of Day Summary (10 PM)

    // Pick the worst offender across all friends who have a limit and are 1h+ over it.
    private func scheduleEndOfDaySummary(members: [MemberData]) {
        let today = todayString()
        let dedupKey = "endOfDay-\(today)"
        guard !hasAlreadySent(key: dedupKey) else { return }

        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= 22 else { return }

        let overBy60 = members.filter { m in
            m.personalGoalMinutes > 0 && m.minutesUsed >= m.personalGoalMinutes + 60
        }
        guard let worst = overBy60.max(by: { $0.minutesUsed < $1.minutesUsed }) else { return }
        let copy = NotificationCopy.randomEndOfDay(
            name: worst.displayName,
            usedMinutes: worst.minutesUsed,
            goalMinutes: worst.personalGoalMinutes
        )

        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.sound = .default

        let request = UNNotificationRequest(identifier: dedupKey, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        markSent(key: dedupKey)
    }

    // MARK: - Scenario 3: Morning Doom Scroll (9:30 AM)

    private func scheduleMorningDoomScroll(members: [MemberData]) {
        let today = todayString()
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= 6 && hour < 12 else { return }

        let minBlocks = max(1, Int(ceil(90.0 / Double(AppConstants.currentBlockSize))))
        let doomScrollers = members.filter { $0.postMidnightBlocks >= minBlocks }
        guard !doomScrollers.isEmpty else { return }

        for member in doomScrollers {
            let dedupKey = "morning-\(member.userID)-\(today)"
            guard !hasAlreadySent(key: dedupKey) else { continue }

            let copy = NotificationCopy.randomMorningDoom(
                name: member.displayName,
                postMidnightMinutes: member.postMidnightMinutes
            )

            let content = UNMutableNotificationContent()
            content.title = copy.title
            content.body = copy.body
            content.sound = .default

            let minute = Calendar.current.component(.minute, from: Date())
            let trigger: UNNotificationTrigger?
            if hour < 9 || (hour == 9 && minute < 30) {
                var dateComponents = DateComponents()
                dateComponents.hour = 9
                dateComponents.minute = 30
                trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            } else {
                trigger = nil
            }

            let request = UNNotificationRequest(identifier: dedupKey, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
            markSent(key: dedupKey)
        }
    }

    // MARK: - Deduplication

    private func todayString() -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let year  = components.year  ?? 0
        let month = components.month ?? 0
        let day   = components.day   ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
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

    private func cleanupSentKeysIfNewDay() {
        let lastDate = UserDefaults.standard.string(forKey: AppConstants.Keys.notificationsSentDate) ?? ""
        if lastDate != todayString() {
            UserDefaults.standard.removeObject(forKey: AppConstants.Keys.notificationsSentToday)
            UserDefaults.standard.set(todayString(), forKey: AppConstants.Keys.notificationsSentDate)
        }
    }
}
