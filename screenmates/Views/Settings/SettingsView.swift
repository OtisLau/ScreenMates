import SwiftUI

struct SettingsView: View {
    @ObservedObject private var cloudManager = CloudKitManager.shared
    @ObservedObject private var phoneAuth = PhoneAuthManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingDebugMenu = false
    @State private var showingDeactivateConfirmation = false
    @State private var isDeactivating = false
    @State private var deactivateError: String?

    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @State private var notificationPermissionDenied = false

    @State private var limitHours: Int = 0
    @State private var limitMinutes: Int = 0

    private var limitChanged: Bool {
        limitHours * 60 + limitMinutes != cloudManager.myPersonalGoalMinutes
    }

    private func loadLimit() {
        limitHours   = cloudManager.myPersonalGoalMinutes / 60
        limitMinutes = (cloudManager.myPersonalGoalMinutes % 60 / 5) * 5
    }

    private func saveLimit() {
        cloudManager.updatePersonalGoal(limitHours * 60 + limitMinutes)
    }

    private var limitSummary: String {
        let total = limitHours * 60 + limitMinutes
        if total == 0 { return "no limit" }
        let h = total / 60
        let m = total % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        else if h > 0      { return "\(h)h" }
        else               { return "\(m)m" }
    }

    var body: some View {
        NavigationStack {
            List {
                // Identity
                Section("Identity") {
                    NavigationLink {
                        EditDisplayNameView(displayName: cloudManager.myDisplayName)
                    } label: {
                        settingsRow(
                            icon: "person",
                            label: "Display Name",
                            value: cloudManager.myDisplayName.isEmpty ? "Not set" : cloudManager.myDisplayName
                        )
                    }
                }

                // Find Friends — only shown if contacts permission hasn't been handled yet.
                // Once granted, suggested friends appear in the Friends sheet instead.
                if !phoneAuth.contactsHandled {
                    Section {
                        NavigationLink {
                            ContactsPermissionView()
                        } label: {
                            settingsRow(icon: "person.2", label: "Find Friends", value: "")
                        }
                    } header: {
                        Text("Friends")
                    } footer: {
                        Text("Search your contacts for people already on ScreenMates")
                    }
                }

                // Notifications — only show toggle if permission isn't already granted
                if notificationPermissionDenied {
                    Section("Notifications") {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "bell.slash")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                Text("Enable Notifications in Settings")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                } else if !notificationsEnabled {
                    Section("Notifications") {
                        Toggle(isOn: $notificationsEnabled) {
                            HStack(spacing: 12) {
                                Image(systemName: "bell.badge")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                Text("Notifications")
                            }
                        }
                    }
                }

                // Daily Limit
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Daily Limit")
                            Spacer()
                            Text(limitSummary)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(limitHours == 0 && limitMinutes == 0 ? Color.secondary : Color.primary)
                        }

                        Divider()

                        HStack {
                            Text("Hours")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Stepper("\(limitHours)h", value: $limitHours, in: 0...12)
                                .labelsHidden()
                            Text("\(limitHours)h")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .frame(minWidth: 36, alignment: .trailing)
                        }

                        HStack {
                            Text("Minutes")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Stepper("\(limitMinutes)m", value: $limitMinutes, in: 0...55, step: 5)
                                .labelsHidden()
                            Text("\(limitMinutes)m")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .frame(minWidth: 36, alignment: .trailing)
                        }

                        if limitChanged {
                            Button {
                                saveLimit()
                            } label: {
                                Text("Update")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Limit")
                } footer: {
                    Text("Your personal daily screen-time limit. Friends see their own limit on their device.")
                }

                // Tools (dev only)
                if AppConstants.isTestMode {
                    Section("Tools") {
                        NavigationLink {
                            DiagnosticView()
                        } label: {
                            actionRow(icon: "stethoscope", label: "Diagnostics")
                        }

                        Button {
                            showingDebugMenu = true
                        } label: {
                            actionRow(icon: "wrench.and.screwdriver", label: "Debug Menu")
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    DisclosureGroup {
                        Button(role: .destructive) {
                            showingDeactivateConfirmation = true
                        } label: {
                            if isDeactivating {
                                HStack(spacing: 12) {
                                    ProgressView()
                                    Text("Deactivating Account")
                                }
                            } else {
                                actionRow(icon: "person.crop.circle.badge.xmark", label: "Deactivate Account")
                            }
                        }
                        .disabled(isDeactivating)
                    } label: {
                        actionRow(icon: "ellipsis.circle", label: "Advanced")
                    }
                } footer: {
                    Text("Deactivation removes your profile from ScreenMates and signs you out on this device.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadLimit()
                Task {
                    let authorized = await NotificationManager.shared.isAuthorized
                    await MainActor.run { notificationPermissionDenied = !authorized }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingDebugMenu) {
                DebugMenuView()
            }
            .alert("Deactivate account?", isPresented: $showingDeactivateConfirmation) {
                Button("Deactivate Account", role: .destructive) {
                    deactivateAccount()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your ScreenMates profile and signs you out on this device. You will need to verify your phone number again to continue.")
            }
            .alert("Could Not Deactivate Account", isPresented: Binding(
                get: { deactivateError != nil },
                set: { if !$0 { deactivateError = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(deactivateError ?? "")
            }
        }
    }

    private func deactivateAccount() {
        isDeactivating = true
        Task {
            do {
                try await cloudManager.deactivateAccount()
                await MainActor.run {
                    isDeactivating = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeactivating = false
                    deactivateError = error.localizedDescription
                }
            }
        }
    }

    private func settingsRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func actionRow(icon: String, label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
        }
    }
}

private struct EditDisplayNameView: View {
    @ObservedObject private var cloudManager = CloudKitManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var isSaving = false

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        trimmedDisplayName != cloudManager.myDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isNameValid: Bool {
        !trimmedDisplayName.isEmpty && trimmedDisplayName.count <= 20
    }

    init(displayName: String) {
        _displayName = State(initialValue: displayName)
    }

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $displayName)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
            } header: {
                Text("Display Name")
            } footer: {
                HStack {
                    Text("This is how you'll appear to your friends.")
                    Spacer()
                    Text("\(trimmedDisplayName.count)/20")
                        .foregroundStyle(trimmedDisplayName.count > 20 ? Color.red : Color.secondary)
                }
            }
        }
        .navigationTitle("Edit Name")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving..." : "Save") {
                    saveDisplayName()
                }
                .disabled(!isNameValid || !hasChanges || isSaving)
            }
        }
    }

    private func saveDisplayName() {
        guard isNameValid, hasChanges else { return }

        isSaving = true
        cloudManager.myDisplayName = trimmedDisplayName
        cloudManager.usernameSet = true
        cloudManager.updateMyProfile {
            Task { @MainActor in
                isSaving = false
                dismiss()
                await cloudManager.refreshFriendsNow(reason: "display-name")
            }
        }
    }
}
