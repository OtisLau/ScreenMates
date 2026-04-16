import DeviceActivity
import ManagedSettings
import Foundation
import Darwin

class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    let suiteName = "group.com.otishlau.screenmates"
    private let lastThresholdIndexKey = "LastThresholdIndex"
    private let sharedStateLockName = "ScreenMatesExtensionState.lock"

    private lazy var sharedDefaults: UserDefaults? = UserDefaults(suiteName: suiteName)

    private var blockSizeMinutes: Int {
        let bs = sharedDefaults?.integer(forKey: "SharedBlockSizeMinutes") ?? 0
        return bs > 0 ? bs : 15
    }

    private var maxTrackableBlocksPerDay: Int {
        let blockSize = blockSizeMinutes
        return max(((24 * 60) - 1 + blockSize - 1) / blockSize, 1)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        guard let sharedDefaults else {
            print("App Group UserDefaults unavailable for suite '\(suiteName)'")
            return
        }

        sharedDefaults.set(Date(), forKey: "LastExtensionWakeDate")
        sharedDefaults.set(event.rawValue, forKey: "LastExtensionWakeEvent")

        withSharedStateLock {
            processThresholdEvent(event, sharedDefaults: sharedDefaults)
        }
    }

    private func processThresholdEvent(_ event: DeviceActivityEvent.Name, sharedDefaults: UserDefaults) {
        let now = Date()
        let lastBlockDate = sharedDefaults.object(forKey: "LastBlockDate") as? Date ?? .distantPast

        // Self-heal day rollover: if the stored day has rolled over, zero the counters
        // right here rather than waiting for the app to wake. Otherwise every threshold
        // from midnight until the app next runs would be dropped, losing hours of tracking.
        if !Calendar.current.isDate(lastBlockDate, inSameDayAs: now) {
            sharedDefaults.set(0, forKey: "DailyBlocksUsed")
            sharedDefaults.set(0, forKey: "PostMidnightBlocksUsed")
            sharedDefaults.set(0, forKey: lastThresholdIndexKey)
            sharedDefaults.set(0, forKey: "LastAutoBatchRolloverIndex")
        }

        let thresholdIndex = parseThresholdIndex(from: event.rawValue) ?? 0
        let lastIndex = sharedDefaults.integer(forKey: lastThresholdIndexKey)

        // Deduplicate and track position for batch-exhaustion detection by the main app.
        guard thresholdIndex > lastIndex else { return }
        sharedDefaults.set(thresholdIndex, forKey: lastThresholdIndexKey)

        // Wall-clock rate limit: only count a block if enough real time has elapsed since
        // the last one. This makes catch-up replays after restartMonitoring() no-ops —
        // they all fire in rapid succession so the rate limit blocks all but the first.
        let blockSize = blockSizeMinutes
        let blockSizeSeconds = Double(blockSize * 60)
        let elapsed = now.timeIntervalSince(lastBlockDate)
        guard elapsed >= blockSizeSeconds else {
            print("Rate limited: \(Int(elapsed))s since last block (need \(blockSize * 60)s)")
            return
        }

        let previousBlocks = sharedDefaults.integer(forKey: "DailyBlocksUsed")
        let currentBlocks = min(max(thresholdIndex, previousBlocks), maxTrackableBlocksPerDay)

        // Track post-midnight usage (12AM–4AM local) for notifications.
        let hour = Calendar.current.component(.hour, from: now)
        if hour < 4 && currentBlocks > previousBlocks {
            let postMidnight = sharedDefaults.integer(forKey: "PostMidnightBlocksUsed")
            sharedDefaults.set(postMidnight + 1, forKey: "PostMidnightBlocksUsed")
        }

        sharedDefaults.set(currentBlocks, forKey: "DailyBlocksUsed")
        sharedDefaults.set(now, forKey: "LastBlockDate")
        sharedDefaults.set(event.rawValue, forKey: "LastExtensionThresholdEvent")
        sharedDefaults.set(currentBlocks, forKey: "LastExtensionBlocksAtThreshold")

        print("Threshold hit. Daily total: \(currentBlocks) blocks")

        updateWidgetCache(sharedDefaults: sharedDefaults, currentBlocks: currentBlocks)
    }

    private func withSharedStateLock(_ body: () -> Void) {
        guard let lockURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: suiteName)?
            .appendingPathComponent(sharedStateLockName)
        else {
            body()
            return
        }

        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            body()
            return
        }
        defer { close(fd) }

        guard flock(fd, LOCK_EX) == 0 else {
            body()
            return
        }
        defer { flock(fd, LOCK_UN) }

        body()
    }

    // Minimal struct matching the JSON schema of CachedMember in the main app.
    private struct CachedMember: Codable {
        let id: String
        let userID: String
        let displayName: String
        var blocks: Int
        var lastUpdate: Date
        var postMidnightBlocks: Int?
    }

    // Updates the current user's row in the leaderboard cache.
    // The extension only writes — it does NOT call reloadAllTimelines() to avoid OOM races.
    private func updateWidgetCache(sharedDefaults: UserDefaults, currentBlocks: Int) {
        guard
            let userID      = sharedDefaults.string(forKey: "SharedMyUserID"), !userID.isEmpty,
            let displayName = sharedDefaults.string(forKey: "SharedMyDisplayName"), !displayName.isEmpty
        else { return }

        let cacheKey = "CachedLeaderboardData"
        var members: [CachedMember] = []
        if let data = sharedDefaults.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode([CachedMember].self, from: data) {
            members = decoded
        }

        let postMidnightBlocks = sharedDefaults.integer(forKey: "PostMidnightBlocksUsed")

        if let idx = members.firstIndex(where: { $0.userID == userID }) {
            members[idx] = CachedMember(id: userID, userID: userID,
                                        displayName: displayName,
                                        blocks: currentBlocks, lastUpdate: Date(),
                                        postMidnightBlocks: postMidnightBlocks)
        } else {
            members.append(CachedMember(id: userID, userID: userID,
                                        displayName: displayName,
                                        blocks: currentBlocks, lastUpdate: Date(),
                                        postMidnightBlocks: postMidnightBlocks))
        }

        if let encoded = try? JSONEncoder().encode(members) {
            sharedDefaults.set(encoded, forKey: cacheKey)
        }
    }

    private func parseThresholdIndex(from raw: String) -> Int? {
        guard raw.hasPrefix("block_") else { return nil }
        return Int(raw.dropFirst("block_".count))
    }
}
