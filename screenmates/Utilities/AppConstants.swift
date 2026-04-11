import Foundation

struct AppConstants {

    // MARK: - App Group
    static let appGroupSuite = "group.com.otishlau.screenmates"

    // MARK: - CloudKit
    static let cloudKitContainerID = "iCloud.com.otishlau.screenmates"

    // MARK: - Test Mode
    // Flip this to false before shipping to production.
    static let isTestMode = false

    // MARK: - Phone Auth
    // Accept any 6-digit code without calling Twilio. Flip to false once the
    // Twilio proxy (Cloudflare Worker) is deployed and credentials are set.
    static let skipOTPVerification = true

    // 0:00 -> 23:59 = 1439 total threshold minutes in a day.
    static let maxThresholdMinuteOfDay = (24 * 60) - 1

    // MARK: - Block Size
    // One "block" = this many minutes of screen time.
    // Test: 1 min blocks for quick verification. Prod: 15 min to fit Apple's 96-event limit.
    static let currentBlockSize = isTestMode ? 1 : 15

    // How many events to register per monitoring session/batch.
    static let eventsPerMonitoringBatch = 96

    // Always track from setup onward only (no same-day replay of historical usage).
    static let includesPastActivity = false

    // Force DeviceActivity to monitor all activity regardless of picker selection.
    static let monitorAllActivity = true

    // Absolute ceiling for thresholds/blocks in one day based on block size.
    static let maxTrackableBlocksPerDay = thresholdEventsPerDay(for: currentBlockSize)

    // Heuristic for "all categories selected" in FamilyActivityPicker.
    static let allCategoryTokenCountForAllActivityFallback = 13

    // MARK: - Timing
    // How often the dashboard auto-refreshes while the app is open.
    static let dashboardRefreshInterval: TimeInterval = isTestMode ? 30 : 60

    // How often the background task wakes up to sync when the app is closed.
    static let backgroundTaskIdentifier = "com.otishlau.screenmates.refresh"
    static let backgroundTaskInterval: TimeInterval = 15 * 60

    // MARK: - UserDefaults Keys
    struct Keys {
        static let dailyBlocksUsed       = "DailyBlocksUsed"
        static let lastBlockDate         = "LastBlockDate"
        static let cachedLeaderboardData = "CachedLeaderboardData"

        // Identity mirrored into App Group so the extension can read them
        static let sharedUserID       = "SharedMyUserID"
        static let sharedDisplayName  = "SharedMyDisplayName"
        static let sharedGroupID      = "SharedMyGroupID"

        // Config values mirrored into App Group so the extension and widget can read them
        static let sharedBlockSizeMinutes  = "SharedBlockSizeMinutes"

        // Last threshold index where we already performed automatic batch rollover.
        static let lastAutoBatchRolloverIndex = "LastAutoBatchRolloverIndex"

        // The index of the last threshold event processed by the extension.
        static let lastThresholdIndex = "LastThresholdIndex"
        static let sharedGoalMinutes  = "SharedGoalMinutes"

        // Post-midnight tracking (blocks accumulated between 12AM–4AM)
        static let postMidnightBlocksUsed = "PostMidnightBlocksUsed"

        // Notification dedup
        static let notificationsSentToday = "NotificationsSentToday"
        static let notificationsSentDate  = "NotificationsSentDate"

        static let monitoringSetupTimestamp = "MonitoringSetupTimestamp"

        // Phone auth identity (stored in standard UserDefaults)
        static let isPhoneVerified    = "IsPhoneVerified"
        static let contactsHandled    = "ContactsHandled"
        static let phoneNumberE164    = "PhoneNumberE164"
        static let phoneHash          = "PhoneHash"
        static let authProviderUserID = "AuthProviderUserID"
    }

    static func thresholdEventsPerDay(for blockSize: Int) -> Int {
        guard blockSize > 0 else { return 0 }
        return (maxThresholdMinuteOfDay + blockSize - 1) / blockSize
    }
}
