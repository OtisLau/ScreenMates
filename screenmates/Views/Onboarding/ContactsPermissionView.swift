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
    @StateObject private var auth = PhoneAuthManager.shared

    @State private var isSearching = false
    @State private var matches: [ContactMatch] = []
    @State private var searchDone = false

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
            if CNContactStore.authorizationStatus(for: .contacts) == .authorized {
                startSearch()
            }
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
                         : "Your contacts who are already on ScreenMates")
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

            Button {
                auth.markContactsHandled()
            } label: {
                HStack(spacing: 8) {
                    Text("Continue").fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .glassProminentButtonStyle()
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private func matchRow(_ match: ContactMatch) -> some View {
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

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.green)
                .font(.system(size: 20))
        }
        .padding(16)
        .glassCard(cornerRadius: AppTheme.cornerRadiusLarge)
    }

    // MARK: - Logic

    private func requestContacts() {
        let store = CNContactStore()
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
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
            auth.markContactsHandled()
        @unknown default:
            auth.markContactsHandled()
        }
    }

    private func startSearch() {
        isSearching = true
        Task {
            let results = await discoverContacts()
            await MainActor.run {
                matches = results
                searchDone = true
                isSearching = false
            }
        }
    }

    private func discoverContacts() async -> [ContactMatch] {
        let store = CNContactStore()
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)

        var hashToName: [String: String] = [:]
        try? store.enumerateContacts(with: request) { contact, _ in
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
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
}
