import SwiftUI

// Settings screen — shows who you are, what group you're in,
// and a few dev tools for debugging.
struct SettingsView: View {
    @StateObject private var cloudManager = CloudKitManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingDebugMenu = false
    @State private var showingLeaveConfirm = false

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

                Section("Tools") {
                    Button("Force Refresh Now") {
                        cloudManager.forceSyncNow()
                    }
                    NavigationLink("Diagnostics") {
                        DiagnosticView()
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
            .confirmationDialog("Leave group?", isPresented: $showingLeaveConfirm) {
                Button("Leave Group", role: .destructive) { cloudManager.leaveGroup() }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingDebugMenu) {
                DebugMenuView()
            }
        }
    }
}
