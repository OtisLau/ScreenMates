import SwiftUI

struct SettingsView: View {
    @ObservedObject private var cloudManager = CloudKitManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingDebugMenu = false
    @State private var showingLeaveConfirm = false
    @State private var codeCopied = false

    @State private var limitHours: Int = 0
    @State private var limitMinutes: Int = 0

    private var limitChanged: Bool {
        limitHours * 60 + limitMinutes != cloudManager.groupGoalMinutes
    }

    private func loadLimit() {
        limitHours   = cloudManager.groupGoalMinutes / 60
        limitMinutes = (cloudManager.groupGoalMinutes % 60 / 5) * 5
    }

    private func saveLimit() {
        cloudManager.updateGroupGoal(limitHours * 60 + limitMinutes)
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
                    settingsRow(
                        icon: "number",
                        label: "User ID",
                        value: cloudManager.myID
                    )
                }

                // Group
                Section("Group") {
                    if cloudManager.myGroupID.isEmpty {
                        settingsRow(icon: "person.2", label: "Group", value: "Not in a group")
                    } else {
                        // Tap to copy — shows checkmark feedback
                        Button {
                            UIPasteboard.general.string = cloudManager.myGroupID
                            codeCopied = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1.8))
                                codeCopied = false
                            }
                        } label: {
                            HStack {
                                Image(systemName: "person.2")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                Text("Group Code")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(cloudManager.myGroupID)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 12))
                                    .foregroundStyle(codeCopied ? Color(UIColor.systemGreen) : Color(UIColor.tertiaryLabel))
                                    .animation(.easeInOut(duration: 0.2), value: codeCopied)
                            }
                        }
                        .buttonStyle(.plain)

                        // Leave Group — confirmationDialog anchored to this button
                        Button(role: .destructive) {
                            showingLeaveConfirm = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.red)
                                    .frame(width: 20)
                                Text("Leave Group")
                                    .foregroundStyle(.red)
                            }
                        }
                        .confirmationDialog("Leave group?", isPresented: $showingLeaveConfirm, titleVisibility: .visible) {
                            Button("Leave Group", role: .destructive) { cloudManager.leaveGroup() }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("You'll need a new code to rejoin.")
                        }
                    }
                }

                // Limit
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
            .onAppear { loadLimit() }
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
