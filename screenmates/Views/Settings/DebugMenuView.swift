import SwiftUI
import DeviceActivity
import FamilyControls
import Combine

// Simple debug screen for testing — just shows the two things you care about:
//  1. Is everyone connected to the same group?
//  2. Is CloudKit actually receiving updates?
struct DebugMenuView: View {
    @ObservedObject var cloudManager = CloudKitManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var isResetting = false
    @State private var isResettingToBlockZero = false
    @State private var isRestarting = false
    @State private var monitoringActive = false   // whether "dailyTracking" is currently registered

    private let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)

    private func refreshMonitoringStatus() {
        let activities = DeviceActivityCenter().activities
        monitoringActive = activities.contains(DeviceActivityName("dailyTracking"))
    }

    // Last time the extension successfully uploaded to CloudKit
    private var lastUploadDate: Date? {
        sharedDefaults?.object(forKey: "LastExtensionCloudUploadAttempt") as? Date
    }
    private var lastUploadSucceeded: Bool? {
        guard sharedDefaults?.object(forKey: "LastExtensionCloudUploadSuccess") != nil else { return nil }
        return sharedDefaults?.bool(forKey: "LastExtensionCloudUploadSuccess")
    }
    private var lastUploadError: String? {
        sharedDefaults?.string(forKey: "LastExtensionCloudUploadError")
    }

    // Last time the extension detected a screen time threshold
    private var lastThresholdDate: Date? {
        sharedDefaults?.object(forKey: "LastExtensionThresholdDate") as? Date
    }
    private var lastThresholdEvent: String? {
        sharedDefaults?.string(forKey: "LastExtensionThresholdEvent")
    }

    // Earliest possible confirmation the extension process launched — written before any guard/return.
    // If this is nil after using a tracked app, the extension is NOT being woken by iOS at all.
    // If this is set but "Extension fired" is still "Not yet", the extension is launching but
    // failing somewhere in the threshold-processing logic (see console logs).
    private var lastExtensionWakeDate: Date? {
        sharedDefaults?.object(forKey: "LastExtensionWakeDate") as? Date
    }
    private var lastExtensionWakeEvent: String? {
        sharedDefaults?.string(forKey: "LastExtensionWakeEvent")
    }

    // When was monitoring last configured (onboarding "Save & Continue" or "Restart Monitoring")?
    private var monitoringSetupDate: Date? {
        sharedDefaults?.object(forKey: AppConstants.Keys.monitoringSetupTimestamp) as? Date
    }

    var body: some View {
        NavigationView {
            List {

                // WHO'S IN THE GROUP
                // Shows everyone connected so you can confirm all test devices joined correctly
                Section("Group Members (\(cloudManager.groupMembers.count))") {
                    if cloudManager.myGroupID.isEmpty {
                        Text("Not in a group yet")
                            .foregroundColor(.red)
                    } else {
                        LabeledContent("Group ID", value: cloudManager.myGroupID)

                        if cloudManager.groupMembers.isEmpty {
                            Text("No members found in CloudKit — tap Force Refresh")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            // Show each person with their current block count so you can
                            // verify the right data is coming through
                            ForEach(cloudManager.groupMembers) { member in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(member.userID == cloudManager.myID ? "\(member.displayName) (you)" : member.displayName)
                                            .font(.body)
                                        Text("updated \(DateHelpers.relativeTime(from: member.lastUpdate))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text("\(member.minutesUsed) min")
                                        .bold()
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }

                // IS DATA REACHING CLOUDKIT
                // Shows whether the extension is firing and whether uploads are succeeding
                Section("CloudKit Sync Status") {

                    // Family Controls authorization status — if this isn't "Approved",
                    // startMonitoring() may silently register but never deliver callbacks.
                    HStack {
                        Text("FC auth status")
                        Spacer()
                        let status = AuthorizationCenter.shared.authorizationStatus
                        switch status {
                        case .approved:
                            Text("Approved ✅").foregroundColor(.green)
                        case .denied:
                            Text("DENIED ❌").foregroundColor(.red)
                        case .notDetermined:
                            Text("Not determined ⚠️").foregroundColor(.orange)
                        @unknown default:
                            Text("Unknown (\(String(describing: status)))").foregroundColor(.orange)
                        }
                    }

                    // Is DeviceActivity monitoring currently active?
                    // If this says NO, the OS killed the session — tap Restart Monitoring.
                    HStack {
                        Text("Monitoring active")
                        Spacer()
                        if monitoringActive {
                            Text("Yes ✅")
                                .foregroundColor(.green)
                        } else {
                            Text("No ⚠️ — tap Restart Monitoring")
                                .foregroundColor(.orange)
                        }
                    }

                    // When was monitoring last set up?
                    if let d = monitoringSetupDate {
                        HStack {
                            Text("Last setup")
                            Spacer()
                            Text(DateHelpers.relativeTime(from: d))
                                .foregroundColor(.secondary)
                        }
                    }

                    // What is tracked? Shows how many apps/categories/domains are in the saved selection.
                    // If ALL are 0, monitoring is active but watching nothing — go through onboarding again.
                    let stats = MonitoringManager.shared.savedSelectionStats
                    HStack {
                        Text("Apps selected")
                        Spacer()
                        if let s = stats {
                            let total = s.apps + s.categories + s.domains
                            Text("\(s.apps) apps · \(s.categories) cats · \(s.domains) domains")
                                .font(.caption)
                                .foregroundColor(total == 0 ? .red : .secondary)
                        } else {
                            Text("None saved ⚠️")
                                .foregroundColor(.red)
                        }
                    }

                    HStack {
                        Text("Tracking profile")
                        Spacer()
                        Text("\(AppConstants.currentBlockSize) min/block · \(AppConstants.eventsPerMonitoringBatch) events/batch · \(AppConstants.maxTrackableBlocksPerDay) max blocks/day")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Did the extension process launch at all?
                    // Written BEFORE any guard/return in eventDidReachThreshold.
                    // If this is "Never" after using a tracked app, iOS is not waking the extension.
                    if let d = lastExtensionWakeDate {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Extension woke")
                                Spacer()
                                Text(DateHelpers.relativeTime(from: d))
                                    .foregroundColor(.green)
                            }
                            if let e = lastExtensionWakeEvent {
                                Text(e).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    } else {
                        HStack {
                            Text("Extension woke")
                            Spacer()
                            Text("Never — use a tracked app")
                                .foregroundColor(.orange)
                        }
                    }

                    // Did the extension detect screen time?
                    if let d = lastThresholdDate {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Extension threshold")
                                Spacer()
                                Text(DateHelpers.relativeTime(from: d))
                                    .foregroundColor(.green)
                            }
                            if let e = lastThresholdEvent {
                                Text(e).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    } else {
                        HStack {
                            Text("Extension threshold")
                            Spacer()
                            Text("Not yet — use a tracked app")
                                .foregroundColor(.orange)
                        }
                    }

                    // Did the upload reach CloudKit?
                    if let d = lastUploadDate {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Last upload")
                                Spacer()
                                Text(DateHelpers.relativeTime(from: d))
                                    .foregroundColor(.secondary)
                            }
                            if let success = lastUploadSucceeded {
                                Text(success ? "✅ Reached CloudKit" : "❌ Failed")
                                    .font(.caption)
                                    .foregroundColor(success ? .green : .red)
                            }
                            if let err = lastUploadError, !err.isEmpty {
                                Text(err)
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        HStack {
                            Text("Upload status")
                            Spacer()
                            Text("No uploads yet")
                                .foregroundColor(.secondary)
                        }
                    }

                    // Your current local block count (what the extension has tracked)
                    HStack {
                        Text("Your local blocks")
                        Spacer()
                        Text("\(cloudManager.currentBlocksUsed) blocks (\(cloudManager.currentBlocksUsed * AppConstants.currentBlockSize) min)")
                            .foregroundColor(.secondary)
                    }

                    // Last threshold index the extension processed.
                    // HIGH + 0 blocks = duplicate-blocking (tap Reset My Count to 0).
                    // 0 after a reset = correct/expected.
                    HStack {
                        Text("Last threshold index")
                        Spacer()
                        let idx = sharedDefaults?.integer(forKey: "LastThresholdIndex") ?? 0
                        let blocks = cloudManager.currentBlocksUsed
                        let isStuck = idx > 50 && blocks == 0  // high index, 0 blocks = bad state
                        Text("\(idx)")
                            .monospacedDigit()
                            .foregroundColor(isStuck ? .orange : .secondary)
                    }
                }

                Section("Actions") {
                    Button {
                        cloudManager.forceSyncNow()
                    } label: {
                        Label("Force Refresh Now", systemImage: "arrow.triangle.2.circlepath")
                    }

                    // Re-registers monitoring events starting after the last threshold that fired.
                    // Use this when the current event batch is exhausted and the extension goes silent.
                    Button {
                        isRestarting = true
                        DispatchQueue.global().async {
                            MonitoringManager.shared.restartMonitoring()
                            DispatchQueue.main.async { isRestarting = false }
                        }
                    } label: {
                        if isRestarting {
                            Label("Restarting…", systemImage: "hourglass")
                        } else {
                            Label("Restart Monitoring", systemImage: "play.circle")
                        }
                    }
                    .disabled(isRestarting)

                    // Sends the app back to onboarding so you can re-select apps and re-register
                    // DeviceActivity monitoring. Use this after a fresh build wipes the registration.
                    // Your username and group ID are preserved — just pick apps and tap Save & Continue.
                    Button(role: .destructive) {
                        cloudManager.isSetupDone = false
                    } label: {
                        Label("Re-run App Setup", systemImage: "arrow.uturn.backward")
                    }

                    // Zeros your local block count and immediately uploads 0 to CloudKit.
                    // Use this before a test run to clear yesterday's leftover data.
                    Button(role: .destructive) {
                        isResetting = true
                        cloudManager.resetMyCountToZero {
                            isResetting = false
                        }
                    } label: {
                        if isResetting {
                            Label("Resetting…", systemImage: "hourglass")
                        } else {
                            Label("Reset My Count to 0", systemImage: "arrow.counterclockwise")
                        }
                    }
                    .disabled(isResetting)

                    if AppConstants.isTestMode {
                        // Test-only hard reset:
                        // 1) push local/CloudKit count to 0
                        // 2) re-register monitoring from block_1 for a fresh run.
                        Button(role: .destructive) {
                            isResettingToBlockZero = true
                            cloudManager.resetMyCountToZero {
                                DispatchQueue.global().async {
                                    MonitoringManager.shared.restartMonitoring()
                                    DispatchQueue.main.async {
                                        isResettingToBlockZero = false
                                        refreshMonitoringStatus()
                                    }
                                }
                            }
                        } label: {
                            if isResettingToBlockZero {
                                Label("Resetting blocks…", systemImage: "hourglass")
                            } else {
                                Label("Reset to Block 0 (Test)", systemImage: "gobackward")
                            }
                        }
                        .disabled(isResettingToBlockZero)
                    }
                }
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                refreshMonitoringStatus()
            }
            // Refresh monitoring status every 5 seconds while the debug menu is open
            .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
                refreshMonitoringStatus()
                // Also force a UI refresh so "Your local blocks" stays live
                cloudManager.objectWillChange.send()
            }
        }
    }
}
