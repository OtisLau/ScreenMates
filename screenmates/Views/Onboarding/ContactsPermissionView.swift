import SwiftUI
import Contacts

struct ContactMatch: Identifiable {
    let id = UUID()
    let contactName: String
    let displayName: String
    let userID: String
}

/// Requests contacts permission, hashes contact phone numbers, queries CloudKit
/// for matching UserProfiles, and shows results. Skippable at any point.
struct ContactsPermissionView: View {
    @ObservedObject private var auth = PhoneAuthManager.shared

    private static let localPendingRequestsKey = "LocalOutgoingPendingFriendNames"

    @State private var isSearching = false
    @State private var isSendingRequests = false
    @State private var matches: [ContactMatch] = []
    @State private var selectedUserIDs: Set<String> = []
    @State private var searchDone = false
    @State private var showDeniedAlert = false
    @State private var requestErrorMessage: String?

    var body: some View {
        ZStack {
            AppBackground()
            if searchDone {
                matchesContent
            } else {
                permissionContent
            }
        }
        .onAppear {
            // If permission already granted from a previous session, go straight to search.
            if canSearchContacts {
                startSearch()
            }
        }
        .alert("Contacts Access Needed", isPresented: $showDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Skip", role: .cancel) {
                auth.markContactsHandled()
            }
        } message: {
            Text("To find friends, enable Contacts access in Settings.")
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

    // MARK: - Permission explanation

    private var permissionContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.primary.opacity(0.7))

                VStack(spacing: 8) {
                    Text("Find your friends")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("See which of your contacts\nalready use ScreenMates")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                // Privacy explanation card
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 36, height: 36)
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.7))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Private by default")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Numbers are hashed before any comparison — never stored in plain text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(16)
                .glassCard(cornerRadius: AppTheme.cornerRadiusLarge)
                .padding(.horizontal, 24)
            }

            Spacer()

            VStack(spacing: 12) {
                Button { requestContacts() } label: {
                    HStack(spacing: 8) {
                        if isSearching {
                            SpinnerIcon()
                            Text("Searching…").fontWeight(.semibold)
                        } else {
                            Text("Find Friends").fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .glassProminentButtonStyle()
                .disabled(isSearching)

                Button("Skip for now") {
                    auth.markContactsHandled()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Results

    private var matchesContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: matches.isEmpty ? "person.slash.fill" : "person.2.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.primary.opacity(0.7))

                VStack(spacing: 8) {
                    Text(matches.isEmpty
                         ? "No matches yet"
                         : "\(matches.count) friend\(matches.count == 1 ? "" : "s") found")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(matches.isEmpty
                         ? "None of your contacts are on ScreenMates yet"
                         : "Select the friends you want to add")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                if !matches.isEmpty {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(matches) { match in
                                matchRow(match)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .frame(maxHeight: 280)
                }
            }

            Spacer()

            // Only show Continue during onboarding. From Settings the view is in a
            // NavigationLink so dismiss() is enough — markContactsHandled is already true.
            if !auth.contactsHandled {
                Button {
                    Task { await continueFromMatches() }
                } label: {
                    HStack(spacing: 8) {
                        if isSendingRequests {
                            SpinnerIcon()
                            Text("Sending…").fontWeight(.semibold)
                        } else {
                            Text(continueButtonTitle).fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .glassProminentButtonStyle()
                .disabled(isSendingRequests)
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }

    private var continueButtonTitle: String {
        guard !selectedUserIDs.isEmpty else { return "Continue" }
        return "Send \(selectedUserIDs.count) request\(selectedUserIDs.count == 1 ? "" : "s")"
    }

    private var canSearchContacts: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized { return true }
        if #available(iOS 18.0, *), status == .limited { return true }
        return false
    }

    private func matchRow(_ match: ContactMatch) -> some View {
        let isSelected = selectedUserIDs.contains(match.userID)

        return Button {
            toggleSelection(for: match)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 36, height: 36)
                    Image(systemName: "person.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(match.contactName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(match.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppTheme.green : Color.secondary)
                    .font(.system(size: 20))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .padding(16)
            .glassCard(cornerRadius: AppTheme.cornerRadiusLarge)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(match.contactName), \(match.displayName)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    // MARK: - Logic

    private func requestContacts() {
        Haptics.medium()
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)

        if canSearchContacts {
            startSearch()
            return
        }

        switch status {
        case .authorized:
            startSearch()
        case .notDetermined:
            isSearching = true
            store.requestAccess(for: .contacts) { granted, _ in
                DispatchQueue.main.async {
                    if granted {
                        startSearch()
                    } else {
                        isSearching = false
                        auth.markContactsHandled()
                    }
                }
            }
        case .denied, .restricted:
            showDeniedAlert = true
        default:
            showDeniedAlert = true
        }
    }

    private func startSearch() {
        isSearching = true
        Task {
            let results = await discoverContacts()
            await MainActor.run {
                matches = results
                selectedUserIDs = []
                searchDone = true
                isSearching = false
            }
        }
    }

    private func toggleSelection(for match: ContactMatch) {
        Haptics.soft()
        if selectedUserIDs.contains(match.userID) {
            selectedUserIDs.remove(match.userID)
        } else {
            selectedUserIDs.insert(match.userID)
        }
    }

    @MainActor
    private func continueFromMatches() async {
        guard !isSendingRequests else { return }
        guard !selectedUserIDs.isEmpty else {
            Haptics.soft()
            auth.markContactsHandled()
            return
        }
        Haptics.medium()

        isSendingRequests = true
        defer { isSendingRequests = false }

        let selectedMatches = matches.filter { selectedUserIDs.contains($0.userID) }
        do {
            for match in selectedMatches {
                do {
                    try await CloudKitManager.shared.sendFriendRequest(toUserID: match.userID)
                    let acceptedIncomingRequest = try await CloudKitManager.shared.acceptPendingIncomingFriendRequest(fromUserID: match.userID)
                    if acceptedIncomingRequest {
                        removeLocalPendingFriend(userID: match.userID)
                    } else {
                        markLocalPendingFriend(userID: match.userID, displayName: match.displayName)
                    }
                } catch CloudKitManager.FriendError.alreadyExists {
                    let acceptedIncomingRequest = try await CloudKitManager.shared.acceptPendingIncomingFriendRequest(fromUserID: match.userID)
                    if acceptedIncomingRequest {
                        removeLocalPendingFriend(userID: match.userID)
                    } else if try await CloudKitManager.shared.hasAcceptedFriendship(withUserID: match.userID) {
                        removeLocalPendingFriend(userID: match.userID)
                    } else {
                        markLocalPendingFriend(userID: match.userID, displayName: match.displayName)
                    }
                }
            }
            await CloudKitManager.shared.fetchPendingRequests()
            await CloudKitManager.shared.fetchOutgoingPendingRequests()
            await CloudKitManager.shared.refreshFriendsNow(reason: "onboarding-contacts")
            auth.markContactsHandled()
        } catch {
            requestErrorMessage = error.localizedDescription
        }
    }

    private func markLocalPendingFriend(userID: String, displayName: String) {
        let existingData = UserDefaults.standard.data(forKey: Self.localPendingRequestsKey)
        var pending = (try? existingData.flatMap {
            try JSONDecoder().decode([String: String].self, from: $0)
        }) ?? [:]
        pending[userID] = displayName

        guard let data = try? JSONEncoder().encode(pending) else { return }
        UserDefaults.standard.set(data, forKey: Self.localPendingRequestsKey)
    }

    private func removeLocalPendingFriend(userID: String) {
        guard let existingData = UserDefaults.standard.data(forKey: Self.localPendingRequestsKey),
              var pending = try? JSONDecoder().decode([String: String].self, from: existingData)
        else { return }

        pending.removeValue(forKey: userID)
        if pending.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.localPendingRequestsKey)
        } else if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: Self.localPendingRequestsKey)
        }
    }

    private func discoverContacts() async -> [ContactMatch] {
        let store = CNContactStore()
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        let myPhoneHash = auth.phoneHash
        let myUserID = CloudKitManager.shared.myID

        var hashToName: [String: String] = [:]
        try? store.enumerateContacts(with: request) { contact, _ in
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            for phone in contact.phoneNumbers {
                if let e164 = PhoneAuthManager.normalizeToE164(phone.value.stringValue) {
                    let phoneHash = PhoneAuthManager.sha256(e164)
                    guard phoneHash != myPhoneHash else { continue }
                    hashToName[phoneHash] = name
                }
            }
        }

        guard !hashToName.isEmpty else { return [] }

        do {
            let profiles = try await CloudKitManager.shared.fetchUsersByPhoneHashes(Array(hashToName.keys))
            return profiles.compactMap { profile in
                guard profile.userID != myUserID,
                      let name = hashToName[profile.phoneHash]
                else { return nil }
                return ContactMatch(contactName: name, displayName: profile.displayName, userID: profile.userID)
            }
        } catch {
            print("fetchUsersByPhoneHashes failed: \(error)")
            return []
        }
    }
}
