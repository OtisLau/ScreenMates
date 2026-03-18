import SwiftUI

// Join or create a group.
struct GroupSelectionView: View {
    @StateObject private var cloudManager = CloudKitManager.shared

    @State private var groupInput: String = ""
    @State private var isWorking = false
    @State private var error: ErrorHandler.AppError?
    @State private var showingShareSheet = false
    @State private var createdGroupID: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 40)

                // Header
                VStack(spacing: 10) {
                    Text("Join Your Group")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Connect with friends to compare screen time")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Action cards
                VStack(spacing: 12) {

                    // Create group button
                    Button {
                        createGroup()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "plus.square.on.square")
                                .font(.system(size: 20))
                                .foregroundStyle(Color(UIColor.systemGreen))
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Create a Group")
                                    .font(.headline)
                                Text("Get a code to share with friends")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if isWorking && createdGroupID.isEmpty {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(16)
                        .glassCard(cornerRadius: AppTheme.cornerRadiusLarge)
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)

                    // Divider
                    HStack {
                        Rectangle().fill(Color(UIColor.separator)).frame(height: 0.5)
                        Text("or")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                        Rectangle().fill(Color(UIColor.separator)).frame(height: 0.5)
                    }

                    // Join group card
                    VStack(spacing: 12) {
                        HStack(spacing: 14) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 20))
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Join a Group")
                                    .font(.headline)
                                Text("Enter the 6-character code")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        // Code input
                        HStack(spacing: 10) {
                            TextField("XXXXXX", text: $groupInput)
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .kerning(4)
                                .textInputAutocapitalization(.characters)
                                .disableAutocorrection(true)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 14)
                                .glassCard(cornerRadius: AppTheme.cornerRadius)

                            Button {
                                joinGroup()
                            } label: {
                                if isWorking && !groupInput.isEmpty {
                                    ProgressView()
                                        .frame(width: 52, height: 48)
                                } else {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 18, weight: .bold))
                                        .frame(width: 52, height: 48)
                                }
                            }
                            .glassProminentButtonStyle()
                            .disabled(isWorking || groupInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(16)
                    .glassCard(cornerRadius: AppTheme.cornerRadiusLarge)
                }
                .padding(.horizontal)

                // Error message
                if let error {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer(minLength: 40)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            GroupShareSheet(groupID: createdGroupID)
        }
    }

    private func joinGroup() {
        error = nil
        isWorking = true
        let gid = groupInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        cloudManager.validateGroup(gid) { result in
            DispatchQueue.main.async {
                self.isWorking = false
                switch result {
                case .success:
                    self.cloudManager.joinGroup(groupID: gid)
                case .failure(let appError):
                    self.error = appError
                }
            }
        }
    }

    private func createGroup() {
        error = nil
        isWorking = true
        cloudManager.createGroup { result in
            DispatchQueue.main.async {
                self.isWorking = false
                switch result {
                case .success(let groupID):
                    self.createdGroupID = groupID
                    self.showingShareSheet = true
                case .failure(let appError):
                    self.error = appError
                }
            }
        }
    }
}
