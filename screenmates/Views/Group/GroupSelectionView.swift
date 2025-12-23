import SwiftUI

/// Join or create a group (dev-focused: minimal UI, correct CloudKit flow).
struct GroupSelectionView: View {
    @StateObject private var cloudManager = CloudKitManager.shared

    @State private var groupInput: String = ""
    @State private var isWorking = false
    @State private var error: ErrorHandler.AppError?

    @State private var showingShareSheet = false
    @State private var createdGroupID: String = ""

    var body: some View {
        VStack(spacing: 16) {
            TextField("Enter Group ID", text: $groupInput)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)

            HStack(spacing: 12) {
                Button("Join") {
                    joinGroup()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking || groupInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Create") {
                    createGroup()
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)
            }

            if isWorking {
                ProgressView()
            }

            if let error {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
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
