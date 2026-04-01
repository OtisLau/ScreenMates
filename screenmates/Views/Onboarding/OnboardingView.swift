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

    @State private var permissionGranted = false
    @State private var notificationGranted = false
    @State private var isStartingMonitoring = false
    @State private var isRequestingPermission = false
    @State private var isRequestingNotifications = false
    @State private var showAuthError = false
    @State private var authErrorMessage = ""

    let center = AuthorizationCenter.shared

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                Spacer()

                // Hero area
                VStack(spacing: 14) {
                    Image(systemName: "iphone.and.arrow.right.inward")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(Color.primary.opacity(0.7))

                    Text("ScreenMates")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Track your screen time with friends.\nSpend less time on your phone, together.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer()

                // Step cards
                VStack(spacing: 10) {
                    stepCard(
                        number: 1,
                        title: "Allow Screen Time Access",
                        subtitle: "Required to track daily usage",
                        icon: "lock.shield.fill",
                        done: permissionGranted,
                        isLoading: isRequestingPermission,
                        action: requestPermissions
                    )

                    stepCard(
                        number: 2,
                        title: "Enable Notifications",
                        subtitle: "Get notified about your group's screen time",
                        icon: "bell.badge.fill",
                        done: notificationGranted,
                        isLoading: isRequestingNotifications,
                        action: requestNotifications
                    )

                    // Continue button
                    Button {
                        startMonitoring()
                    } label: {
                        HStack(spacing: 8) {
                            if isStartingMonitoring {
                                SpinnerIcon()
                                Text("Getting Started…")
                                    .fontWeight(.semibold)
                            } else {
                                Text("Get Started")
                                    .fontWeight(.semibold)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
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
        }
        .onAppear {
            permissionGranted = (center.authorizationStatus == .approved)
            Task {
                notificationGranted = await NotificationManager.shared.isAuthorized
            }
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
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Icon in a rounded square
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 36, height: 36)
                    if isLoading {
                        SpinnerIcon()
                    } else {
                        Image(systemName: done ? "checkmark" : icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.7))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !isLoading {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .glassCard(cornerRadius: AppTheme.cornerRadiusLarge)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || done)
    }

    private func requestNotifications() {
        isRequestingNotifications = true
        Task {
            let granted = await NotificationManager.shared.requestPermission()
            await MainActor.run {
                notificationGranted = granted
                isRequestingNotifications = false
                if granted {
                    UserDefaults.standard.set(true, forKey: "notificationsEnabled")
                }
            }
        }
    }

    private func requestPermissions() {
        isRequestingPermission = true
        Task {
            do {
                try await center.requestAuthorization(for: .individual)
                await MainActor.run {
                    permissionGranted = true
                    isRequestingPermission = false
                }
            } catch {
                await MainActor.run {
                    isRequestingPermission = false
                    if center.authorizationStatus == .approved {
                        permissionGranted = true
                    } else {
                        authErrorMessage = "Screen Time authorization failed: \(error.localizedDescription)\n\nIf you previously granted access, try force-quitting and reopening the app."
                        showAuthError = true
                    }
                }
            }
        }
    }

    private func startMonitoring() {
        isStartingMonitoring = true

        Task { @MainActor in
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

        for i in 1...checkpoints {
            let eventName = DeviceActivityEvent.Name("block_\(i)")
            let minutes = min(i * blockSize, maxMinutesInDay)
            let event: DeviceActivityEvent
            if #available(iOS 17.4, *) {
                if AppConstants.monitorAllActivity {
                    event = DeviceActivityEvent(
                        threshold: DateComponents(minute: minutes),
                        includesPastActivity: AppConstants.includesPastActivity
                    )
                } else {
                    // Selection-based monitoring — saved selection may be nil on first launch,
                    // which is fine: the all-activity fallback above handles that case.
                    event = DeviceActivityEvent(
                        threshold: DateComponents(minute: minutes),
                        includesPastActivity: AppConstants.includesPastActivity
                    )
                }
            } else {
                event = DeviceActivityEvent(threshold: DateComponents(minute: minutes))
            }
            events[eventName] = event
        }

        do {
            deviceActivityCenter.stopMonitoring()
            let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)
            sharedDefaults?.set(Date(), forKey: AppConstants.Keys.monitoringSetupTimestamp)
            sharedDefaults?.set(0, forKey: AppConstants.Keys.lastThresholdIndex)
            sharedDefaults?.set(0, forKey: AppConstants.Keys.lastAutoBatchRolloverIndex)
            try deviceActivityCenter.startMonitoring(
                DeviceActivityName("dailyTracking"),
                during: schedule,
                events: events
            )


            cloudManager.isSetupDone = true
            isStartingMonitoring = false

            Task { @MainActor in
                await CloudKitManager.shared.refreshGroupNow(reason: "setup")
            }
        } catch {
            print("Error starting monitoring: \(error)")
            isStartingMonitoring = false
        }
        } // end Task
    }
}
