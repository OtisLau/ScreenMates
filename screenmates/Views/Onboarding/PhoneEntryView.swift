import SwiftUI

private struct PhoneButtonStyle: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.glassProminentButtonStyle()
        } else {
            content.glassButtonStyle()
        }
    }
}

/// Handles phone number entry and OTP verification in a single view.
/// Toggles between two visual states — phone entry and OTP entry —
/// so there's no navigation stack or sheet to manage.
struct PhoneEntryView: View {
    private enum Step { case phone, otp }

    @State private var step: Step = .phone
    @State private var phoneNumber = ""
    @State private var code = ""
    @State private var pendingE164 = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = "That code didn't work. Please try again."
    @State private var statusMessage = ""

    @FocusState private var isFocused: Bool

    private var phoneIsValid: Bool {
        phoneNumber.filter { $0.isNumber }.count >= 10
    }

    var body: some View {
        ZStack {
            AppBackground()
            if step == .phone {
                phoneContent
            } else {
                otpContent
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: - Phone entry

    private var phoneContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.primary.opacity(0.7))

                VStack(spacing: 8) {
                    Text("What's your number?")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("We'll send a code to verify\nit's really you")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                HStack(spacing: 10) {
                    Text("+1")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField("", text: $phoneNumber,
                              prompt: Text("(555) 867-5309").foregroundColor(.secondary))
                        .font(.system(size: 22, weight: .semibold))
                        .keyboardType(.phonePad)
                        .focused($isFocused)
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 20)
                .glassCard(cornerRadius: AppTheme.cornerRadiusLarge)
                .padding(.horizontal, 24)
            }

            Spacer()

            Button { sendCode() } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        SpinnerIcon()
                        Text("Sending…").fontWeight(.semibold)
                    } else {
                        Text("Send Code").fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .modifier(PhoneButtonStyle(enabled: phoneIsValid))
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
            .disabled(!phoneIsValid || isLoading)
        }
        .onAppear { isFocused = true }
    }

    // MARK: - OTP entry

    private var otpContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                Image(systemName: "ellipsis.message.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.primary.opacity(0.7))

                VStack(spacing: 8) {
                    Text("Check your texts")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Enter the 6-digit code sent to\n\(formattedPhone(pendingE164))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                TextField("", text: $code,
                          prompt: Text("000000").foregroundColor(.secondary))
                    .font(.system(size: 32, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .focused($isFocused)
                    .onChange(of: code) { _, new in
                        let digits = new.filter { $0.isNumber }
                        code = String(digits.prefix(6))
                    }
                    .padding(.vertical, 18)
                    .glassCard(cornerRadius: AppTheme.cornerRadiusLarge)
                    .padding(.horizontal, 24)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button { verifyCode() } label: {
                    HStack(spacing: 8) {
                        if isLoading {
                            SpinnerIcon()
                            Text("Verifying…").fontWeight(.semibold)
                        } else {
                            Text("Verify").fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .modifier(PhoneButtonStyle(enabled: code.count == 6))
                .disabled(code.count < 6 || isLoading)

                Button("Use a different number") {
                    code = ""
                    step = .phone
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .onAppear { isFocused = true }
        .alert("Invalid Code", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Actions

    private func sendCode() {
        guard let e164 = PhoneAuthManager.normalizeToE164(phoneNumber) else { return }
        pendingE164 = e164
        isLoading = true

        if AppConstants.skipOTPVerification {
            isLoading = false
            step = .otp
            return
        }

        Task {
            do {
                try await PhoneAuthProxyClient().startVerification(to: e164)
                await MainActor.run {
                    isLoading = false
                    step = .otp
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func verifyCode() {
        isLoading = true
        statusMessage = ""

        if AppConstants.skipOTPVerification {
            // In bypass mode any 6-digit code is accepted.
            finishVerifiedPhone(providerUserID: "bypass-\(UUID().uuidString.prefix(8))")
            return
        }

        Task {
            do {
                let providerUserID = try await PhoneAuthProxyClient().checkVerification(to: pendingE164, code: code)
                finishVerifiedPhone(providerUserID: providerUserID)
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func finishVerifiedPhone(providerUserID: String) {
        Task {
            let phoneHash = PhoneAuthManager.sha256(pendingE164)
            let restoredAccount: CloudKitManager.RestoredAccount?
            do {
                restoredAccount = try await CloudKitManager.shared.restoreExistingAccount(
                    phoneHash: phoneHash,
                    providerUserID: providerUserID
                )
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "We couldn't check for an existing account. Please try again."
                    showError = true
                }
                return
            }

            if let restoredAccount, !restoredAccount.displayName.isEmpty {
                await MainActor.run {
                    statusMessage = "Welcome back, \(restoredAccount.displayName)"
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }

            await MainActor.run {
                PhoneAuthManager.shared.markPhoneVerified(
                    e164: pendingE164,
                    providerUserID: providerUserID,
                    syncProfile: restoredAccount == nil
                )
                isLoading = false
            }
        }
    }

    // MARK: - Helpers

    private func formattedPhone(_ e164: String) -> String {
        let d = e164.filter { $0.isNumber }
        guard d.count == 11 else { return e164 }
        let area   = d.dropFirst().prefix(3)
        let prefix = d.dropFirst(4).prefix(3)
        let line   = d.dropFirst(7)
        return "+1 (\(area)) \(prefix)-\(line)"
    }
}
