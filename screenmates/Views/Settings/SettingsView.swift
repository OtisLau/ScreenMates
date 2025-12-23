import SwiftUI

/// App settings (dev-focused; houses debug + basic account/group actions).
struct SettingsView: View {
    @StateObject private var cloudManager = CloudKitManager.shared

    @Environment(\.dismiss) private var dismiss

    @State private var showingDebugMenu = false
    @State private var showingLeaveConfirm = false

    @State private var goalDraft: Int = AppConstants.defaultDailyGoalBlocks
    @State private var goalIsSaving = false
    @State private var goalError: ErrorHandler.AppError?

    var body: some View {
        NavigationView {
            List {
                Section("Identity") {
                    LabeledContent("User ID", value: cloudManager.myID)
                    LabeledContent("Name", value: cloudManager.myDisplayName.isEmpty ? "Not set" : cloudManager.myDisplayName)
                }

                Section("Group") {
                    LabeledContent("Group ID", value: cloudManager.myGroupID.isEmpty ? "Not in a group" : cloudManager.myGroupID)
                    if !cloudManager.myGroupID.isEmpty {
                        Button(role: .destructive) {
                            showingLeaveConfirm = true
                        } label: {
                            Text("Leave Group")
                        }
                    }
                }

                Section("Daily Goal") {
                    let currentGoal = cloudManager.currentGroup?.dailyGoalBlocks ?? AppConstants.defaultDailyGoalBlocks
                    LabeledContent("Current goal", value: "\(currentGoal) blocks")

                    Stepper(value: $goalDraft, in: 1...AppConstants.maxDailyCheckpoints) {
                        Text("New goal: \(goalDraft) blocks")
                    }
                    .disabled(cloudManager.myGroupID.isEmpty || goalIsSaving)

                    Button {
                        saveGoal()
                    } label: {
                        if goalIsSaving {
                            HStack {
                                ProgressView()
                                Text("Saving…")
                            }
                        } else {
                            Text("Save Goal")
                        }
                    }
                    .disabled(cloudManager.myGroupID.isEmpty || goalIsSaving || goalDraft == currentGoal)

                    if let goalError {
                        Text(goalError.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section("Tools") {
                    Button("Force Refresh Now") {
                        cloudManager.forceSyncNow()
                    }

                    NavigationLink {
                        DiagnosticView()
                    } label: {
                        Text("Diagnostics")
                    }

                    Button("Debug Menu") {
                        showingDebugMenu = true
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                goalDraft = cloudManager.currentGroup?.dailyGoalBlocks ?? AppConstants.defaultDailyGoalBlocks
            }
            .confirmationDialog("Leave group?", isPresented: $showingLeaveConfirm) {
                Button("Leave Group", role: .destructive) {
                    cloudManager.leaveGroup()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingDebugMenu) {
                DebugMenuView()
            }
        }
    }

    private func saveGoal() {
        goalError = nil
        goalIsSaving = true
        let newGoal = goalDraft

        cloudManager.updateGroupGoal(newGoal: newGoal) { result in
            DispatchQueue.main.async {
                self.goalIsSaving = false
                switch result {
                case .success:
                    Task { @MainActor in
                        // Pull latest group details + mirror into App Group.
                        await cloudManager.refreshGroupNow(reason: "goal-change")
                    }
                case .failure(let err):
                    self.goalError = err
                }
            }
        }
    }
}
