import DeviceActivity
import ManagedSettings
import Foundation
import CloudKit
import WidgetKit

class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    let suiteName = "group.com.otishlau.screenmates"
    private let cloudContainerID = "iCloud.com.otishlau.screenmates"
    private let maxDailyCheckpoints: Int = 96

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

        // 1. Check for midnight reset
        let lastDate = sharedDefaults.object(forKey: "LastBlockDate") as? Date ?? Date()
        if !Calendar.current.isDateInToday(lastDate) {
            sharedDefaults.set(0, forKey: "DailyBlocksUsed")
            sharedDefaults.set(0, forKey: "LastThresholdIndex")
            sharedDefaults.set(0, forKey: "BlockResetOffset") // clear any manual reset offset at midnight
        }

        // 2. Update the block count
        // The event name is "block_N" — treat it as "you have reached at least N blocks today",
        // NOT "+1 every callback" (iOS can fire duplicates, especially after monitoring starts).
        let thresholdIndex = parseThresholdIndex(from: event.rawValue) ?? 0
        let lastIndex = sharedDefaults.integer(forKey: "LastThresholdIndex")

        var currentBlocks = sharedDefaults.integer(forKey: "DailyBlocksUsed")
        if thresholdIndex > 0 {
            if thresholdIndex > lastIndex {
                // Subtract the reset offset so that after a manual reset the count
                // starts from 0 again instead of jumping to the raw threshold number.
                // e.g. block_33 with offset 32 → 1 block displayed.
                let resetOffset = sharedDefaults.integer(forKey: "BlockResetOffset")
                currentBlocks = max(0, thresholdIndex - resetOffset)
                sharedDefaults.set(thresholdIndex, forKey: "LastThresholdIndex")
            } else {
                // Duplicate / out-of-order callback — ignore
                return
            }
        } else {
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

        // 4. Tell the widget to reload so it shows fresh data immediately
        WidgetCenter.shared.reloadAllTimelines()

        // 5. Upload to CloudKit so friends see your updated count
        attemptCloudUpload(sharedDefaults: sharedDefaults, currentBlocks: currentBlocks)
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
