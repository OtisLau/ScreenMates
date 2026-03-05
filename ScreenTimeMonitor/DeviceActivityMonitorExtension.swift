import DeviceActivity
import ManagedSettings
import Foundation
import CloudKit

class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    let suiteName = "group.com.otishlau.screenmates"
    private let cloudContainerID = "iCloud.com.otishlau.screenmates"

    // The extension can't import AppConstants, so the main app mirrors this value into
    // App Group storage. If missing, fall back to deriving from block size.
    private var maxDailyCheckpoints: Int {
        let defaults = UserDefaults(suiteName: suiteName)
        let mirroredCap = defaults?.integer(forKey: "SharedMaxDailyCheckpoints") ?? 0
        if mirroredCap > 0 { return mirroredCap }

        let bs = defaults?.integer(forKey: "SharedBlockSizeMinutes") ?? 0
        let blockSize = bs > 0 ? bs : 15
        return (24 * 60) / blockSize
    }

    // The extension can't import AppConstants from the main app, so the main app mirrors
    // the upload throttle value into App Group storage. We read it here and fall back to
    // 30 minutes if it hasn't been set yet (i.e. app hasn't been opened once since install).
    private var uploadThrottleSeconds: TimeInterval {
        UserDefaults(suiteName: suiteName)?.double(forKey: "SharedUploadThrottleSeconds").nonZero ?? (30 * 60)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        let sharedDefaults = UserDefaults(suiteName: suiteName)
        guard let sharedDefaults else {
            print("❌ App Group UserDefaults unavailable for suite '\(suiteName)'")
            return
        }

        // Early wake marker — written before any guard/return so the debug menu can confirm
        // the extension process was actually launched by iOS, independent of all downstream logic.
        sharedDefaults.set(Date(), forKey: "LastExtensionWakeDate")
        sharedDefaults.set(event.rawValue, forKey: "LastExtensionWakeEvent")

        // 1. Check for midnight reset
        // Use .distantPast as the fallback so a fresh install (nil key) always triggers the
        // reset on the first callback, properly zeroing both counters before counting begins.
        let lastDate = sharedDefaults.object(forKey: "LastBlockDate") as? Date ?? .distantPast
        if !Calendar.current.isDateInToday(lastDate) {
            sharedDefaults.set(0, forKey: "DailyBlocksUsed")
            sharedDefaults.set(0, forKey: "LastThresholdIndex")
        }

        // 2. Update the block count
        // Use LastThresholdIndex to filter out duplicate/replayed callbacks from iOS,
        // but increment by 1 rather than using the raw threshold number.
        // This means DailyBlocksUsed is always a clean "blocks since last reset" count,
        // so zeroing DailyBlocksUsed is all a reset needs to do.
        let thresholdIndex = parseThresholdIndex(from: event.rawValue) ?? 0
        let lastIndex = sharedDefaults.integer(forKey: "LastThresholdIndex")

        // When startMonitoring() is called mid-day, iOS immediately fires callbacks for every
        // threshold already exceeded today. We stamp MonitoringSetupTimestamp just before
        // startMonitoring() so we can detect this replay window (first 15 seconds).
        //
        // During the replay window we use the events to build a baseline that reflects the
        // user's real accumulated screen time for today (sourced directly from the OS).
        // DailyBlocksUsed is set to the highest replayed threshold seen so far. The main app
        // uploads this baseline ~20 seconds after setup once replay has settled.
        // After the replay window, new events increment on top of that baseline as normal.
        let setupTime = sharedDefaults.object(forKey: "MonitoringSetupTimestamp") as? Date ?? .distantPast
        let isSetupReplay = Date().timeIntervalSince(setupTime) < 15

        var currentBlocks = sharedDefaults.integer(forKey: "DailyBlocksUsed")
        if thresholdIndex > 0 {
            if thresholdIndex > lastIndex {
                // Always advance the index so future deduplication works correctly.
                sharedDefaults.set(thresholdIndex, forKey: "LastThresholdIndex")
                if isSetupReplay {
                    // Replay event — use it to raise the baseline but don't increment.
                    // max() ensures the highest replayed threshold wins even with race conditions.
                    let baseline = max(currentBlocks, thresholdIndex)
                    sharedDefaults.set(baseline, forKey: "DailyBlocksUsed")
                    return
                }
                currentBlocks += 1
            } else {
                // Duplicate / out-of-order callback — ignore
                return
            }
        } else {
            if isSetupReplay { return }
            currentBlocks += 1
        }

        currentBlocks = min(currentBlocks, maxDailyCheckpoints)

        // 3. Persist
        sharedDefaults.set(currentBlocks, forKey: "DailyBlocksUsed")
        sharedDefaults.set(Date(), forKey: "LastBlockDate")
        sharedDefaults.set(Date(), forKey: "LastExtensionThresholdDate")
        sharedDefaults.set(event.rawValue, forKey: "LastExtensionThresholdEvent")
        sharedDefaults.set(currentBlocks, forKey: "LastExtensionBlocksAtThreshold")

        print("🧱 Threshold hit. Daily total: \(currentBlocks) blocks")

        // 4. Update the current user's entry in the widget cache so the widget shows
        //    fresh data for the local user without waiting for a CloudKit round-trip.
        //    Then tell the widget to reload — but throttle to max once per 30 seconds
        //    so rapid replay events don't hammer the widget process into an OOM kill.
        updateWidgetCache(sharedDefaults: sharedDefaults, currentBlocks: currentBlocks)

        // 5. Upload to CloudKit so friends see your updated count
        attemptCloudUpload(sharedDefaults: sharedDefaults, currentBlocks: currentBlocks)
    }

    // Minimal struct that matches the JSON schema of MemberData / CachedMember so the
    // extension can update the leaderboard cache without importing the main app target.
    private struct CachedMember: Codable {
        let id: String
        let userID: String
        let displayName: String
        var blocks: Int
        var lastUpdate: Date
    }

    // Updates the current user's row in the leaderboard cache.
    // The extension only writes to the cache — it does NOT call reloadAllTimelines().
    // Calling reloadAllTimelines() from the extension can race with the main app's own
    // reloadTimelines() calls (triggered by the 30s dashboard timer and CloudKit pushes),
    // spawning two concurrent widget processes that together exceed the widget memory limit.
    //
    // The widget picks up the updated cache via:
    //   1. The main app's reloadTimelines(ofKind:) on every 30s refresh / CloudKit push
    //   2. The widget's own 15-minute self-refresh policy
    private func updateWidgetCache(sharedDefaults: UserDefaults, currentBlocks: Int) {
        guard
            let userID      = sharedDefaults.string(forKey: "SharedMyUserID"),   !userID.isEmpty,
            let displayName = sharedDefaults.string(forKey: "SharedMyDisplayName"), !displayName.isEmpty
        else { return }

        let cacheKey = "CachedLeaderboardData"
        var members: [CachedMember] = []
        if let data = sharedDefaults.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode([CachedMember].self, from: data) {
            members = decoded
        }

        // Find the current user's row and update it; add a new row if not present yet.
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

    private func attemptCloudUpload(sharedDefaults: UserDefaults?, currentBlocks: Int) {
        guard let sharedDefaults else { return }

        // Throttle uploads
        let now = Date()
        let last = sharedDefaults.object(forKey: "LastExtensionCloudUpload") as? Date ?? .distantPast
        guard now.timeIntervalSince(last) >= uploadThrottleSeconds else { return }
        sharedDefaults.set(now, forKey: "LastExtensionCloudUpload")
        sharedDefaults.set(now, forKey: "LastExtensionCloudUploadAttempt")

        // Identity is mirrored into App Group by the main app on launch / setup
        guard
            let userID = sharedDefaults.string(forKey: "SharedMyUserID"), !userID.isEmpty,
            let displayName = sharedDefaults.string(forKey: "SharedMyDisplayName"), !displayName.isEmpty,
            let groupID = sharedDefaults.string(forKey: "SharedMyGroupID"), !groupID.isEmpty
        else {
            sharedDefaults.set(false, forKey: "LastExtensionCloudUploadSuccess")
            sharedDefaults.set("Skipped: missing identity in App Group (open app once after onboarding)", forKey: "LastExtensionCloudUploadError")
            return
        }

        let container = CKContainer(identifier: cloudContainerID)
        let database = container.publicCloudDatabase
        let recordID = CKRecord.ID(recordName: userID)

        Task {
            do {
                let record: CKRecord
                do {
                    record = try await database.record(for: recordID)
                } catch let error as CKError where error.code == .unknownItem {
                    record = CKRecord(recordType: "UserProfile", recordID: recordID)
                }

                record["user_id"] = userID
                record["display_name"] = displayName
                record["group_id"] = groupID
                record["blocks_used"] = currentBlocks
                record["last_updated"] = Date()
                record["last_active_date"] = Date()

                do {
                    _ = try await database.save(record)
                } catch let error as CKError where error.code == .serverRecordChanged {
                    let latest = try await database.record(for: recordID)
                    latest["user_id"] = userID
                    latest["display_name"] = displayName
                    latest["group_id"] = groupID
                    latest["blocks_used"] = currentBlocks
                    latest["last_updated"] = Date()
                    latest["last_active_date"] = Date()
                    _ = try await database.save(latest)
                }
                sharedDefaults.set(true, forKey: "LastExtensionCloudUploadSuccess")
                sharedDefaults.removeObject(forKey: "LastExtensionCloudUploadError")
                print("✅ Extension: uploaded \(currentBlocks) blocks to CloudKit")
            } catch {
                print("❌ Extension CloudKit upload failed: \(error.localizedDescription)")
                sharedDefaults.set(false, forKey: "LastExtensionCloudUploadSuccess")
                sharedDefaults.set(error.localizedDescription, forKey: "LastExtensionCloudUploadError")
            }
        }
    }

    private func parseThresholdIndex(from raw: String) -> Int? {
        guard raw.hasPrefix("block_") else { return nil }
        let suffix = raw.dropFirst("block_".count)
        return Int(suffix)
    }
}

// Helper so we can fall back when a stored Double is 0 (i.e. key was never set)
private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
