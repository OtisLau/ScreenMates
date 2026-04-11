import SwiftUI
import Contacts
import CloudKit

struct FriendsView: View {
    private static let localPendingRequestsKey = "LocalOutgoingPendingFriendNames"

    @ObservedObject private var cloudManager = CloudKitManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var addCode: String = ""
    @State private var lookupState: LookupState = .idle
    @State private var codeCopied = false
    @State private var suggestedFriends: [ContactMatch] = []
    @State private var isLoadingSuggestions = false
    @State private var pendingSuggestionIDs: Set<String> = []
    @State private var sendingSuggestionIDs: Set<String> = []
    @State private var optimisticPendingFriendNames: [String: String] = [:]
    @State private var processingRequestIDs: Set<String> = []
    @State private var removingFriendIDs: Set<String> = []
    @State private var requestErrorMessage: String?

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

    private struct PendingFriendDisplay: Identifiable {
        let userID: String
        let displayName: String

        var id: String { userID }
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
                                if processingRequestIDs.contains(request.id) {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    requestActionButton("Decline", color: .red, isProminent: false) {
                                        Task { await respond(to: request, accepting: false) }
                                    }
                                    requestActionButton("Accept", color: .blue, isProminent: true) {
                                        Task { await respond(to: request, accepting: true) }
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }

                // Accepted friends
                let acceptedFriends = cloudManager.friends.filter { $0.userID != cloudManager.myID }
                let acceptedFriendIDs = Set(acceptedFriends.map(\.userID))
                let cloudOutgoingPendingIDs = Set(cloudManager.outgoingPendingRequests.map(\.recipientUserID))
                let cloudOutgoingPendingFriends = cloudManager.outgoingPendingRequests.compactMap { request -> PendingFriendDisplay? in
                    guard !acceptedFriendIDs.contains(request.recipientUserID) else { return nil }
                    return PendingFriendDisplay(userID: request.recipientUserID, displayName: request.recipientName)
                }
                let optimisticPendingFriends = optimisticPendingFriendNames.compactMap { userID, displayName -> PendingFriendDisplay? in
                    guard !acceptedFriendIDs.contains(userID),
                          !cloudOutgoingPendingIDs.contains(userID)
                    else { return nil }
                    return PendingFriendDisplay(userID: userID, displayName: displayName)
                }
                let outgoingPendingFriends = cloudOutgoingPendingFriends + optimisticPendingFriends
                if !acceptedFriends.isEmpty || !outgoingPendingFriends.isEmpty {
                    Section("Friends (\(acceptedFriends.count + outgoingPendingFriends.count))") {
                        ForEach(acceptedFriends) { friend in
                            HStack {
                                Text(friend.displayName).font(.system(size: 15))
                                Spacer()
                                if removingFriendIDs.contains(friend.userID) {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text(friend.userID.prefix(6).uppercased())
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await removeFriend(friend) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .disabled(removingFriendIDs.contains(friend.userID))
                            }
                        }
                        ForEach(outgoingPendingFriends) { request in
                            HStack {
                                Text(request.displayName)
                                    .font(.system(size: 15))
                                Spacer()
                                Text("Pending")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if cloudManager.pendingRequests.isEmpty && cloudManager.outgoingPendingRequests.isEmpty {
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
                                suggestionActionButton(suggestion)
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
                loadLocalPendingFriends()
                removeAcceptedLocalPendingFriends()
                Task {
                    await cloudManager.fetchPendingRequests()
                    await cloudManager.fetchOutgoingPendingRequests()
                    await acceptReciprocalPendingRequests()
                    reconcileLocalPendingFriends()
                    await loadSuggestions()
                }
            }
            .onChange(of: cloudManager.friends.map(\.userID)) { _, _ in
                reconcileLocalPendingFriends()
            }
            .alert("Friend request failed", isPresented: Binding(
                get: { requestErrorMessage != nil },
                set: { if !$0 { requestErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { requestErrorMessage = nil }
            } message: {
                Text(requestErrorMessage ?? "Something went wrong.")
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
        let incomingPendingIDs = Set(cloudManager.pendingRequests.map(\.requesterUserID))
        let outgoingPendingIDs = Set(cloudManager.outgoingPendingRequests.map(\.recipientUserID))
        let filtered = discovered.filter {
            !friendIDs.contains($0.userID) &&
            !incomingPendingIDs.contains($0.userID) &&
            !outgoingPendingIDs.contains($0.userID) &&
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

        do {
            let profiles = try await CloudKitManager.shared.fetchUsersByPhoneHashes(Array(hashToName.keys))
            return profiles.compactMap { profile in
                guard let name = hashToName[profile.phoneHash] else { return nil }
                return ContactMatch(contactName: name, displayName: profile.displayName, userID: profile.userID)
            }
        } catch {
            print("fetchUsersByPhoneHashes failed: \(error)")
            return []
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private func suggestionActionButton(_ suggestion: ContactMatch) -> some View {
        if sendingSuggestionIDs.contains(suggestion.userID) {
            ProgressView()
                .controlSize(.small)
        } else if pendingSuggestionIDs.contains(suggestion.userID) {
            Text("Pending")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
        } else {
            Button("Add") {
                Task { await sendSuggestionRequest(to: suggestion) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
    }

    private func requestActionButton(
        _ title: String,
        color: Color,
        isProminent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isProminent ? Color.white : color)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(color.opacity(isProminent ? 1 : 0.22))
                }
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func respond(to request: FriendRequest, accepting: Bool) async {
        guard !processingRequestIDs.contains(request.id) else { return }

        processingRequestIDs.insert(request.id)
        defer { processingRequestIDs.remove(request.id) }

        do {
            if accepting {
                try await cloudManager.acceptFriendRequest(request)
            } else {
                try await cloudManager.declineFriendRequest(request)
            }
        } catch {
            requestErrorMessage = friendRequestErrorMessage(from: error)
        }
    }

    private func friendRequestErrorMessage(from error: Error) -> String {
        if let ckError = error as? CKError, ckError.code == .permissionFailure {
            return """
            CloudKit rejected the update. In the Development schema, Friendship needs Write permission for authenticated iCloud users, not just the record creator.
            """
        }
        return error.localizedDescription
    }

    @MainActor
    private func removeFriend(_ friend: MemberData) async {
        guard !removingFriendIDs.contains(friend.userID) else { return }

        removingFriendIDs.insert(friend.userID)
        defer { removingFriendIDs.remove(friend.userID) }

        do {
            try await cloudManager.removeFriend(userID: friend.userID)
        } catch {
            requestErrorMessage = friendRequestErrorMessage(from: error)
        }
    }

    @MainActor
    private func sendSuggestionRequest(to suggestion: ContactMatch) async {
        guard !sendingSuggestionIDs.contains(suggestion.userID),
              !pendingSuggestionIDs.contains(suggestion.userID)
        else { return }

        sendingSuggestionIDs.insert(suggestion.userID)
        defer { sendingSuggestionIDs.remove(suggestion.userID) }

        var acceptedIncomingRequest = false
        var shouldShowPending = true
        do {
            try await cloudManager.sendFriendRequest(toUserID: suggestion.userID)
            acceptedIncomingRequest = try await cloudManager.acceptPendingIncomingFriendRequest(fromUserID: suggestion.userID)
            shouldShowPending = !acceptedIncomingRequest
        } catch CloudKitManager.FriendError.alreadyExists {
            do {
                acceptedIncomingRequest = try await cloudManager.acceptPendingIncomingFriendRequest(fromUserID: suggestion.userID)
                let alreadyFriends = try await cloudManager.hasAcceptedFriendship(withUserID: suggestion.userID)
                shouldShowPending = !acceptedIncomingRequest && !alreadyFriends
            } catch {
                requestErrorMessage = friendRequestErrorMessage(from: error)
                return
            }
        } catch {
            requestErrorMessage = friendRequestErrorMessage(from: error)
            return
        }

        if acceptedIncomingRequest {
            optimisticPendingFriendNames.removeValue(forKey: suggestion.userID)
            saveLocalPendingFriends()
        } else if shouldShowPending {
            pendingSuggestionIDs.insert(suggestion.userID)
            markLocalPendingFriend(userID: suggestion.userID, displayName: suggestion.displayName)
        } else {
            optimisticPendingFriendNames.removeValue(forKey: suggestion.userID)
            saveLocalPendingFriends()
        }
        suggestedFriends.removeAll { $0.userID == suggestion.userID }
        Task {
            await cloudManager.fetchPendingRequests()
            await cloudManager.fetchOutgoingPendingRequests()
            await cloudManager.refreshFriendsNow(reason: acceptedIncomingRequest ? "contact-accept" : "contact-request")
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
            markLocalPendingFriend(userID: toUserID, displayName: displayName)
            Task {
                await cloudManager.fetchOutgoingPendingRequests()
            }
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

    @MainActor
    private func acceptReciprocalPendingRequests() async {
        let incomingRequesterIDs = Set(cloudManager.pendingRequests.map(\.requesterUserID))
        let reciprocalIDs = cloudManager.outgoingPendingRequests
            .map(\.recipientUserID)
            .filter { incomingRequesterIDs.contains($0) }

        guard !reciprocalIDs.isEmpty else { return }

        do {
            for userID in reciprocalIDs {
                _ = try await cloudManager.acceptPendingIncomingFriendRequest(fromUserID: userID)
                optimisticPendingFriendNames.removeValue(forKey: userID)
            }
            saveLocalPendingFriends()
            await cloudManager.fetchPendingRequests()
            await cloudManager.fetchOutgoingPendingRequests()
            await cloudManager.refreshFriendsNow(reason: "reciprocal-pending")
        } catch {
            requestErrorMessage = friendRequestErrorMessage(from: error)
        }
    }

    private func loadLocalPendingFriends() {
        guard let data = UserDefaults.standard.data(forKey: Self.localPendingRequestsKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        optimisticPendingFriendNames = decoded
    }

    private func markLocalPendingFriend(userID: String, displayName: String) {
        optimisticPendingFriendNames[userID] = displayName
        saveLocalPendingFriends()
    }

    private func removeAcceptedLocalPendingFriends() {
        let acceptedFriendIDs = Set(cloudManager.friends.map(\.userID))
        let oldValue = optimisticPendingFriendNames
        optimisticPendingFriendNames = optimisticPendingFriendNames.filter { userID, _ in
            !acceptedFriendIDs.contains(userID)
        }
        if optimisticPendingFriendNames != oldValue {
            saveLocalPendingFriends()
        }
    }

    private func reconcileLocalPendingFriends() {
        let acceptedFriendIDs = Set(cloudManager.friends.map(\.userID))
        let cloudOutgoingPendingIDs = Set(cloudManager.outgoingPendingRequests.map(\.recipientUserID))
        let oldValue = optimisticPendingFriendNames
        optimisticPendingFriendNames = optimisticPendingFriendNames.filter { userID, _ in
            !acceptedFriendIDs.contains(userID) && cloudOutgoingPendingIDs.contains(userID)
        }
        if optimisticPendingFriendNames != oldValue {
            saveLocalPendingFriends()
        }
    }

    private func saveLocalPendingFriends() {
        if optimisticPendingFriendNames.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.localPendingRequestsKey)
            return
        }
        guard let data = try? JSONEncoder().encode(optimisticPendingFriendNames) else { return }
        UserDefaults.standard.set(data, forKey: Self.localPendingRequestsKey)
    }
}
