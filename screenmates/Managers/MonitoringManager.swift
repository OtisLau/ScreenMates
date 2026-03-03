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

        let lastIndex  = sharedDefaults?.integer(forKey: "LastThresholdIndex") ?? 0
        let blockSize  = AppConstants.currentBlockSize
        let maxMinutes = (24 * 60) - 1 // 23:59

        // Build the next batch of events continuing from where we left off
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for i in 1...AppConstants.maxDailyCheckpoints {
            let index   = lastIndex + i
            let minutes = index * blockSize
            guard minutes <= maxMinutes else { break }

            events[DeviceActivityEvent.Name("block_\(index)")] = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories:   selection.categoryTokens,
                webDomains:   selection.webDomainTokens,
                threshold:    DateComponents(minute: minutes)
            )
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

        do {
            try center.startMonitoring(DeviceActivityName("dailyTracking"), during: schedule, events: events)
            // Zero the display count so blocks start climbing from 0 in the new batch
            sharedDefaults?.set(0, forKey: AppConstants.Keys.dailyBlocksUsed)
            print("✅ Monitoring restarted from block_\(lastIndex + 1) with \(events.count) events")
        } catch {
            print("❌ Failed to restart monitoring: \(error)")
        }
    }
}
