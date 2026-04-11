import SwiftUI

struct FriendsView: View {
    @ObservedObject private var cloudManager = CloudKitManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var addCode: String = ""
    @State private var lookupState: LookupState = .idle
    @State private var codeCopied = false

    enum LookupState: Equatable {
        case idle
        case searching
        case found(userID: String, displayName: String)
        case notFound
        case sending
        case sent
        case error(String)
        case alreadyFriends
    }

    var body: some View {
        NavigationStack {
            List {
                // Friend code
                Section {
                    Button {
                        UIPasteboard.general.string = cloudManager.myFriendCode
                        codeCopied = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.8))
                            codeCopied = false
                        }
                    } label: {
                        HStack {
                            Text(cloudManager.myFriendCode)
                                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(codeCopied ? Color(UIColor.systemGreen) : .secondary)
                                .animation(.easeInOut(duration: 0.2), value: codeCopied)
                        }
                    }
                    .buttonStyle(.plain)

                    ShareLink(
                        item: "Add me on ScreenMates! My code: \(cloudManager.myFriendCode)"
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14))
                            Text("Share Code")
                        }
                    }
                } header: {
                    Text("Your Friend Code")
                } footer: {
                    Text("Share this with friends so they can add you.")
                }

                // Add by code
                Section {
                    HStack {
                        TextField("Enter code", text: $addCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onChange(of: addCode) { _, new in
                                addCode = String(new.prefix(6))
                                if lookupState != .idle { lookupState = .idle }
                            }

                        if case .searching = lookupState {
                            ProgressView()
                        } else if addCode.count == 6 {
                            Button("Find") {
                                Task { await lookupFriend() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                    }

                    switch lookupState {
                    case .found(let userID, let displayName):
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(userID.prefix(6).uppercased())
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Add") {
                                Task { await sendRequest(toUserID: userID, displayName: displayName) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }

                    case .sending:
                        HStack {
                            ProgressView()
                            Text("Sending request…")
                                .foregroundStyle(.secondary)
                        }

                    case .sent:
                        Label("Request sent!", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)

                    case .notFound:
                        Text("No user found with that code.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)

                    case .alreadyFriends:
                        Text("You already have a request or friendship with this person.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)

                    case .error(let msg):
                        Text(msg)
                            .foregroundStyle(.red)
                            .font(.subheadline)

                    default:
                        EmptyView()
                    }
                } header: {
                    Text("Add Friend")
                }

                // Pending incoming requests
                if !cloudManager.pendingRequests.isEmpty {
                    Section("Requests") {
                        ForEach(cloudManager.pendingRequests) { request in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(request.requesterName)
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(request.requesterUserID.prefix(6).uppercased())
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Decline") {
                                    Task { await cloudManager.declineFriendRequest(request) }
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)

                                Button("Accept") {
                                    Task { await cloudManager.acceptFriendRequest(request) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                            }
                        }
                    }
                }

                // Accepted friends
                let acceptedFriends = cloudManager.friends.filter { $0.userID != cloudManager.myID }
                if !acceptedFriends.isEmpty {
                    Section("Friends (\(acceptedFriends.count))") {
                        ForEach(acceptedFriends) { friend in
                            HStack {
                                Text(friend.displayName)
                                    .font(.system(size: 15))
                                Spacer()
                                Text(friend.userID.prefix(6).uppercased())
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                } else if cloudManager.pendingRequests.isEmpty {
                    Section {
                        Text("No friends yet — share your code to get started.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                Task { await cloudManager.fetchPendingRequests() }
            }
        }
    }

    private func lookupFriend() async {
        lookupState = .searching
        do {
            if let result = try await cloudManager.lookupUserByFriendCode(addCode) {
                lookupState = .found(userID: result.userID, displayName: result.displayName)
            } else {
                lookupState = .notFound
            }
        } catch {
            lookupState = .error(error.localizedDescription)
        }
    }

    private func sendRequest(toUserID: String, displayName: String) async {
        lookupState = .sending
        do {
            try await cloudManager.sendFriendRequest(toUserID: toUserID)
            lookupState = .sent
            addCode = ""
        } catch CloudKitManager.FriendError.alreadyExists {
            lookupState = .alreadyFriends
        } catch {
            lookupState = .error(error.localizedDescription)
        }
    }
}
