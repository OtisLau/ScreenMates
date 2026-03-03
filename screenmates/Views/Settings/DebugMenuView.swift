import SwiftUI
import UIKit

// Developer debug screen — useful for checking whether the extension is firing,
// CloudKit is syncing, and background tasks are running.
struct DebugMenuView: View {
    @StateObject var cloudManager = CloudKitManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var showingSyncSuccess = false
    @State private var showingResetSuccess = false

    private let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)

    // Read values directly from App Group storage so we can see what the extension sees
    private var currentBlocks: Int {
        sharedDefaults?.integer(forKey: AppConstants.Keys.dailyBlocksUsed) ?? 0
    }
    private var lastBlockDate: Date? {
        sharedDefaults?.object(forKey: AppConstants.Keys.lastBlockDate) as? Date
    }
    private var lastThresholdDate: Date? {
        sharedDefaults?.object(forKey: "LastExtensionThresholdDate") as? Date
    }
    private var lastThresholdEvent: String? {
        sharedDefaults?.string(forKey: "LastExtensionThresholdEvent")
    }
    private var lastUploadAttempt: Date? {
        sharedDefaults?.object(forKey: "LastExtensionCloudUploadAttempt") as? Date
    }
    private var lastUploadSuccess: Bool? {
        guard sharedDefaults?.object(forKey: "LastExtensionCloudUploadSuccess") != nil else { return nil }
        return sharedDefaults?.bool(forKey: "LastExtensionCloudUploadSuccess")
    }
    private var lastUploadError: String? {
        sharedDefaults?.string(forKey: "LastExtensionCloudUploadError")
    }

    var body: some View {
        NavigationView {
            List {

                Section("Build Config") {
                    row("Test Mode", value: AppConstants.isTestMode ? "ON" : "OFF",
                        color: AppConstants.isTestMode ? .orange : .green)
                    row("Block Size", value: "\(AppConstants.currentBlockSize) min")
                    row("Upload Throttle", value: "\(Int(AppConstants.uploadThrottleSeconds))s")
                }

                Section("Local Data") {
                    row("Daily Blocks Used", value: "\(currentBlocks)")
                    if let d = lastBlockDate {
                        row("Last Block Date", value: d.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                Section("Your Identity") {
                    row("User ID", value: cloudManager.myID, small: true)
                    row("Name", value: cloudManager.myDisplayName.isEmpty ? "NOT SET" : cloudManager.myDisplayName,
                        color: cloudManager.myDisplayName.isEmpty ? .red : nil)
                    row("Group ID", value: cloudManager.myGroupID.isEmpty ? "None" : cloudManager.myGroupID)
                    row("Group Members", value: "\(cloudManager.groupMembers.count)")
                }

                Section("Extension Activity") {
                    // Shows whether the ScreenTimeMonitor extension is actually firing
                    if let d = lastThresholdDate {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last threshold: \(DateHelpers.relativeTime(from: d))")
                                .font(.caption)
                            if let e = lastThresholdEvent {
                                Text(e).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("No threshold events yet — use a selected app for 1+ min")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let d = lastUploadAttempt {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last upload attempt: \(DateHelpers.relativeTime(from: d))")
                                .font(.caption)
                            if let success = lastUploadSuccess {
                                Text(success ? "✅ Succeeded" : "❌ Failed")
                                    .font(.caption2)
                                    .foregroundColor(success ? .green : .red)
                            }
                            if let err = lastUploadError, !err.isEmpty {
                                Text(err).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("No upload attempts yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Background Sync") {
                    let status = UIApplication.shared.backgroundRefreshStatus
                    row("Background Refresh",
                        value: status == .available ? "Available" : status == .denied ? "Denied" : "Restricted",
                        color: status == .available ? .green : .red)

                    if let d = sharedDefaults?.object(forKey: AppConstants.Keys.lastBackgroundSync) as? Date {
                        row("Last BG Sync", value: DateHelpers.relativeTime(from: d))
                    } else {
                        Text("No background syncs recorded yet")
                            .font(.caption).foregroundColor(.secondary)
                    }

                    if let history = sharedDefaults?.array(forKey: AppConstants.Keys.backgroundSyncHistory) as? [[String: Any]] {
                        NavigationLink("Sync History (\(history.count))") {
                            BackgroundSyncHistoryView(history: history)
                        }
                    }
                }

                Section("Actions") {
                    Button { manualSync() } label: {
                        Label("Force Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button { simulateMidnightReset() } label: {
                        Label("Simulate Midnight Reset", systemImage: "moon.stars")
                    }
                    NavigationLink("Diagnostics") { DiagnosticView() }
                    Button(role: .destructive) { clearLocalData() } label: {
                        Label("Clear Local Data", systemImage: "trash")
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
            .alert("Sync triggered", isPresented: $showingSyncSuccess) {
                Button("OK") {}
            }
            .alert("Reset complete", isPresented: $showingResetSuccess) {
                Button("OK") {}
            }
        }
    }

    // Helper to build a consistent label/value row
    @ViewBuilder
    private func row(_ label: String, value: String, color: Color? = nil, small: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(small ? .caption : .body)
                .foregroundColor(color ?? .secondary)
        }
    }

    private func manualSync() {
        cloudManager.forceSyncNow()
        showingSyncSuccess = true
    }

    private func simulateMidnightReset() {
        sharedDefaults?.set(0, forKey: AppConstants.Keys.dailyBlocksUsed)
        sharedDefaults?.set(Date.distantPast, forKey: AppConstants.Keys.lastBlockDate)
        showingResetSuccess = true
    }

    private func clearLocalData() {
        sharedDefaults?.removeObject(forKey: AppConstants.Keys.dailyBlocksUsed)
        sharedDefaults?.removeObject(forKey: AppConstants.Keys.lastBlockDate)
    }
}
