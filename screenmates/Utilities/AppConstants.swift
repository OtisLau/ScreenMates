import Foundation

struct AppConstants {

    // MARK: - App Group
    // Shared storage bucket that lets the main app, the extension, and the widget talk to each other
    static let appGroupSuite = "group.com.otishlau.screenmates"

    // MARK: - CloudKit
    static let cloudKitContainerID = "iCloud.com.otishlau.screenmates"

    // MARK: - Test Mode
    // Flip this to false before shipping to production.
    // It controls block size, how often the extension uploads, and how often the dashboard refreshes.
    static let isTestMode = true

    // 0:00 -> 23:59 = 1439 total threshold minutes in a day.
    static let maxThresholdMinuteOfDay = (24 * 60) - 1

    // MARK: - Block Size
    // One "block" = this many minutes of screen time.
    // In test mode we use 1 min blocks for quick end-to-end verification.
    // We pair that with a small checkpoint cap (see below) to avoid a huge event map.
    // In production, 15 min per block covers a full 24-hour day within Apple's 96-event limit.
    static let testModeBlockSize   = 1   // minutes
    static let productionBlockSize = 15  // minutes
    static let currentBlockSize    = isTestMode ? testModeBlockSize : productionBlockSize

    // How many events to register per monitoring session/batch.
    // Test and production both use 96 to keep behavior aligned.
    static let testModeEventsPerBatch = 96
    static let productionEventsPerBatch = 96
    static let eventsPerMonitoringBatch = isTestMode ? testModeEventsPerBatch : productionEventsPerBatch

    // Always track from setup onward only (no same-day replay of historical usage).
    static let includesPastActivity = false

    // Force DeviceActivity to monitor all activity regardless of picker selection.
    // Keep this true for maximum reliability in background tracking.
    static let monitorAllActivity = true

    // Absolute ceiling for thresholds/blocks in one day based on block size.
    // This is separate from eventsPerMonitoringBatch.
    static let maxTrackableBlocksPerDay = thresholdEventsPerDay(for: currentBlockSize)

    // Heuristic for "all categories selected" in FamilyActivityPicker.
    // If apps/domains are empty and category token count reaches this value,
    // we treat monitoring as all-activity to avoid category-only gaps on some devices.
    static let allCategoryTokenCountForAllActivityFallback = 13

    // MARK: - Timing
    // How often the extension is allowed to upload your data to CloudKit after a threshold fires.
    // This needs to be LESS than the block size (15 min) so every threshold results in an upload.
    // We use 5 min as a safe buffer — short enough to upload on every 15-min block,
    // but long enough to ignore any duplicate callbacks iOS fires in quick succession.
    static let testModeUploadThrottle:   TimeInterval = 30     // 30 seconds (fast for testing)
    static let productionUploadThrottle: TimeInterval = 5 * 60 // 5 minutes (uploads on every 15-min block)
    static let uploadThrottleSeconds = isTestMode ? testModeUploadThrottle : productionUploadThrottle

    // How often the dashboard auto-refreshes while the app is open.
    static let testModeDashboardRefresh:   TimeInterval = 30  // 30 seconds
    static let productionDashboardRefresh: TimeInterval = 60  // 1 minute
    static let dashboardRefreshInterval = isTestMode ? testModeDashboardRefresh : productionDashboardRefresh

    // How often the background task wakes up to sync when the app is closed.
    // iOS doesn't guarantee exact timing on this — treat it as a best-effort fallback.
    static let backgroundTaskIdentifier = "com.otishlau.screenmates.refresh"
    static let backgroundTaskInterval: TimeInterval = 15 * 60 // 15 minutes

    // MARK: - UserDefaults Keys
    // All the keys used to read/write from App Group storage
    struct Keys {
        static let dailyBlocksUsed      = "DailyBlocksUsed"
        static let lastBlockDate        = "LastBlockDate"
        static let cachedLeaderboardData = "CachedLeaderboardData"
        static let lastBackgroundSync   = "LastBackgroundSync"
        static let backgroundSyncHistory = "BackgroundSyncHistory"

        // Identity mirrored into App Group so the extension can upload to CloudKit
        static let sharedUserID       = "SharedMyUserID"
        static let sharedDisplayName  = "SharedMyDisplayName"
        static let sharedGroupID      = "SharedMyGroupID"

        // Config values mirrored into App Group so the extension and widget can read them
        static let sharedBlockSizeMinutes   = "SharedBlockSizeMinutes"
        static let sharedUploadThrottle     = "SharedUploadThrottleSeconds" // extension reads this
        // Timestamp of the last start/restart of monitoring (for debug display only).
        static let monitoringSetupTimestamp = "MonitoringSetupTimestamp"

        // Last threshold index where we already performed automatic batch rollover.
        static let lastAutoBatchRolloverIndex = "LastAutoBatchRolloverIndex"
    }

    static func thresholdEventsPerDay(for blockSize: Int) -> Int {
        guard blockSize > 0 else { return 0 }
        // ceil(maxThresholdMinuteOfDay / blockSize) without floating point.
        return (maxThresholdMinuteOfDay + blockSize - 1) / blockSize
    }
}
