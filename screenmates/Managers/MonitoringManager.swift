import Foundation
import DeviceActivity
import FamilyControls

// Handles saving the app selection from onboarding and restarting monitoring mid-session.
// Useful in test mode when the current event batch is exhausted and you need to keep testing.
class MonitoringManager {
    static let shared = MonitoringManager()
    private init() {}

    private let defaults = UserDefaults.standard
    private let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)
    private let selectionKey = "SavedActivitySelection"

    // Clears all per-day tracking state and stamps "today" as the active tracking day.
    // Returns true when a reset was performed.
    @discardableResult
    func performHardDayRolloverResetIfNeeded(now: Date = Date()) -> Bool {
        guard let sharedDefaults else { return false }

        let lastBlockDate = sharedDefaults.object(forKey: AppConstants.Keys.lastBlockDate) as? Date ?? .distantPast
        guard !Calendar.current.isDate(lastBlockDate, inSameDayAs: now) else { return false }

        sharedDefaults.set(0, forKey: AppConstants.Keys.dailyBlocksUsed)
        sharedDefaults.set(0, forKey: AppConstants.Keys.lastThresholdIndex)
        sharedDefaults.set(0, forKey: AppConstants.Keys.lastAutoBatchRolloverIndex)
        sharedDefaults.set(now, forKey: AppConstants.Keys.lastBlockDate)

        // Remove upload throttles so the first post-midnight threshold uploads immediately.
        sharedDefaults.removeObject(forKey: "LastExtensionCloudUpload")
        sharedDefaults.removeObject(forKey: "LastExtensionCloudUploadAttempt")

        return true
    }

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
            print(" Activity selection saved")
        }
    }

    // Re-register monitoring with a fresh batch of events starting after the last threshold
    // that already fired. This lets testing continue after a batch is exhausted without
    // wiping already-counted usage.
    //
    // e.g. if LastThresholdIndex = 96, new events are block_97…block_192 at minutes 97…192.
    // Since your current usage is ~96 min, block_97 hasn't fired yet → extension wakes on next use.
    func restartMonitoring() {
        let selection: FamilyActivitySelection? = {
            guard let data = defaults.data(forKey: selectionKey) else { return nil }
            return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        }()

        if !AppConstants.monitorAllActivity && selection == nil {
            print(" No saved selection — open the app from scratch to reconfigure monitoring")
            return
        }

        _ = performHardDayRolloverResetIfNeeded()

        let lastIndex  = sharedDefaults?.integer(forKey: AppConstants.Keys.lastThresholdIndex) ?? 0
        let blockSize  = AppConstants.currentBlockSize
        let maxMinutes = AppConstants.maxThresholdMinuteOfDay

        // Build the next batch of events continuing from where we left off
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        let useAllActivity =
            AppConstants.monitorAllActivity ||
            (selection?.applicationTokens.isEmpty == true &&
             selection?.webDomainTokens.isEmpty == true &&
             (selection?.categoryTokens.count ?? 0) >= AppConstants.allCategoryTokenCountForAllActivityFallback)
        if useAllActivity {
            print(" Restart monitoring using all-activity mode")
        }
        for i in 1...AppConstants.eventsPerMonitoringBatch {
            let index   = lastIndex + i
            let minutes = index * blockSize
            guard minutes <= maxMinutes else { break }

            let event: DeviceActivityEvent
            if #available(iOS 17.4, *) {
                if useAllActivity {
                    event = DeviceActivityEvent(
                        threshold: DateComponents(minute: minutes),
                        includesPastActivity: AppConstants.includesPastActivity
                    )
                } else {
                    guard let selection else { continue }
                    event = DeviceActivityEvent(
                        applications: selection.applicationTokens,
                        categories:   selection.categoryTokens,
                        webDomains:   selection.webDomainTokens,
                        threshold:    DateComponents(minute: minutes),
                        includesPastActivity: AppConstants.includesPastActivity
                    )
                }
            } else {
                if useAllActivity {
                    event = DeviceActivityEvent(
                        threshold: DateComponents(minute: minutes)
                    )
                } else {
                    guard let selection else { continue }
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
            print(" No valid events to register — already at the 24-hour ceiling")
            return
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd:   DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        let center = DeviceActivityCenter()
        center.stopMonitoring()

        // Stamp when monitoring was last started (debug visibility).
        sharedDefaults?.set(Date(), forKey: AppConstants.Keys.monitoringSetupTimestamp)

        do {
            try center.startMonitoring(DeviceActivityName("dailyTracking"), during: schedule, events: events)
            print(" Monitoring restarted from block_\(lastIndex + 1) with \(events.count) events")
        } catch {
            print(" Failed to restart monitoring: \(error)")
        }
    }
}
