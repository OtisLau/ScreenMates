import DeviceActivity
import ManagedSettings
import Foundation
import CloudKit

class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    let suiteName = "group.com.otishlau.screenmates"
    private let cloudContainerID = "iCloud.com.otishlau.screenmates"
    private let monitoringSetupKey = "MonitoringSetupTimestamp"
    private let lastThresholdDateKey = "LastExtensionThresholdDate"
    private let lastThresholdIndexKey = "LastThresholdIndex"
    private let deltaClampDebugRawKey = "LastThresholdRawDelta"
    private let deltaClampDebugAppliedKey = "LastThresholdAppliedDelta"
    private let deltaClampDebugDateKey = "LastThresholdDeltaClampedDate"
    private let deltaClampDebugReasonKey = "LastThresholdDeltaClampedReason"
    private let deltaClampDebugRangeKey = "LastThresholdDeltaClampedRange"
    private let recentSetupClampWindow: TimeInterval = 20 * 60
    private let deltaJitterAllowance = 2

    // Single shared defaults instance — avoids re-allocating UserDefaults on every property access.
    private lazy var sharedDefaults: UserDefaults? = UserDefaults(suiteName: suiteName)

    // Hard cap of trackable thresholds in a day derived from block size only.
    private var maxTrackableBlocksPerDay: Int {
        let bs = sharedDefaults?.integer(forKey: "SharedBlockSizeMinutes") ?? 0
        let blockSize = bs > 0 ? bs : 15
        let maxThresholdMinuteOfDay = (24 * 60) - 1
        let dailyCap = (maxThresholdMinuteOfDay + blockSize - 1) / blockSize
        return max(dailyCap, 1)
    }

    private var blockSizeMinutes: Int {
        let bs = sharedDefaults?.integer(forKey: "SharedBlockSizeMinutes") ?? 0
        return bs > 0 ? bs : 15
    }

    // The extension can't import AppConstants from the main app, so the main app mirrors
    // the upload throttle value into App Group storage.
    private var uploadThrottleSeconds: TimeInterval {
        sharedDefaults?.double(forKey: "SharedUploadThrottleSeconds").nonZero ?? (30 * 60)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        guard let sharedDefaults else {
            print(" App Group UserDefaults unavailable for suite '\(suiteName)'")
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
            performHardDayRolloverReset(sharedDefaults: sharedDefaults)
        }

        // 2. Update the block count
        // Use LastThresholdIndex to dedupe callbacks and to recover skipped thresholds.
        // If iOS delivers block_137 after block_96 (or after a day reset), add the delta
        // rather than just +1 so local blocks stay aligned with real usage.
        let now = Date()
        let thresholdIndex = parseThresholdIndex(from: event.rawValue) ?? 0
        let lastIndex = sharedDefaults.integer(forKey: lastThresholdIndexKey)

        var currentBlocks = sharedDefaults.integer(forKey: "DailyBlocksUsed")
        if thresholdIndex > 0 {
            if thresholdIndex > lastIndex {
                // Always advance the index so future deduplication works correctly.
                sharedDefaults.set(thresholdIndex, forKey: lastThresholdIndexKey)
                let rawDelta = thresholdIndex - lastIndex
                let delta = appliedDeltaForThresholdJump(
                    rawDelta: rawDelta,
                    lastIndex: lastIndex,
                    thresholdIndex: thresholdIndex,
                    now: now,
                    sharedDefaults: sharedDefaults
                )
                currentBlocks += delta
            } else {
                // Duplicate / out-of-order callback — ignore
                return
            }
        } else {
            currentBlocks += 1
        }

        currentBlocks = min(currentBlocks, maxTrackableBlocksPerDay)

        // 2a. Post-restart rate limit
        // When monitoring restarts mid-day, iOS can immediately replay every threshold
        // up to today's accumulated device activity. Each fires with delta=1 so the
        // per-jump clamping above doesn't catch it. Cap growth to real elapsed time
        // since the restart so catch-up replays can't inflate the count.
        if let setupDate = sharedDefaults.object(forKey: monitoringSetupKey) as? Date {
            let setupAge = now.timeIntervalSince(setupDate)
            if setupAge >= 0 && setupAge <= recentSetupClampWindow {
                let blocksAtSetup = sharedDefaults.integer(forKey: "BlocksAtMonitoringSetup")
                let maxBlocksSinceRestart = Int(setupAge / Double(max(blockSizeMinutes, 1) * 60)) + deltaJitterAllowance
                let ceiling = blocksAtSetup + maxBlocksSinceRestart
                if currentBlocks > ceiling {
                    print(" Post-restart rate limit: capped \(currentBlocks) to \(ceiling) (setup \(Int(setupAge))s ago, baseline \(blocksAtSetup))")
                    currentBlocks = ceiling
                }
            }
        }

        // 2b. Track post-midnight usage (12AM–4AM) for doom scroll notifications
        let hour = Calendar.current.component(.hour, from: now)
        if hour < 4 {
            let delta = currentBlocks - sharedDefaults.integer(forKey: "DailyBlocksUsed")
            let postMidnight = sharedDefaults.integer(forKey: "PostMidnightBlocksUsed")
            sharedDefaults.set(postMidnight + max(delta, 1), forKey: "PostMidnightBlocksUsed")
        }

        // 3. Persist
        sharedDefaults.set(currentBlocks, forKey: "DailyBlocksUsed")
        sharedDefaults.set(now, forKey: "LastBlockDate")
        sharedDefaults.set(now, forKey: lastThresholdDateKey)
        sharedDefaults.set(event.rawValue, forKey: "LastExtensionThresholdEvent")
        sharedDefaults.set(currentBlocks, forKey: "LastExtensionBlocksAtThreshold")

        print(" Threshold hit. Daily total: \(currentBlocks) blocks")

        // 4. Update the current user's entry in the widget cache so the widget shows
        //    fresh data for the local user without waiting for a CloudKit round-trip.
        updateWidgetCache(sharedDefaults: sharedDefaults, currentBlocks: currentBlocks)

        // 5. Upload to CloudKit so friends see your updated count
        attemptCloudUpload(currentBlocks: currentBlocks)
    }

    // Minimal struct that matches the JSON schema of MemberData / CachedMember so the
    // extension can update the leaderboard cache without importing the main app target.
    private struct CachedMember: Codable {
        let id: String
        let userID: String
        let displayName: String
        var blocks: Int
        var lastUpdate: Date
        var postMidnightBlocks: Int?
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

    private func attemptCloudUpload(currentBlocks: Int) {
        guard let sharedDefaults else { return }

        // Throttle uploads — gate on last *successful* upload so a failed attempt
        // doesn't block the next threshold from retrying.
        let now = Date()
        let last = sharedDefaults.object(forKey: "LastExtensionCloudUpload") as? Date ?? .distantPast
        guard now.timeIntervalSince(last) >= uploadThrottleSeconds else { return }
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

                let postMidnightBlocks = sharedDefaults.integer(forKey: "PostMidnightBlocksUsed")
                record["user_id"] = userID
                record["display_name"] = displayName
                record["group_id"] = groupID
                record["blocks_used"] = currentBlocks
                record["post_midnight_blocks"] = postMidnightBlocks
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
                    latest["post_midnight_blocks"] = postMidnightBlocks
                    latest["last_updated"] = Date()
                    latest["last_active_date"] = Date()
                    _ = try await database.save(latest)
                }
                sharedDefaults.set(now, forKey: "LastExtensionCloudUpload")
                sharedDefaults.set(true, forKey: "LastExtensionCloudUploadSuccess")
                sharedDefaults.removeObject(forKey: "LastExtensionCloudUploadError")
                print(" Extension: uploaded \(currentBlocks) blocks to CloudKit")
            } catch {
                print(" Extension CloudKit upload failed: \(error.localizedDescription)")
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

    // Keeps large threshold jumps plausible: if iOS wakes us with a far-future block index
    // (e.g. block_96 right after setup or after a monitoring restart), cap the recovered
    // delta by how much time has actually elapsed since the reference event.
    //
    // Two clamping windows:
    //   1. "recent-setup": within 20 min of startMonitoring — guards against iOS replaying
    //      pre-setup activity despite includesPastActivity=false.
    //   2. "last-threshold": always active when lastIndex == 0 and a last-threshold date is
    //      recorded — guards against a monitoring restart resetting lastIndex to 0 while iOS
    //      immediately fires a high block number (which would add the full index as delta).
    //      After the first real threshold fires post-restart this case no longer triggers.
    private func appliedDeltaForThresholdJump(
        rawDelta: Int,
        lastIndex: Int,
        thresholdIndex: Int,
        now: Date,
        sharedDefaults: UserDefaults
    ) -> Int {
        guard rawDelta > 1 else { return max(rawDelta, 0) }

        let secondsPerBlock = TimeInterval(max(blockSizeMinutes, 1) * 60)
        guard secondsPerBlock > 0 else { return rawDelta }

        // Window 1: clamp during the first 20 min after monitoring was set up.
        if let setupDate = sharedDefaults.object(forKey: monitoringSetupKey) as? Date {
            let setupAge = now.timeIntervalSince(setupDate)
            if setupAge >= 0 && setupAge <= recentSetupClampWindow {
                return clampDeltaIfNeeded(
                    rawDelta: rawDelta,
                    lastIndex: lastIndex,
                    thresholdIndex: thresholdIndex,
                    reason: "recent-setup",
                    referenceDate: setupDate,
                    secondsPerBlock: secondsPerBlock,
                    now: now,
                    sharedDefaults: sharedDefaults
                )
            }
        }

        // Window 2: if a prior threshold date exists, use it as the time reference to cap
        // how many blocks can plausibly have elapsed since then.  This catches large jumps
        // at any point in the day — not just when lastIndex == 0 — so a delayed iOS
        // catch-up callback (e.g. block_96 arriving after block_5) can't add 91 blocks
        // in one shot and peg usage at 24 hours.
        if let lastThresholdDate = sharedDefaults.object(forKey: lastThresholdDateKey) as? Date {
            return clampDeltaIfNeeded(
                rawDelta: rawDelta,
                lastIndex: lastIndex,
                thresholdIndex: thresholdIndex,
                reason: "last-threshold",
                referenceDate: lastThresholdDate,
                secondsPerBlock: secondsPerBlock,
                now: now,
                sharedDefaults: sharedDefaults
            )
        }

        // No prior threshold date (cleared by day rollover or fresh install).
        // This is the first threshold of the day — cap delta at 1 to prevent
        // iOS firing a high block index and over-counting on a clean slate.
        if lastIndex == 0 && rawDelta > 1 {
            sharedDefaults.set(rawDelta, forKey: deltaClampDebugRawKey)
            sharedDefaults.set(1, forKey: deltaClampDebugAppliedKey)
            sharedDefaults.set(now, forKey: deltaClampDebugDateKey)
            sharedDefaults.set("first-of-day", forKey: deltaClampDebugReasonKey)
            sharedDefaults.set("block_0->block_\(thresholdIndex)", forKey: deltaClampDebugRangeKey)
            print(" Clamped first-of-day delta \(rawDelta) to 1")
            return 1
        }

        return rawDelta
    }

    private func clampDeltaIfNeeded(
        rawDelta: Int,
        lastIndex: Int,
        thresholdIndex: Int,
        reason: String,
        referenceDate: Date,
        secondsPerBlock: TimeInterval,
        now: Date,
        sharedDefaults: UserDefaults
    ) -> Int {
        let elapsed = max(0, now.timeIntervalSince(referenceDate))
        let plausibleSteps = Int(elapsed / secondsPerBlock)
        let maxPlausibleDelta = max(1, plausibleSteps + deltaJitterAllowance)
        guard rawDelta > maxPlausibleDelta else { return rawDelta }

        sharedDefaults.set(rawDelta, forKey: deltaClampDebugRawKey)
        sharedDefaults.set(maxPlausibleDelta, forKey: deltaClampDebugAppliedKey)
        sharedDefaults.set(now, forKey: deltaClampDebugDateKey)
        sharedDefaults.set(reason, forKey: deltaClampDebugReasonKey)
        sharedDefaults.set("block_\(lastIndex)->block_\(thresholdIndex)", forKey: deltaClampDebugRangeKey)
        print(" Clamped threshold delta \(rawDelta) to \(maxPlausibleDelta) [\(reason)]")

        return maxPlausibleDelta
    }

    // Keep extension-side day reset behavior aligned with the app-side reset.
    private func performHardDayRolloverReset(sharedDefaults: UserDefaults) {
        // Snapshot post-midnight blocks before zeroing so morning notifications can reference them
        let postMidnight = sharedDefaults.integer(forKey: "PostMidnightBlocksUsed")
        sharedDefaults.set(postMidnight, forKey: "YesterdayPostMidnightBlocks")

        sharedDefaults.set(0, forKey: "DailyBlocksUsed")
        sharedDefaults.set(0, forKey: lastThresholdIndexKey)
        sharedDefaults.set(0, forKey: "LastAutoBatchRolloverIndex")
        sharedDefaults.set(0, forKey: "PostMidnightBlocksUsed")
        sharedDefaults.set(Date(), forKey: "LastBlockDate")
        sharedDefaults.removeObject(forKey: "LastExtensionCloudUpload")
        sharedDefaults.removeObject(forKey: "LastExtensionCloudUploadAttempt")
        // Clear stale threshold date so delta clamping uses today's reference,
        // not yesterday's — prevents over-counting on the first threshold after midnight.
        sharedDefaults.removeObject(forKey: lastThresholdDateKey)
    }
}

// Helper so we can fall back when a stored Double is 0 (i.e. key was never set)
private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
