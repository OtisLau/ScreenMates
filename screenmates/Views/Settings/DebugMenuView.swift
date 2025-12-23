import SwiftUI
import UIKit
import BackgroundTasks

/// Debug menu for testing and troubleshooting
struct DebugMenuView: View {
    @StateObject var cloudManager = CloudKitManager.shared
    @StateObject var streakManager = StreakManager.shared
    @StateObject var notificationManager = NotificationManager.shared
    
    @Environment(\.dismiss) var dismiss
    
    @State private var showingSyncSuccess = false
    @State private var showingResetSuccess = false
    
    private let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)

    private var appGroupContainerStatus: String {
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupSuite)
        return url == nil ? "Unavailable" : "OK"
    }

    private var appGroupContainerStatusColor: Color {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupSuite) == nil ? .red : .green
    }
    
    private var currentBlocks: Int {
        sharedDefaults?.integer(forKey: AppConstants.Keys.dailyBlocksUsed) ?? 0
    }
    
    private var lastBlockDate: Date? {
        sharedDefaults?.object(forKey: AppConstants.Keys.lastBlockDate) as? Date
    }

    private var lastExtensionUploadAttempt: Date? {
        sharedDefaults?.object(forKey: "LastExtensionCloudUploadAttempt") as? Date
    }

    private var lastExtensionUploadSuccess: Bool? {
        guard let sharedDefaults else { return nil }
        if sharedDefaults.object(forKey: "LastExtensionCloudUploadSuccess") == nil { return nil }
        return sharedDefaults.bool(forKey: "LastExtensionCloudUploadSuccess")
    }

    private var lastExtensionUploadError: String? {
        sharedDefaults?.string(forKey: "LastExtensionCloudUploadError")
    }

    private var lastExtensionThresholdDate: Date? {
        sharedDefaults?.object(forKey: "LastExtensionThresholdDate") as? Date
    }

    private var lastExtensionThresholdEvent: String? {
        sharedDefaults?.string(forKey: "LastExtensionThresholdEvent")
    }

    private var lastExtensionThresholdActivity: String? {
        sharedDefaults?.string(forKey: "LastExtensionThresholdActivity")
    }

    private var lastExtensionBlocksAtThreshold: Int? {
        guard let sharedDefaults else { return nil }
        if sharedDefaults.object(forKey: "LastExtensionBlocksAtThreshold") == nil { return nil }
        return sharedDefaults.integer(forKey: "LastExtensionBlocksAtThreshold")
    }

    private var mirroredGoal: Int? {
        guard let sharedDefaults else { return nil }
        if sharedDefaults.object(forKey: AppConstants.Keys.sharedDailyGoalBlocks) == nil { return nil }
        return sharedDefaults.integer(forKey: AppConstants.Keys.sharedDailyGoalBlocks)
    }
    
    var body: some View {
        NavigationView {
            List {
                // Mode info
                Section("Mode") {
                    HStack {
                        Text("Test Mode")
                        Spacer()
                        Text(AppConstants.isTestMode ? "Enabled" : "Disabled")
                            .foregroundColor(AppConstants.isTestMode ? .orange : .green)
                    }
                    
                    HStack {
                        Text("Block Size")
                        Spacer()
                        Text("\(AppConstants.currentBlockSize) minutes")
                            .foregroundColor(.secondary)
                    }
                }
                
                // UserDefaults data
                Section("Local Data (UserDefaults)") {
                    HStack {
                        Text("Daily Blocks Used")
                        Spacer()
                        Text("\(currentBlocks)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Current Streak")
                        Spacer()
                        Text("\(streakManager.currentStreak)")
                            .foregroundColor(.secondary)
                    }
                    
                    if let lastDate = lastBlockDate {
                        HStack {
                            Text("Last Block Date")
                            Spacer()
                            Text(lastDate.formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }

                Section("App Group") {
                    HStack {
                        Text("Container")
                        Spacer()
                        Text(appGroupContainerStatus)
                            .foregroundColor(appGroupContainerStatusColor)
                    }

                    if let mirroredGoal {
                        HStack {
                            Text("Mirrored Goal")
                            Spacer()
                            Text("\(mirroredGoal) blocks")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Mirrored Goal: not set yet (open dashboard once or change goal)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // CloudKit data
                Section("CloudKit Data") {
                    HStack {
                        Text("User ID")
                        Spacer()
                        Text(cloudManager.myID)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    HStack {
                        Text("Display Name")
                        Spacer()
                        Text(cloudManager.myDisplayName.isEmpty ? "NOT SET" : cloudManager.myDisplayName)
                            .foregroundColor(cloudManager.myDisplayName.isEmpty ? .red : .secondary)
                            .font(.caption)
                    }
                    
                    HStack {
                        Text("Group ID")
                        Spacer()
                        Text(cloudManager.myGroupID)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    HStack {
                        Text("Group Members")
                        Spacer()
                        Text("\(cloudManager.groupMembers.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    if let lastSync = cloudManager.lastSyncTime {
                        HStack {
                            Text("Last Sync")
                            Spacer()
                            Text(DateHelpers.relativeTime(from: lastSync))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Actions
                Section("Actions") {
                    NavigationLink {
                        DiagnosticView()
                    } label: {
                        Label("Run Diagnostics", systemImage: "stethoscope")
                            .foregroundColor(.purple)
                    }
                    
                    Button {
                        manualSync()
                    } label: {
                        Label("Force Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    
                    Button {
                        simulateMidnightReset()
                    } label: {
                        Label("Simulate Midnight Reset", systemImage: "moon.stars")
                    }
                    
                    Button {
                        sendTestNotification()
                    } label: {
                        Label("Send Test Notification", systemImage: "bell")
                    }
                    
                    Button(role: .destructive) {
                        clearLocalData()
                    } label: {
                        Label("Clear Local Data", systemImage: "trash")
                    }
                }
                
                // Notification info
                Section("Notifications") {
                    HStack {
                        Text("Authorized")
                        Spacer()
                        Text(notificationManager.isAuthorized ? "Yes" : "No")
                            .foregroundColor(notificationManager.isAuthorized ? .green : .red)
                    }
                    
                    HStack {
                        Text("Enabled in App")
                        Spacer()
                        Text(notificationManager.notificationsEnabled ? "Yes" : "No")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Background sync info
                Section("Background Sync") {
                    // System-level background refresh availability (if this is Off, BGTasks will never run)
                    HStack {
                        Text("Background Refresh")
                        Spacer()
                        Text(backgroundRefreshStatusText)
                            .foregroundColor(backgroundRefreshStatusColor)
                            .font(.caption)
                    }

                    if let lastBgSync = sharedDefaults?.object(forKey: AppConstants.Keys.lastBackgroundSync) as? Date {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last Background Sync")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(lastBgSync.formatted(date: .abbreviated, time: .shortened))
                                .font(.body)
                            Text(DateHelpers.relativeTime(from: lastBgSync))
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    } else {
                        Text("No background syncs yet")
                            .foregroundColor(.secondary)
                    }
                    
                    if let history = sharedDefaults?.array(forKey: AppConstants.Keys.backgroundSyncHistory) as? [[String: Any]] {
                        NavigationLink {
                            BackgroundSyncHistoryView(history: history)
                        } label: {
                            HStack {
                                Text("Sync History")
                                Spacer()
                                Text("\(history.count) events")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Extension sync info (this is what increments blocks)
                Section("Extension Cloud Upload") {
                    if let d = lastExtensionThresholdDate {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last Threshold Event")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(d.formatted(date: .abbreviated, time: .shortened))
                                .font(.body)
                            Text(DateHelpers.relativeTime(from: d))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            if let e = lastExtensionThresholdEvent {
                                Text("Event: \(e)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if let a = lastExtensionThresholdActivity {
                                Text("Activity: \(a)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if let b = lastExtensionBlocksAtThreshold {
                                Text("Blocks at event: \(b)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("No threshold events yet (extension may not be firing)")
                            .foregroundColor(.secondary)
                    }

                    if let attempt = lastExtensionUploadAttempt {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last Upload Attempt")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(attempt.formatted(date: .abbreviated, time: .shortened))
                                .font(.body)
                            Text(DateHelpers.relativeTime(from: attempt))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("No upload attempts yet")
                            .foregroundColor(.secondary)
                    }

                    if let success = lastExtensionUploadSuccess {
                        HStack {
                            Text("Last Result")
                            Spacer()
                            Text(success ? "✅ Success" : "❌ Failed")
                                .foregroundColor(success ? .green : .red)
                        }
                    }

                    if let err = lastExtensionUploadError, !err.isEmpty {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle("Debug Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Success", isPresented: $showingSyncSuccess) {
                Button("OK") { }
            } message: {
                Text("Manual sync completed!")
            }
            .alert("Reset Complete", isPresented: $showingResetSuccess) {
                Button("OK") { }
            } message: {
                Text("Daily blocks reset to 0")
            }
        }
    }
    
    private func manualSync() {
        cloudManager.forceSyncNow()
        showingSyncSuccess = true
    }
    
    private func simulateMidnightReset() {
        sharedDefaults?.set(0, forKey: AppConstants.Keys.dailyBlocksUsed)
        sharedDefaults?.set(Date(), forKey: AppConstants.Keys.lastBlockDate)
        showingResetSuccess = true
    }
    
    private func sendTestNotification() {
        notificationManager.sendTestNotification()
    }
    
    private func clearLocalData() {
        sharedDefaults?.removeObject(forKey: AppConstants.Keys.dailyBlocksUsed)
        sharedDefaults?.removeObject(forKey: AppConstants.Keys.lastBlockDate)
        sharedDefaults?.removeObject(forKey: AppConstants.Keys.currentStreak)
        sharedDefaults?.removeObject(forKey: AppConstants.Keys.lastCheckDate)
    }

    private var backgroundRefreshStatusText: String {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: return "Available"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }

    private var backgroundRefreshStatusColor: Color {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: return .green
        case .denied, .restricted: return .red
        @unknown default: return .secondary
        }
    }
}
