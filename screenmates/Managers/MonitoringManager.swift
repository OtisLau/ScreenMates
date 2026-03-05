import Foundation
import DeviceActivity
import FamilyControls

// Handles saving the app selection from onboarding and restarting monitoring mid-session.
// Useful in test mode when the daily 96-event cap is exhausted and you need to keep testing.
class MonitoringManager {
    static let shared = MonitoringManager()
    private init() {}

    private let defaults = UserDefaults.standard
    private let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)
    private let selectionKey = "SavedActivitySelection"

    // Returns the app / category / web-domain counts from the last saved selection.
    // Returns nil if no selection has been saved yet (user has never completed onboarding).
    var savedSelectionStats: (apps: Int, categories: Int, domains: Int)? {
        guard let data = defaults.data(forKey: selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return nil
        }
        return (selection.applicationTokens.count,
                selection.categoryTokens.count,
                selection.webDomainTokens.count)
    }

    // Encode and persist the FamilyActivitySelection so we can restart monitoring later
    // without going through onboarding again.
    func saveSelection(_ selection: FamilyActivitySelection) {
        if let encoded = try? JSONEncoder().encode(selection) {
            defaults.set(encoded, forKey: selectionKey)
            print("💾 Activity selection saved")
        }
    }

    // Re-register monitoring with a fresh batch of events starting after the last threshold
    // that already fired. This lets you continue testing after hitting the 96-event ceiling
    // without iOS immediately replaying already-exceeded thresholds.
    //
    // e.g. if LastThresholdIndex = 96, new events are block_97…block_192 at minutes 97…192.
    // Since your current usage is ~96 min, block_97 hasn't fired yet → extension wakes on next use.
    func restartMonitoring() {
        guard let data = defaults.data(forKey: selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            print("❌ No saved selection — open the app from scratch to reconfigure monitoring")
            return
        }

        // If the last block was recorded on a previous day, reset the index so we start
        // fresh from block_1 — otherwise lastIndex near the daily ceiling would produce
        // zero events and leave monitoring permanently dead until a manual re-onboard.
        let lastBlockDate = sharedDefaults?.object(forKey: AppConstants.Keys.lastBlockDate) as? Date ?? .distantPast
        if !Calendar.current.isDateInToday(lastBlockDate) {
            sharedDefaults?.set(0, forKey: "LastThresholdIndex")
        }

        let lastIndex  = sharedDefaults?.integer(forKey: "LastThresholdIndex") ?? 0
        let blockSize  = AppConstants.currentBlockSize
        let maxMinutes = (24 * 60) - 1 // 23:59

        // Build the next batch of events continuing from where we left off
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        let useAllActivityFallback =
            selection.applicationTokens.isEmpty &&
            selection.webDomainTokens.isEmpty &&
            selection.categoryTokens.count >= AppConstants.allCategoryTokenCountForAllActivityFallback
        if useAllActivityFallback {
            print("⚠️ Restart monitoring using all-activity fallback")
        }
        for i in 1...AppConstants.maxDailyCheckpoints {
            let index   = lastIndex + i
            let minutes = index * blockSize
            guard minutes <= maxMinutes else { break }

            let event: DeviceActivityEvent
            if #available(iOS 17.4, *) {
                if useAllActivityFallback {
                    event = DeviceActivityEvent(
                        threshold: DateComponents(minute: minutes),
                        includesPastActivity: true
                    )
                } else {
                    event = DeviceActivityEvent(
                        applications: selection.applicationTokens,
                        categories:   selection.categoryTokens,
                        webDomains:   selection.webDomainTokens,
                        threshold:    DateComponents(minute: minutes),
                        includesPastActivity: true
                    )
                }
            } else {
                if useAllActivityFallback {
                    event = DeviceActivityEvent(
                        threshold: DateComponents(minute: minutes)
                    )
                } else {
                    event = DeviceActivityEvent(
                        applications: selection.applicationTokens,
                        categories:   selection.categoryTokens,
                        webDomains:   selection.webDomainTokens,
                        threshold:    DateComponents(minute: minutes)
                    )
                }
            }
            events[DeviceActivityEvent.Name("block_\(index)")] = event
        }

        guard !events.isEmpty else {
            print("⚠️ No valid events to register — already at the 24-hour ceiling")
            return
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd:   DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        let center = DeviceActivityCenter()
        center.stopMonitoring()

        // Zero BEFORE startMonitoring to avoid a race condition:
        // if we zeroed AFTER, the extension could wake for a replay, increment the count,
        // and then this line would overwrite it back to 0 — leaving blocks stuck at 0.
        sharedDefaults?.set(0, forKey: AppConstants.Keys.dailyBlocksUsed)

        // Stamp now so the extension can distinguish iOS replay events (first 15 s after
        // startMonitoring) from genuinely new usage — same logic as in onboarding.
        sharedDefaults?.set(Date(), forKey: AppConstants.Keys.monitoringSetupTimestamp)

        do {
            try center.startMonitoring(DeviceActivityName("dailyTracking"), during: schedule, events: events)
            print("✅ Monitoring restarted from block_\(lastIndex + 1) with \(events.count) events")
        } catch {
            print("❌ Failed to restart monitoring: \(error)")
        }
    }
}
