import SwiftUI
import FamilyControls
import DeviceActivity

// Button style helper for the onboarding continue button
private struct OnboardingContinueButtonStyle: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.glassProminentButtonStyle()
        } else {
            content.glassButtonStyle()
        }
    }
}

// Onboarding — permissions and app selection.
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
        VStack(spacing: 0) {
            Spacer()

            // Hero area
            VStack(spacing: 16) {
                Image(systemName: "iphone.and.arrow.right.inward")
                    .font(.system(size: 52))
                    .foregroundStyle(AppTheme.accent)

                Text("ScreenMates")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Track your screen time with friends.\nSpend less time on your phone, together.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            // Step cards
            VStack(spacing: 10) {
                stepCard(
                    number: 1,
                    title: "Allow Screen Time Access",
                    subtitle: "Required to track daily usage",
                    icon: "hand.raised.fill",
                    done: permissionGranted,
                    action: requestPermissions
                )

                stepCard(
                    number: 2,
                    title: "Select Apps (Optional)",
                    subtitle: AppConstants.monitorAllActivity || hasAnySelection ? "All activity tracked" : "Or track everything automatically",
                    icon: "square.grid.2x2.fill",
                    done: AppConstants.monitorAllActivity || hasAnySelection,
                    action: { isPickerPresented = true }
                )

                // Continue button
                Button {
                    startMonitoring()
                } label: {
                    HStack {
                        if isStartingMonitoring {
                            ProgressView()
                        } else {
                            Text("Get Started")
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .modifier(OnboardingContinueButtonStyle(enabled: permissionGranted))
                .disabled(isStartingMonitoring || !permissionGranted)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 48)
        }
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
        .onAppear {
            permissionGranted = (center.authorizationStatus == .approved)
        }
        .alert("Screen Time Permission", isPresented: $showAuthError) {
            Button("OK") {}
        } message: {
            Text(authErrorMessage)
        }
    }

    // Reusable step card
    private func stepCard(
        number: Int,
        title: String,
        subtitle: String,
        icon: String,
        done: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Step number or checkmark
                ZStack {
                    Circle()
                        .fill(done ? Color(UIColor.systemGreen).opacity(0.2) : Color(UIColor.tertiarySystemFill))
                        .frame(width: 36, height: 36)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(UIColor.systemGreen))
                    } else {
                        Text("\(number)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: done ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(done ? Color(UIColor.systemGreen) : Color.secondary)
            }
            .padding(16)
            .glassCard(cornerRadius: AppTheme.cornerRadiusLarge)
        }
        .buttonStyle(.plain)
    }

    private func requestPermissions() {
        Task {
            do {
                try await center.requestAuthorization(for: .individual)
                permissionGranted = true
            } catch {
                if center.authorizationStatus == .approved {
                    permissionGranted = true
                } else {
                    authErrorMessage = "Screen Time authorization failed: \(error.localizedDescription)\n\nIf you previously granted access, try force-quitting and reopening the app."
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

        let blockSize = AppConstants.currentBlockSize
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        let maxMinutesInDay = AppConstants.maxThresholdMinuteOfDay
        let checkpoints = min(AppConstants.eventsPerMonitoringBatch, AppConstants.maxTrackableBlocksPerDay)

        let useAllActivity =
            AppConstants.monitorAllActivity ||
            (selection.applicationTokens.isEmpty &&
             selection.webDomainTokens.isEmpty &&
             selection.categoryTokens.count >= AppConstants.allCategoryTokenCountForAllActivityFallback)

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
                    event = DeviceActivityEvent(threshold: DateComponents(minute: minutes))
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

            MonitoringManager.shared.saveSelection(selection)
            cloudManager.isSetupDone = true
            isStartingMonitoring = false

            Task { @MainActor in
                await CloudKitManager.shared.refreshGroupNow(reason: "setup")
            }
        } catch {
            print("Error starting monitoring: \(error)")
            isStartingMonitoring = false
        }
    }
}
