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
            Text("To start, we need to know which apps you want to track.")
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
                        Text("2. Select Distracting Apps")
                        Spacer()
                        if hasAnySelection {
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
                if hasAnySelection {
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
                    print("❌ Permission error: \(error)")
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

        // Keep thresholds within the day (0:00 → 23:59 = 1439 minutes).
        // Example: 15-min blocks => 96 checkpoints reaches 1440 minutes, so we cap at 1439 for the last event.
        let maxMinutesInDay = (24 * 60) - 1
        let maxEventsForBlockSize = (maxMinutesInDay / blockSize) + 1
        let checkpoints = min(AppConstants.maxDailyCheckpoints, maxEventsForBlockSize)

        let useAllActivityFallback =
            selection.applicationTokens.isEmpty &&
            selection.webDomainTokens.isEmpty &&
            selection.categoryTokens.count >= AppConstants.allCategoryTokenCountForAllActivityFallback
        if useAllActivityFallback {
            print("⚠️ Using all-activity fallback because all categories appear selected")
        }
        
        for i in 1...checkpoints {
            let eventName = DeviceActivityEvent.Name("block_\(i)")
            let minutes = min(i * blockSize, maxMinutesInDay)
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
                        categories: selection.categoryTokens,
                        webDomains: selection.webDomainTokens,
                        threshold: DateComponents(minute: minutes),
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

            // Stamp the current time so the extension can tell the difference between
            // "iOS replay of old accumulated usage" and "new usage after setup."
            // Any threshold callback arriving within 15 seconds of this stamp is a replay
            // and will be skipped — only genuinely new events get counted.
            let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)
            sharedDefaults?.set(Date(), forKey: AppConstants.Keys.monitoringSetupTimestamp)
            sharedDefaults?.set(0, forKey: "LastThresholdIndex")
            sharedDefaults?.removeObject(forKey: "LastExtensionCloudUpload")
            sharedDefaults?.removeObject(forKey: "LastExtensionCloudUploadAttempt")

            try deviceActivityCenter.startMonitoring(
                DeviceActivityName("dailyTracking"),
                during: schedule,
                events: events
            )
            print("✅ Monitoring Started with \(events.count) Checkpoints")

            // Persist the selection so MonitoringManager can restart monitoring later
            // (e.g. from the debug menu after exhausting the daily event limit in test mode)
            MonitoringManager.shared.saveSelection(selection)

            // Mark setup as done
            cloudManager.isSetupDone = true
            isStartingMonitoring = false

            // iOS replays all already-exceeded thresholds within ~15 seconds of startMonitoring().
            // Wait 20 seconds for replay to settle, then upload the baseline so group members
            // see your real current screen time right away — not 0.
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                Task { @MainActor in
                    await CloudKitManager.shared.refreshGroupNow(reason: "setup-baseline")
                }
            }
            
        } catch {
            print("❌ Error starting monitoring: \(error)")
            isStartingMonitoring = false
        }
    }
}
