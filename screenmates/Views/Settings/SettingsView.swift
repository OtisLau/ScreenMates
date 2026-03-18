import SwiftUI

struct SettingsView: View {
    @StateObject private var cloudManager = CloudKitManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingDebugMenu = false
    @State private var showingLeaveConfirm = false

    // Preset goal options in minutes
    private let goalOptions = [30, 60, 90, 120, 150, 180, 240, 300, 360]

    private func goalLabel(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
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
                        icon: "person.fill",
                        iconColor: AppTheme.accent,
                        label: "Display Name",
                        value: cloudManager.myDisplayName.isEmpty ? "Not set" : cloudManager.myDisplayName
                    )
                    settingsRow(
                        icon: "number",
                        iconColor: Color.secondary,
                        label: "User ID",
                        value: String(cloudManager.myID.prefix(12)) + "..."
                    )
                }

                // Group
                Section("Group") {
                    if cloudManager.myGroupID.isEmpty {
                        settingsRow(
                            icon: "person.2.fill",
                            iconColor: Color.secondary,
                            label: "Group",
                            value: "Not in a group"
                        )
                    } else {
                        settingsRow(
                            icon: "person.2.fill",
                            iconColor: Color(UIColor.systemGreen),
                            label: "Group Code",
                            value: cloudManager.myGroupID
                        )

                        Button(role: .destructive) {
                            showingLeaveConfirm = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.red.opacity(0.15))
                                        .frame(width: 28, height: 28)
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.red)
                                }
                                Text("Leave Group")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                // Goal
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(UIColor.systemGreen).opacity(0.15))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "target")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(UIColor.systemGreen))
                            }
                            Text("Daily Goal")
                            Spacer()
                            Text(cloudManager.dailyGoalMinutes == 0 ? "No goal" : goalLabel(cloudManager.dailyGoalMinutes))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(cloudManager.dailyGoalMinutes == 0 ? Color.secondary : AppTheme.accent)
                        }

                        // Scrollable row of preset chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                // "No goal" chip
                                let noGoalSelected = cloudManager.dailyGoalMinutes == 0
                                Button {
                                    cloudManager.dailyGoalMinutes = 0
                                } label: {
                                    Text("None")
                                        .font(.system(size: 13, weight: noGoalSelected ? .bold : .regular))
                                        .foregroundStyle(noGoalSelected ? Color.primary : Color.secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(noGoalSelected ? Color(UIColor.secondarySystemFill) : Color.clear)
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(noGoalSelected ? Color(UIColor.separator) : Color(UIColor.separator).opacity(0.5), lineWidth: 1))
                                }
                                .buttonStyle(.plain)

                                ForEach(goalOptions, id: \.self) { minutes in
                                    let selected = cloudManager.dailyGoalMinutes == minutes
                                    Button {
                                        cloudManager.dailyGoalMinutes = minutes
                                    } label: {
                                        Text(goalLabel(minutes))
                                            .font(.system(size: 13, weight: selected ? .bold : .regular, design: .monospaced))
                                            .foregroundStyle(selected ? Color.primary : Color.secondary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(selected ? Color(UIColor.secondarySystemFill) : Color.clear)
                                            .clipShape(Capsule())
                                            .overlay(Capsule().stroke(selected ? Color(UIColor.separator) : Color(UIColor.separator).opacity(0.5), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }

                        Text("How much screen time you're aiming for per day")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Goal")
                }

                // Tools
                Section("Tools") {
                    Button {
                        cloudManager.forceSyncNow()
                    } label: {
                        actionRow(icon: "arrow.triangle.2.circlepath", iconColor: Color(UIColor.systemGreen), label: "Force Sync")
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        DiagnosticView()
                    } label: {
                        actionRow(icon: "stethoscope", iconColor: .orange, label: "Diagnostics")
                    }

                    Button {
                        showingDebugMenu = true
                    } label: {
                        actionRow(icon: "wrench.and.screwdriver.fill", iconColor: Color.secondary, label: "Debug Menu")
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Leave group?", isPresented: $showingLeaveConfirm) {
                Button("Leave Group", role: .destructive) { cloudManager.leaveGroup() }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingDebugMenu) {
                DebugMenuView()
            }
        }
    }

    private func settingsRow(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(iconColor)
            }
            Text(label)
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func actionRow(icon: String, iconColor: Color, label: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(iconColor)
            }
            Text(label)
        }
    }
}
