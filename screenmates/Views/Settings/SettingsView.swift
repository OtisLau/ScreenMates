import SwiftUI

struct SettingsView: View {
    @ObservedObject private var cloudManager = CloudKitManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingDebugMenu = false
    @State private var codeCopied = false

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
                    settingsRow(
                        icon: "person",
                        label: "Display Name",
                        value: cloudManager.myDisplayName.isEmpty ? "Not set" : cloudManager.myDisplayName
                    )
                    // Friend code — tap to copy
                    Button {
                        UIPasteboard.general.string = cloudManager.myFriendCode
                        codeCopied = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.8))
                            codeCopied = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: "number")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text("Friend Code")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(cloudManager.myFriendCode)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12))
                                .foregroundStyle(codeCopied ? Color(UIColor.systemGreen) : Color(UIColor.tertiaryLabel))
                                .animation(.easeInOut(duration: 0.2), value: codeCopied)
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Friends
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
