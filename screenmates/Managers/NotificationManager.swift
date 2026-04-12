import Foundation
import UserNotifications

@MainActor
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
            await scheduleOverLimitNotifications(members: members)
            await scheduleEndOfDaySummary(members: members)
            await scheduleMorningDoomScroll(members: members)
        }
    }

    // MARK: - Scenario 1: Over Limit (immediate)

    // Fires when any friend exceeds their own personal limit.
    // Skips members whose limit is 0 (no limit set).
    private func scheduleOverLimitNotifications(members: [MemberData]) async {
        let today = dayBucketString()

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
            if await addNotificationRequest(request) {
                markSent(key: dedupKey)
            }
        }
    }

    // MARK: - Scenario 2: End of Day Summary (10 PM)

    // Pick the worst offender across all friends who have a limit and are 1h+ over it.
    private func scheduleEndOfDaySummary(members: [MemberData]) async {
        let today = dayBucketString()
        let dedupKey = "endOfDay-\(today)"
        guard !hasAlreadySent(key: dedupKey) else { return }

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

        guard let trigger = calendarTriggerForToday(hour: 22, minute: 0) else { return }
        let request = UNNotificationRequest(identifier: dedupKey, content: content, trigger: trigger)
        if await addNotificationRequest(request) {
            markSent(key: dedupKey)
        }
    }

    // MARK: - Scenario 3: Morning Doom Scroll (9:30 AM)

    private func scheduleMorningDoomScroll(members: [MemberData]) async {
        let today = dayBucketString()
        let now = Date()

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

            guard let trigger = calendarTriggerForToday(hour: 9, minute: 30, now: now) else { continue }

            let request = UNNotificationRequest(identifier: dedupKey, content: content, trigger: trigger)
            if await addNotificationRequest(request) {
                markSent(key: dedupKey)
            }
        }
    }

    @MainActor
    private func addNotificationRequest(_ request: UNNotificationRequest) async -> Bool {
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            print("Notification add failed (\(request.identifier)): \(error.localizedDescription)")
            return false
        }
    }

    private func calendarTriggerForToday(hour: Int, minute: Int, now: Date = Date()) -> UNCalendarNotificationTrigger? {
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: now)
        dateComponents.calendar = calendar
        dateComponents.timeZone = calendar.timeZone
        dateComponents.hour = hour
        dateComponents.minute = minute
        dateComponents.second = 0

        guard let fireDate = calendar.date(from: dateComponents), fireDate > now else { return nil }
        return UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
    }

    // MARK: - Deduplication

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func dayBucketString(date: Date = Date()) -> String {
        Self.dayFormatter.string(from: date)
    }

    private func hasAlreadySent(key: String) -> Bool {
        let sent = UserDefaults.standard.stringArray(forKey: AppConstants.Keys.notificationsSentToday) ?? []
        return sent.contains(key)
    }

    private func markSent(key: String) {
        var sent = UserDefaults.standard.stringArray(forKey: AppConstants.Keys.notificationsSentToday) ?? []
        sent.append(key)
        UserDefaults.standard.set(sent, forKey: AppConstants.Keys.notificationsSentToday)
        UserDefaults.standard.set(dayBucketString(), forKey: AppConstants.Keys.notificationsSentDate)
    }

    private func cleanupSentKeysIfNewDay() {
        let today = dayBucketString()
        let lastDate = UserDefaults.standard.string(forKey: AppConstants.Keys.notificationsSentDate) ?? ""
        if lastDate != today {
            UserDefaults.standard.removeObject(forKey: AppConstants.Keys.notificationsSentToday)
            UserDefaults.standard.set(today, forKey: AppConstants.Keys.notificationsSentDate)
        }
    }
}
