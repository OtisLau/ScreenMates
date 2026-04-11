import SwiftUI
import Contacts

struct FriendsView: View {
    @ObservedObject private var cloudManager = CloudKitManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var addCode: String = ""
    @State private var lookupState: LookupState = .idle
    @State private var codeCopied = false
    @State private var suggestedFriends: [ContactMatch] = []
    @State private var isLoadingSuggestions = false

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
                // Your code — one line, tap to copy, share button on right
                Section("Your Code") {
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = cloudManager.myFriendCode
                            withAnimation(.easeInOut(duration: 0.15)) { codeCopied = true }
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1.8))
                                withAnimation(.easeInOut(duration: 0.15)) { codeCopied = false }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(cloudManager.myFriendCode)
                                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(codeCopied ? Color(UIColor.systemGreen) : .primary)
                                Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 13))
                                    .foregroundStyle(codeCopied ? Color(UIColor.systemGreen) : .secondary)
                            }
                            .animation(.easeInOut(duration: 0.15), value: codeCopied)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        ShareLink(item: "Add me on ScreenMates! My code: \(cloudManager.myFriendCode)") {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15))
                                .foregroundStyle(.blue)
                        }
                    }
                }

                // Add Friend
                Section("Add Friend") {
                    HStack(spacing: 10) {
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
                            Button("Find") { Task { await lookupFriend() } }
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
                            Button("Add") { Task { await sendRequest(toUserID: userID, displayName: displayName) } }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                        }
                    case .sending:
                        HStack(spacing: 8) { ProgressView(); Text("Sending…").foregroundStyle(.secondary) }
                    case .sent:
                        Label("Request sent!", systemImage: "checkmark.circle").foregroundStyle(.green)
                    case .notFound:
                        Text("No user found with that code.").foregroundStyle(.secondary).font(.subheadline)
                    case .alreadyFriends:
                        Text("Already friends or request pending.").foregroundStyle(.secondary).font(.subheadline)
                    case .error(let msg):
                        Text(msg).foregroundStyle(.red).font(.subheadline)
                    default:
                        EmptyView()
                    }
                }

                // Pending requests
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
                                Button("Decline") { Task { await cloudManager.declineFriendRequest(request) } }
                                    .buttonStyle(.bordered).tint(.red)
                                Button("Accept") { Task { await cloudManager.acceptFriendRequest(request) } }
                                    .buttonStyle(.borderedProminent).tint(.blue)
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
                                Text(friend.displayName).font(.system(size: 15))
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

                // Suggested (contacts on ScreenMates who aren't friends yet)
                if isLoadingSuggestions {
                    Section("Suggested") {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                } else if !suggestedFriends.isEmpty {
                    Section {
                        ForEach(suggestedFriends) { suggestion in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.contactName)
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(suggestion.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Add") {
                                    Task { await sendRequest(toUserID: suggestion.userID, displayName: suggestion.displayName) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                            }
                        }
                    } header: {
                        Text("Suggested")
                    } footer: {
                        Text("Contacts already on ScreenMates")
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
                Task {
                    await cloudManager.fetchPendingRequests()
                    await loadSuggestions()
                }
            }
        }
    }

    // MARK: - Suggested friends from contacts

    private func loadSuggestions() async {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return }

        await MainActor.run { isLoadingSuggestions = true }

        let discovered = await discoverContacts()

        // Filter out existing friends and self
        let friendIDs = Set(cloudManager.friends.map(\.userID))
        let pendingIDs = Set(cloudManager.pendingRequests.map(\.requesterUserID))
        let filtered = discovered.filter {
            !friendIDs.contains($0.userID) &&
            !pendingIDs.contains($0.userID) &&
            $0.userID != cloudManager.myID
        }

        await MainActor.run {
            suggestedFriends = filtered
            isLoadingSuggestions = false
        }
    }

    private func discoverContacts() async -> [ContactMatch] {
        let store = CNContactStore()
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)

        var hashToName: [String: String] = [:]
        try? store.enumerateContacts(with: request) { contact, _ in
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }.joined(separator: " ")
            for phone in contact.phoneNumbers {
                if let e164 = PhoneAuthManager.normalizeToE164(phone.value.stringValue) {
                    hashToName[PhoneAuthManager.sha256(e164)] = name
                }
            }
        }
        guard !hashToName.isEmpty else { return [] }

        let profiles = (try? await CloudKitManager.shared.fetchUsersByPhoneHashes(Array(hashToName.keys))) ?? []
        return profiles.compactMap { profile in
            guard let name = hashToName[profile.phoneHash] else { return nil }
            return ContactMatch(contactName: name, displayName: profile.displayName, userID: profile.userID)
        }
    }

    // MARK: - Actions

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
            // Remove from suggestions if it was there
            await MainActor.run {
                suggestedFriends.removeAll { $0.userID == toUserID }
            }
        } catch CloudKitManager.FriendError.alreadyExists {
            lookupState = .alreadyFriends
        } catch {
            lookupState = .error(error.localizedDescription)
        }
    }
}
