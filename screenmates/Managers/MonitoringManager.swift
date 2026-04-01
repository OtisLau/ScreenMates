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

    // Re-register monitoring with a completely fresh batch of events starting from block_1.
    // Always wipes the threshold index so there is no stale data that could produce a
    // huge delta if iOS replays or delivers out-of-order callbacks.
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

        // Always reset the threshold index so the extension starts counting from block_1.
        // DailyBlocksUsed is preserved — we only wipe the indices to prevent stale deltas.
        sharedDefaults?.set(0, forKey: AppConstants.Keys.lastThresholdIndex)
        sharedDefaults?.set(0, forKey: AppConstants.Keys.lastAutoBatchRolloverIndex)

        let blockSize  = AppConstants.currentBlockSize
        let maxMinutes = AppConstants.maxThresholdMinuteOfDay

        // Build a fresh batch of events always starting from block_1
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
            let index   = i
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

        // Stamp when monitoring was last started and snapshot the current block count
        // so the extension can rate-limit catch-up thresholds that fire immediately
        // after restart (iOS replays all thresholds up to today's accumulated activity).
        sharedDefaults?.set(Date(), forKey: AppConstants.Keys.monitoringSetupTimestamp)
        sharedDefaults?.set(sharedDefaults?.integer(forKey: AppConstants.Keys.dailyBlocksUsed) ?? 0,
                            forKey: "BlocksAtMonitoringSetup")

        do {
            try center.startMonitoring(DeviceActivityName("dailyTracking"), during: schedule, events: events)
            print(" Monitoring restarted from block_1 with \(events.count) events")
        } catch {
            print(" Failed to restart monitoring: \(error)")
        }
    }
}
