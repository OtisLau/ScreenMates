import SwiftUI
import FamilyControls
import DeviceActivity

/// Initial onboarding for permissions and app selection
struct OnboardingView: View {
    @ObservedObject var cloudManager = CloudKitManager.shared

    @State private var selection = FamilyActivitySelection()
    @State private var isPickerPresented = false
    @State private var permissionGranted = false
    @State private var isStartingMonitoring = false
    @State private var showAuthError = false
    @State private var authErrorMessage = ""
    
    let center = AuthorizationCenter.shared

    private var hasAnySelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Icon
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 60))
                .foregroundColor(.purple)
            
            // Title
            Text("Welcome to ScreenMates")
                .font(.largeTitle)
                .bold()
                .multilineTextAlignment(.center)
            
            // Description
            Text("To start, grant permission. App selection is optional in all-activity mode.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Spacer()
            
            VStack(spacing: 16) {
                // Step 1: Grant Permissions
                Button {
                    requestPermissions()
                } label: {
                    HStack {
                        Text("1. Grant Permissions")
                        Spacer()
                        if permissionGranted {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
                }
                
                // Step 2: Select Apps
                Button {
                    isPickerPresented = true
                } label: {
                    HStack {
                        Text("2. Select Distracting Apps (Optional)")
                        Spacer()
                        if AppConstants.monitorAllActivity || hasAnySelection {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
                }
                
                // Step 3: Continue button
                Button {
                    startMonitoring()
                } label: {
                    if isStartingMonitoring {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("3. Save & Continue")
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .disabled(isStartingMonitoring || !permissionGranted)
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
        .onAppear {
            // If the device is already authorized (e.g. reinstall / previous run),
            // treat that as granted so onboarding doesn't get stuck.
            permissionGranted = (center.authorizationStatus == .approved)
        }
        .alert("Screen Time Permission", isPresented: $showAuthError) {
            Button("OK") {}
        } message: {
            Text(authErrorMessage)
        }
    }
    
    private func requestPermissions() {
        Task {
            // Request FamilyControls
            do {
                try await center.requestAuthorization(for: .individual)
                permissionGranted = true
            } catch {
                // Some devices throw `authorizationConflict` when already approved (or when a previous
                // authorization exists). If status is approved, allow the flow to proceed.
                if center.authorizationStatus == .approved {
                    permissionGranted = true
                } else {
                    print(" Permission error: \(error)")
                    authErrorMessage = "Screen Time authorization failed: \(error.localizedDescription)\n\nIf you previously granted access, try force-quitting the app and reopening. Otherwise, ensure Screen Time is enabled and try again."
                    showAuthError = true
                }
            }
            
        }
    }
    
    private func startMonitoring() {
        isStartingMonitoring = true
        
        let deviceActivityCenter = DeviceActivityCenter()
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        
        // Create threshold events (checkpoints)
        let blockSize = AppConstants.currentBlockSize
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]

        // Keep thresholds within the day and cap this registration to one batch.
        let maxMinutesInDay = AppConstants.maxThresholdMinuteOfDay
        let checkpoints = min(AppConstants.eventsPerMonitoringBatch, AppConstants.maxTrackableBlocksPerDay)

        let useAllActivity =
            AppConstants.monitorAllActivity ||
            (selection.applicationTokens.isEmpty &&
             selection.webDomainTokens.isEmpty &&
             selection.categoryTokens.count >= AppConstants.allCategoryTokenCountForAllActivityFallback)
        if useAllActivity {
            print(" Using all-activity monitoring")
        }
        
        for i in 1...checkpoints {
            let eventName = DeviceActivityEvent.Name("block_\(i)")
            let minutes = min(i * blockSize, maxMinutesInDay)
            let event: DeviceActivityEvent
            if #available(iOS 17.4, *) {
                if useAllActivity {
                    event = DeviceActivityEvent(
                        threshold: DateComponents(minute: minutes),
                        includesPastActivity: AppConstants.includesPastActivity
                    )
                } else {
                    event = DeviceActivityEvent(
                        applications: selection.applicationTokens,
                        categories: selection.categoryTokens,
                        webDomains: selection.webDomainTokens,
                        threshold: DateComponents(minute: minutes),
                        includesPastActivity: AppConstants.includesPastActivity
                    )
                }
            } else {
                if useAllActivity {
                    event = DeviceActivityEvent(
                        threshold: DateComponents(minute: minutes)
                    )
                } else {
                    event = DeviceActivityEvent(
                        applications: selection.applicationTokens,
                        categories: selection.categoryTokens,
                        webDomains: selection.webDomainTokens,
                        threshold: DateComponents(minute: minutes)
                    )
                }
            }
            events[eventName] = event
        }
        
        do {
            deviceActivityCenter.stopMonitoring()

            // Stamp when monitoring was configured so debug views can show last setup time.
            let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)
            sharedDefaults?.set(Date(), forKey: AppConstants.Keys.monitoringSetupTimestamp)
            sharedDefaults?.set(0, forKey: "LastThresholdIndex")
            sharedDefaults?.set(0, forKey: AppConstants.Keys.lastAutoBatchRolloverIndex)
            sharedDefaults?.removeObject(forKey: "LastExtensionCloudUpload")
            sharedDefaults?.removeObject(forKey: "LastExtensionCloudUploadAttempt")

            try deviceActivityCenter.startMonitoring(
                DeviceActivityName("dailyTracking"),
                during: schedule,
                events: events
            )
            print(" Monitoring Started with \(events.count) Checkpoints")

            // Persist the selection so MonitoringManager can restart monitoring later
            // (e.g. from the debug menu after exhausting the current event batch in test mode)
            MonitoringManager.shared.saveSelection(selection)

            // Mark setup as done
            cloudManager.isSetupDone = true
            isStartingMonitoring = false

            // Push initial 0-state right away so leaderboard reflects the new setup quickly.
            Task { @MainActor in
                await CloudKitManager.shared.refreshGroupNow(reason: "setup")
            }
            
        } catch {
            print(" Error starting monitoring: \(error)")
            isStartingMonitoring = false
        }
    }
}
