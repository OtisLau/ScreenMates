import DeviceActivity
import ManagedSettings
import Foundation

class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    let suiteName = "group.com.otishlau.screenmates"
    private let monitoringSetupKey = "MonitoringSetupTimestamp"
    private let lastThresholdIndexKey = "LastThresholdIndex"

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

        // Ignore events from yesterday's schedule — app will restart monitoring on next wake.
        let lastDate = sharedDefaults.object(forKey: "LastBlockDate") as? Date ?? .distantPast
        guard Calendar.current.isDateInToday(lastDate) else {
            print("Ignoring stale threshold from previous day's schedule")
            return
        }

        let now = Date()
        let thresholdIndex = parseThresholdIndex(from: event.rawValue) ?? 0
        let lastIndex = sharedDefaults.integer(forKey: lastThresholdIndexKey)

        // Deduplicate: ignore duplicate or out-of-order callbacks.
        guard thresholdIndex > lastIndex else { return }
        sharedDefaults.set(thresholdIndex, forKey: lastThresholdIndexKey)

        let delta = thresholdIndex - lastIndex
        let previousBlocks = sharedDefaults.integer(forKey: "DailyBlocksUsed")
        var currentBlocks = min(previousBlocks + delta, maxTrackableBlocksPerDay)

        // Post-restart rate limit: cap growth to real elapsed time in the 20 min after a
        // restart, so iOS catch-up replays (delta=1 each) can't inflate the count.
        if let setupDate = sharedDefaults.object(forKey: monitoringSetupKey) as? Date {
            let setupAge = now.timeIntervalSince(setupDate)
            if setupAge >= 0 && setupAge <= 20 * 60 {
                let blocksAtSetup = sharedDefaults.integer(forKey: "BlocksAtMonitoringSetup")
                let ceiling = blocksAtSetup + Int(setupAge / Double(blockSizeMinutes * 60)) + 2
                if currentBlocks > ceiling {
                    print("Post-restart rate limit: capped \(currentBlocks) to \(ceiling)")
                    currentBlocks = ceiling
                }
            }
        }

        // Track post-midnight usage (12AM–4AM) for notifications.
        let hour = Calendar.current.component(.hour, from: now)
        if hour < 4 {
            let actualDelta = currentBlocks - previousBlocks
            if actualDelta > 0 {
                let postMidnight = sharedDefaults.integer(forKey: "PostMidnightBlocksUsed")
                sharedDefaults.set(postMidnight + actualDelta, forKey: "PostMidnightBlocksUsed")
            }
        }

        sharedDefaults.set(currentBlocks, forKey: "DailyBlocksUsed")
        sharedDefaults.set(now, forKey: "LastBlockDate")
        sharedDefaults.set(event.rawValue, forKey: "LastExtensionThresholdEvent")
        sharedDefaults.set(currentBlocks, forKey: "LastExtensionBlocksAtThreshold")

        print("Threshold hit. Daily total: \(currentBlocks) blocks")

        updateWidgetCache(sharedDefaults: sharedDefaults, currentBlocks: currentBlocks)
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

        if let idx = members.firstIndex(where: { $0.userID == userID }) {
            members[idx] = CachedMember(id: userID, userID: userID,
                                        displayName: displayName,
                                        blocks: currentBlocks, lastUpdate: Date())
        } else {
            members.append(CachedMember(id: userID, userID: userID,
                                        displayName: displayName,
                                        blocks: currentBlocks, lastUpdate: Date()))
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
