import SwiftUI

private struct UsernameButtonStyle: ViewModifier {
    let filled: Bool
    func body(content: Content) -> some View {
        if filled {
            content.glassProminentButtonStyle()
        } else {
            content.glassButtonStyle()
        }
    }
}

// Username setup — shown once after onboarding completes.
struct UsernameSetupView: View {
    @ObservedObject var cloudManager = CloudKitManager.shared

    @State private var username = ""
    @State private var isLoading = false
    @State private var showError = false

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 28) {
                    // Icon
                    Image(systemName: "person.fill")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Color.primary.opacity(0.7))

                    VStack(spacing: 8) {
                        Text("What's your name?")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("This is how you'll appear to your friends")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }

                    // Input field
                    VStack(spacing: 6) {
                        TextField("", text: $username, prompt: Text("Your name").foregroundColor(.secondary))
                            .font(.system(size: 22, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .autocapitalization(.words)
                            .disableAutocorrection(true)
                            .focused($isFocused)
                            .padding(.vertical, 18)
                            .glassCard(cornerRadius: AppTheme.cornerRadiusLarge)
                            .padding(.horizontal, 24)

                        Text("\(username.count)/20")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Continue button
                Button {
                    saveUsername()
                } label: {
                    HStack(spacing: 8) {
                        if isLoading {
                            SpinnerIcon()
                            Text("Saving…")
                                .fontWeight(.semibold)
                        } else {
                            Text("Continue")
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .modifier(UsernameButtonStyle(filled: !username.isEmpty))
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
                .disabled(username.isEmpty || isLoading)
            }
        }
        .onAppear { isFocused = true }
        .alert("Invalid Name", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text("Please enter a name between 1 and 20 characters.")
        }
    }

    private func saveUsername() {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed.count <= 20 else {
            showError = true
            return
        }

        isLoading = true
        cloudManager.myDisplayName = trimmed
        cloudManager.usernameSet = true
        cloudManager.updateMyProfile {
            isLoading = false
        }
    }
}
