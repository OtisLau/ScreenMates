import SwiftUI

// Simple debug screen for testing — just shows the two things you care about:
//  1. Is everyone connected to the same group?
//  2. Is CloudKit actually receiving updates?
struct DebugMenuView: View {
    @StateObject var cloudManager = CloudKitManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var isResetting = false
    @State private var isRestarting = false

    private let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)

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

                    // Did the extension detect screen time?
                    if let d = lastThresholdDate {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Extension last fired")
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
                            Text("Extension fired")
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
                }

                Section("Actions") {
                    Button {
                        cloudManager.forceSyncNow()
                    } label: {
                        Label("Force Refresh Now", systemImage: "arrow.triangle.2.circlepath")
                    }

                    // Re-registers monitoring events starting after the last threshold that fired.
                    // Use this when the daily event limit is exhausted and the extension goes silent.
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
                }
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
