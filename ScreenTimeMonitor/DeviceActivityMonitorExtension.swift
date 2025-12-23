import DeviceActivity
import ManagedSettings
import Foundation
import UserNotifications
import CloudKit

class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    
    let suiteName = "group.com.otishlau.screenmates"
    let notificationCenter = UNUserNotificationCenter.current()
    private let cloudContainerID = "iCloud.com.otishlau.screenmates"
    private let uploadThrottleSeconds: TimeInterval = 30
    private let maxDailyCheckpoints: Int = 96

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        
        let sharedDefaults = UserDefaults(suiteName: suiteName)
        guard let sharedDefaults else {
            // If this prints, the extension is firing but App Group storage isn't available
            // (almost always an entitlements / signing mismatch).
            print("❌ App Group UserDefaults unavailable for suite '\(suiteName)'")
            return
        }
        
        // 1. Check for Midnight Reset
        // If the last block was added yesterday, reset the count to 0 first.
        let lastDate = sharedDefaults.object(forKey: "LastBlockDate") as? Date ?? Date()
        if !Calendar.current.isDateInToday(lastDate) {
            sharedDefaults.set(0, forKey: "DailyBlocksUsed")
            sharedDefaults.set(0, forKey: "LastThresholdIndex")
            // Reset notification flags for new day
            sharedDefaults.set(false, forKey: "Notified75")
            sharedDefaults.set(false, forKey: "Notified90")
            sharedDefaults.set(false, forKey: "NotifiedOver")
        }
        
        // 2. Update the block count
        //
        // IMPORTANT: iOS may call `eventDidReachThreshold` multiple times in rapid succession
        // (especially right after monitoring starts) for thresholds that were already exceeded.
        // In test mode (1 min = 1 block) that can look like "96 blocks all at once".
        //
        // The event name is "block_N", so treat it as "you have reached at least N blocks today",
        // NOT "+1 every callback".
        let thresholdIndex = parseThresholdIndex(from: event.rawValue) ?? 0
        let lastIndex = sharedDefaults.integer(forKey: "LastThresholdIndex")

        var currentBlocks = sharedDefaults.integer(forKey: "DailyBlocksUsed")
        if thresholdIndex > 0 {
            // Only advance when we see a new index.
            if thresholdIndex > lastIndex {
                currentBlocks = max(currentBlocks, thresholdIndex)
                sharedDefaults.set(thresholdIndex, forKey: "LastThresholdIndex")
            } else {
                // Duplicate/out-of-order callback; ignore.
                return
            }
        } else {
            // Fallback if we can't parse the event name.
            currentBlocks += 1
        }

        currentBlocks = min(currentBlocks, maxDailyCheckpoints)
        
        // 3. Save Everything
        sharedDefaults.set(currentBlocks, forKey: "DailyBlocksUsed")
        sharedDefaults.set(Date(), forKey: "LastBlockDate")

        // Debug breadcrumbs so the main app can confirm the extension is firing.
        sharedDefaults.set(Date(), forKey: "LastExtensionThresholdDate")
        sharedDefaults.set(event.rawValue, forKey: "LastExtensionThresholdEvent")
        sharedDefaults.set(activity.rawValue, forKey: "LastExtensionThresholdActivity")
        sharedDefaults.set(currentBlocks, forKey: "LastExtensionBlocksAtThreshold")
        
        print("🧱 Block added! Daily Total: \(currentBlocks)")

        // 3.5 Upload to CloudKit (best-effort) so other devices see updates without opening the app.
        attemptCloudUpload(sharedDefaults: sharedDefaults, currentBlocks: currentBlocks)
        
        // 4. Send Notifications at Thresholds
        // Pull current goal from shared defaults (mirrored by the main app). Fall back to 12.
        let dailyGoal = sharedDefaults.integer(forKey: "SharedDailyGoalBlocks")
        let goal = dailyGoal > 0 ? dailyGoal : 12
        let percentage = Double(currentBlocks) / Double(goal)
        
        // Check if notifications are enabled (defaults to true if not set)
        let notificationsEnabled = sharedDefaults.object(forKey: "NotificationsEnabled") as? Bool ?? true
        guard notificationsEnabled else { return }
        
        // 75% warning
        if percentage >= 0.75 && percentage < 0.90 {
            let notified = sharedDefaults.bool(forKey: "Notified75")
            if !notified {
                sendNotification(
                    title: "⚠️ Approaching Your Limit",
                    body: "You've used \(currentBlocks) of \(goal) blocks today (75%)"
                )
                sharedDefaults.set(true, forKey: "Notified75")
            }
        }
        
        // 90% warning
        if percentage >= 0.90 && currentBlocks < goal {
            let notified = sharedDefaults.bool(forKey: "Notified90")
            if !notified {
                sendNotification(
                    title: "🚨 Almost at Your Limit!",
                    body: "You've used \(currentBlocks) of \(goal) blocks today (90%)"
                )
                sharedDefaults.set(true, forKey: "Notified90")
            }
        }
        
        // Over limit
        if currentBlocks >= goal {
            let notified = sharedDefaults.bool(forKey: "NotifiedOver")
            if !notified {
                sendNotification(
                    title: "❌ Over Your Daily Limit",
                    body: "You went over today's limit of \(goal) blocks"
                )
                sharedDefaults.set(true, forKey: "NotifiedOver")
            }
        }
    }

    private func attemptCloudUpload(sharedDefaults: UserDefaults?, currentBlocks: Int) {
        guard let sharedDefaults else { return }

        // Throttle uploads (especially in test mode where blocks can tick quickly).
        let now = Date()
        let last = sharedDefaults.object(forKey: "LastExtensionCloudUpload") as? Date ?? .distantPast
        guard now.timeIntervalSince(last) >= uploadThrottleSeconds else { return }
        sharedDefaults.set(now, forKey: "LastExtensionCloudUpload")
        sharedDefaults.set(now, forKey: "LastExtensionCloudUploadAttempt")

        // Identity is mirrored into App Group by the main app.
        guard
            let userID = sharedDefaults.string(forKey: "SharedMyUserID"), !userID.isEmpty,
            let displayName = sharedDefaults.string(forKey: "SharedMyDisplayName"), !displayName.isEmpty,
            let groupID = sharedDefaults.string(forKey: "SharedMyGroupID"), !groupID.isEmpty
        else {
            sharedDefaults.set(false, forKey: "LastExtensionCloudUploadSuccess")
            sharedDefaults.set("Skipped: missing SharedMyUserID/SharedMyDisplayName/SharedMyGroupID (open the app once after onboarding/joining group)", forKey: "LastExtensionCloudUploadError")
            return
        }

        let streak = sharedDefaults.integer(forKey: "CurrentStreak")
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
                record["streak"] = streak
                record["last_updated"] = Date()
                record["last_active_date"] = Date()

                do {
                    _ = try await database.save(record)
                } catch let error as CKError where error.code == .serverRecordChanged {
                    // If the main app saved at the same time, refetch and retry once.
                    let latest = try await database.record(for: recordID)
                    latest["user_id"] = userID
                    latest["display_name"] = displayName
                    latest["group_id"] = groupID
                    latest["blocks_used"] = currentBlocks
                    latest["streak"] = streak
                    latest["last_updated"] = Date()
                    latest["last_active_date"] = Date()
                    _ = try await database.save(latest)
                }
                sharedDefaults.set(true, forKey: "LastExtensionCloudUploadSuccess")
                sharedDefaults.removeObject(forKey: "LastExtensionCloudUploadError")
            } catch {
                // Best effort; avoid spamming logs too much.
                print("❌ Extension CloudKit upload failed: \(error.localizedDescription)")
                sharedDefaults.set(false, forKey: "LastExtensionCloudUploadSuccess")
                sharedDefaults.set(error.localizedDescription, forKey: "LastExtensionCloudUploadError")
            }
        }
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        // Trigger immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("❌ Notification error: \(error)")
            } else {
                print("✅ Notification sent: \(title)")
            }
        }
    }

    private func parseThresholdIndex(from raw: String) -> Int? {
        // Expected: "block_42"
        guard raw.hasPrefix("block_") else { return nil }
        let suffix = raw.dropFirst("block_".count)
        return Int(suffix)
    }
}
