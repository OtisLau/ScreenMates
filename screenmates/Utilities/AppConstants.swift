import Foundation

/// Central location for all app-wide constants
struct AppConstants {
    // MARK: - App Group
    static let appGroupSuite = "group.com.otishlau.screenmates"
    
    // MARK: - CloudKit
    static let cloudKitContainerID = "iCloud.com.otishlau.screenmates"
    
    // MARK: - Time Blocks
    static let testModeBlockSize = 1 // 1 minute per block for testing
    static let productionBlockSize = 15 // 15 minutes per block for production
    
    // Use test mode for now
    static let currentBlockSize = testModeBlockSize
    static let isTestMode = true

    /// Number of DeviceActivity threshold events we register per day.
    /// iOS limits the number of events you can register, so this also becomes the maximum
    /// number of "blocks" we can count per day when using threshold events.
    static let maxDailyCheckpoints = 96
    
    // MARK: - Daily Goals
    static let defaultDailyGoalBlocks = 12 // 3 hours in production (12 * 15 min)
    
    // MARK: - Background Tasks
    static let backgroundTaskIdentifier = "com.otishlau.screenmates.refresh"
    static let backgroundTaskInterval: TimeInterval = 15 * 60 // 15 minutes
    
    // MARK: - UserDefaults Keys
    struct Keys {
        static let dailyBlocksUsed = "DailyBlocksUsed"
        static let lastBlockDate = "LastBlockDate"
        static let lastCheckDate = "LastCheckDate"
        static let currentStreak = "CurrentStreak"
        static let notificationsEnabled = "NotificationsEnabled"
        static let lastSyncTimestamp = "LastSyncTimestamp"
        static let cachedLeaderboardData = "CachedLeaderboardData"
        static let lastBackgroundSync = "LastBackgroundSync"
        static let backgroundSyncHistory = "BackgroundSyncHistory"

        // Identity mirrored into App Group so the ScreenTimeMonitor extension can upload to CloudKit
        static let sharedUserID = "SharedMyUserID"
        static let sharedDisplayName = "SharedMyDisplayName"
        static let sharedGroupID = "SharedMyGroupID"
        static let lastExtensionCloudUpload = "LastExtensionCloudUpload"

        // Group config mirrored into App Group so the extension can use the current daily goal.
        static let sharedDailyGoalBlocks = "SharedDailyGoalBlocks"

        // Display config mirrored into App Group so widgets can show minutes correctly.
        static let sharedBlockSizeMinutes = "SharedBlockSizeMinutes"
    }
}
