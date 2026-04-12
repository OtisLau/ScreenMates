import CloudKit
import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

// Handles everything CloudKit: saving your profile, fetching friends' data,
// background sync, and friend request management.
class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()

    struct RestoredAccount {
        let displayName: String
    }

    // MARK: - CloudKit
    let container = CKContainer(identifier: AppConstants.cloudKitContainerID)
    lazy var database = container.publicCloudDatabase

    // MARK: - Who am I?
    @AppStorage("my_user_id") var myID: String = ""
    @AppStorage("my_display_name") var myDisplayName: String = ""
    @AppStorage("my_group_id") var myGroupID: String = ""
    @AppStorage("is_setup_done") var isSetupDone: Bool = false
    @AppStorage("username_set") var usernameSet: Bool = false

    // Personal daily limit — stored locally and synced to/from UserProfile.personal_goal_minutes.
    @Published var myPersonalGoalMinutes: Int = 0

    // Backward-compat alias so settings/debug views that still read groupGoalMinutes compile.
    var groupGoalMinutes: Int { myPersonalGoalMinutes }

    // Friends leaderboard — current user + accepted friends, sorted by usage descending.
    @Published var friends: [MemberData] = []

    // Backward-compat alias — debug/diagnostic views still read groupMembers.
    var groupMembers: [MemberData] { friends }

    // Pending incoming friend requests (status == pending, recipient == me).
    @Published var pendingRequests: [FriendRequest] = []

    // Pending outgoing friend requests (status == pending, requester == me).
    @Published var outgoingPendingRequests: [OutgoingFriendRequest] = []

    // MARK: - UI State
    @Published var isLoading = false
    @Published var lastError: ErrorHandler.AppError?
    @Published var lastSyncTime: Date?

    // Shared storage accessible by the ScreenTimeMonitor extension and widget
    private let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)

    // Reusable encoder/decoder — avoids repeated allocation on every cache read/write
    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder = JSONDecoder()
    private static let friendRequestSubscriptionRetryInterval: TimeInterval = 60 * 60

    // Throttle widget timeline reloads to avoid OOM-killing the widget process.
    private var lastWidgetReload: Date = .distantPast
    private let widgetReloadThrottleForeground: TimeInterval = 30
    private let widgetReloadThrottleBackground: TimeInterval = 15 * 60

    // The CloudKit record ID for this user — always the same so we never create duplicates.
    private var myUserProfileRecordID: CKRecord.ID {
        CKRecord.ID(recordName: myID)
    }

    // MARK: - Friend Code

    // Short shareable code derived from the user's ID — first 6 hex chars, uppercased.
    // e.g. user_id "550e8400-e29b-..." → "550E84"
    var myFriendCode: String {
        String(myID.prefix(6)).uppercased()
    }

    private init() {
        if myID.isEmpty {
            myID = KeychainStore.getOrCreateStableUserID()
        } else {
            KeychainStore.saveStableUserID(myID)
        }

        myPersonalGoalMinutes = UserDefaults.standard.integer(forKey: AppConstants.Keys.myPersonalGoalMinutes)
        loadCachedData()
        mirrorIdentityToAppGroup()
    }

    private func mirrorIdentityToAppGroup() {
        sharedDefaults?.set(myID, forKey: AppConstants.Keys.sharedUserID)
        sharedDefaults?.set(myDisplayName, forKey: AppConstants.Keys.sharedDisplayName)
        sharedDefaults?.set(AppConstants.currentBlockSize, forKey: AppConstants.Keys.sharedBlockSizeMinutes)
        sharedDefaults?.set(myPersonalGoalMinutes, forKey: AppConstants.Keys.sharedGoalMinutes)
    }

    // MARK: - Profile Updates

    // Fetch-or-create the user's CloudKit record, apply current fields, and save.
    // Retries once on conflict by re-fetching the server version.
    private func saveProfileToCloud(blocks: Int? = nil) async throws {
        let currentBlocks = blocks ?? (sharedDefaults?.integer(forKey: AppConstants.Keys.dailyBlocksUsed) ?? 0)
        let postMidnightBlocks = sharedDefaults?.integer(forKey: AppConstants.Keys.postMidnightBlocksUsed) ?? 0

        let record: CKRecord
        do {
            record = try await database.record(for: myUserProfileRecordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: "UserProfile", recordID: myUserProfileRecordID)
        }

        let phoneHash = PhoneAuthManager.shared.phoneHash
        let authProviderUserID = PhoneAuthManager.shared.authProviderUserID

        record["user_id"]               = myID
        record["display_name"]          = myDisplayName
        record["blocks_used"]           = currentBlocks
        record["post_midnight_blocks"]  = postMidnightBlocks
        record["last_updated"]          = Date()
        record["last_active_date"]      = Date()
        record["personal_goal_minutes"] = myPersonalGoalMinutes
        if !phoneHash.isEmpty { record["phone_hash"] = phoneHash }
        if !authProviderUserID.isEmpty {
            record["auth_provider_user_id"] = authProviderUserID
            record["phone_verified_at"] = Date()
        }

        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            let latest = try await database.record(for: myUserProfileRecordID)
            latest["user_id"]               = myID
            latest["display_name"]          = myDisplayName
            latest["blocks_used"]           = currentBlocks
            latest["post_midnight_blocks"]  = postMidnightBlocks
            latest["last_updated"]          = Date()
            latest["last_active_date"]      = Date()
            latest["personal_goal_minutes"] = myPersonalGoalMinutes
            if !phoneHash.isEmpty { latest["phone_hash"] = phoneHash }
            if !authProviderUserID.isEmpty {
                latest["auth_provider_user_id"] = authProviderUserID
                latest["phone_verified_at"] = Date()
            }
            _ = try await database.save(latest)
        }

        await MainActor.run { lastSyncTime = Date() }
        print("☁️ Profile saved: \(currentBlocks) blocks, \(myPersonalGoalMinutes)m limit")
    }

    func updateMyProfile(completion: (() -> Void)? = nil) {
        mirrorIdentityToAppGroup()

        guard !myDisplayName.isEmpty else {
            print("Skipping profile update - display name not set yet")
            completion?()
            return
        }

        Task {
            do {
                try await saveProfileToCloud()
            } catch {
                print("Profile save failed: \(error.localizedDescription)")
            }
            completion?()
        }
    }

    @MainActor
    func restoreExistingAccount(phoneHash: String, providerUserID: String) async throws -> RestoredAccount? {
        guard !phoneHash.isEmpty else { return nil }

        let predicate = NSPredicate(format: "phone_hash == %@", phoneHash)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)

        let (results, _) = try await database.records(matching: query, resultsLimit: 1)
        guard let record = results.compactMap({ _, result in
            if case .success(let record) = result { return record }
            return nil
        }).first else {
            return nil
        }

        let restoredID = record["user_id"] as? String ?? record.recordID.recordName
        let restoredName = record["display_name"] as? String ?? ""
        let restoredGoal = record["personal_goal_minutes"] as? Int ?? 0

        myID = restoredID
        KeychainStore.saveStableUserID(restoredID)
        myDisplayName = restoredName
        usernameSet = !restoredName.isEmpty
        myPersonalGoalMinutes = restoredGoal
        UserDefaults.standard.set(restoredGoal, forKey: AppConstants.Keys.myPersonalGoalMinutes)

        record["user_id"]               = restoredID
        record["auth_provider_user_id"] = providerUserID
        record["phone_verified_at"]     = Date()
        record["last_active_date"]      = Date()
        record["phone_hash"]            = phoneHash
        _ = try await database.save(record)

        mirrorIdentityToAppGroup()
        lastSyncTime = Date()

        return RestoredAccount(displayName: restoredName)
    }

    @MainActor
    func deactivateAccount() async throws {
        let userID = myID
        let profileID = myUserProfileRecordID

        try await markFriendshipsRemoved(for: userID)

        do {
            try await database.deleteRecord(withID: profileID)
        } catch let error as CKError where error.code == .unknownItem {
            print("UserProfile already deleted")
        }

        resetLocalAccountState(regenerateUserID: true)
    }

    // MARK: - Personal Goal

    func updatePersonalGoal(_ minutes: Int) {
        myPersonalGoalMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: AppConstants.Keys.myPersonalGoalMinutes)
        sharedDefaults?.set(minutes, forKey: AppConstants.Keys.sharedGoalMinutes)

        Task {
            do {
                try await saveProfileToCloud()
            } catch {
                print("Personal goal save failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Friends Leaderboard

    // Full refresh: upload my profile, fetch friends leaderboard, evaluate notifications.
    // isSilentPush: skip uploading to avoid push feedback loops.
    @MainActor
    func refreshFriendsNow(reason: String? = nil) async {
        guard !myID.isEmpty else { return }
        print("Refreshing friends leaderboard (\(reason ?? ""))")

        isLoading = true
        defer { isLoading = false }

        let isSilentPush = reason == "silent-push"

        if !isSilentPush {
            await withCheckedContinuation { cont in
                updateMyProfile { cont.resume() }
            }
            try? await cleanupMyDuplicateProfiles()
        }

        do {
            let members = try await fetchFriendsAsync()
            friends = members
            lastSyncTime = Date()

            // Sync my own personal goal from CloudKit in case it changed on another device
            if let me = members.first(where: { $0.userID == myID }) {
                if me.personalGoalMinutes != myPersonalGoalMinutes {
                    myPersonalGoalMinutes = me.personalGoalMinutes
                    UserDefaults.standard.set(me.personalGoalMinutes, forKey: AppConstants.Keys.myPersonalGoalMinutes)
                    sharedDefaults?.set(me.personalGoalMinutes, forKey: AppConstants.Keys.sharedGoalMinutes)
                }
            }

            let forceWidgetReload = reason == "pull-to-refresh" || reason == "manual" || reason == "appear"
            cacheLeaderboardData(forceWidgetReload: forceWidgetReload)

            NotificationManager.shared.evaluateAndSchedule(
                members: members,
                myUserID: myID
            )

            // Also refresh pending requests so the friends badge stays current
            await fetchPendingRequests()
        } catch {
            lastError = handleCloudKitError(error)
        }
    }

    // Backward-compat — existing callsites (AppDelegate, debug screens) still work.
    @MainActor
    func refreshGroupNow(reason: String? = nil) async {
        await refreshFriendsNow(reason: reason)
    }

    func fetchFriendsAsync() async throws -> [MemberData] {
        // Step 1: find all accepted friendships involving me.
        // CloudKit doesn't support OR with multi-condition branches, so run two queries.
        let sentQuery     = CKQuery(recordType: "Friendship",
            predicate: NSPredicate(format: "requester_user_id == %@ AND status == 'accepted'", myID))
        let receivedQuery = CKQuery(recordType: "Friendship",
            predicate: NSPredicate(format: "recipient_user_id == %@ AND status == 'accepted'", myID))

        let (sentResults, _)     = try await database.records(matching: sentQuery)
        let (receivedResults, _) = try await database.records(matching: receivedQuery)
        let friendshipResults    = sentResults + receivedResults

        var friendIDs: [String] = []
        for (_, result) in friendshipResults {
            if case .success(let record) = result {
                let requester = record["requester_user_id"] as? String ?? ""
                let recipient = record["recipient_user_id"] as? String ?? ""
                let friendID  = requester == myID ? recipient : requester
                if !friendID.isEmpty, friendID != myID {
                    friendIDs.append(friendID)
                }
            }
        }

        // Step 2: fetch UserProfile for friends + myself
        let allIDs = Array(Set(friendIDs + [myID]))
        let profilePredicate = NSPredicate(format: "user_id IN %@", allIDs)
        let profileQuery = CKQuery(recordType: "UserProfile", predicate: profilePredicate)
        profileQuery.sortDescriptors = [NSSortDescriptor(key: "blocks_used", ascending: false)]

        let (profileResults, _) = try await database.records(matching: profileQuery)
        var members: [MemberData] = []

        for (_, result) in profileResults {
            if case .success(let record) = result {
                let userID = record["user_id"] as? String ?? record.recordID.recordName
                members.append(MemberData(
                    userID: userID,
                    displayName: record["display_name"] as? String ?? userID,
                    blocks: record["blocks_used"] as? Int ?? 0,
                    lastUpdate: record["last_updated"] as? Date ?? Date(),
                    postMidnightBlocks: record["post_midnight_blocks"] as? Int ?? 0,
                    personalGoalMinutes: record["personal_goal_minutes"] as? Int ?? 0
                ))
            }
        }

        // If my own profile wasn't in CloudKit yet, inject local data so dashboard isn't blank
        if !members.contains(where: { $0.userID == myID }) {
            let localBlocks = sharedDefaults?.integer(forKey: AppConstants.Keys.dailyBlocksUsed) ?? 0
            members.append(MemberData(
                userID: myID,
                displayName: myDisplayName,
                blocks: localBlocks,
                lastUpdate: Date(),
                personalGoalMinutes: myPersonalGoalMinutes
            ))
        }

        return dedupeMembers(members)
    }

    // Fetch UserProfile records whose phone_hash matches any of the provided hashes.
    // Used by ContactsPermissionView to discover which contacts are on ScreenMates.
    func fetchUsersByPhoneHashes(_ hashes: [String]) async throws -> [(userID: String, displayName: String, phoneHash: String)] {
        let uniqueHashes = Array(Set(hashes)).filter { !$0.isEmpty }
        guard !uniqueHashes.isEmpty else { return [] }

        var profilesByUserID: [String: (userID: String, displayName: String, phoneHash: String)] = [:]
        let chunkSize = 100

        for startIndex in stride(from: 0, to: uniqueHashes.count, by: chunkSize) {
            let endIndex = min(startIndex + chunkSize, uniqueHashes.count)
            let chunk = Array(uniqueHashes[startIndex..<endIndex])
            let predicate = NSPredicate(format: "phone_hash IN %@", chunk)
            let query = CKQuery(recordType: "UserProfile", predicate: predicate)
            let (matchResults, _) = try await database.records(matching: query)

            for (_, result) in matchResults {
                guard case .success(let record) = result,
                      let userID      = record["user_id"]      as? String,
                      let displayName = record["display_name"] as? String,
                      let phoneHash   = record["phone_hash"]   as? String
                else { continue }
                profilesByUserID[userID] = (userID: userID, displayName: displayName, phoneHash: phoneHash)
            }
        }

        return Array(profilesByUserID.values)
    }

    // MARK: - Friend Requests

    // Look up a UserProfile by friend code (first 6 chars of user_id, case-insensitive).
    // Returns nil if not found or if the code matches the current user.
    func lookupUserByFriendCode(_ code: String) async throws -> (userID: String, displayName: String)? {
        let prefix = code.uppercased()
        guard prefix.count == 6 else { return nil }
        let predicate = NSPredicate(format: "user_id BEGINSWITH %@", prefix)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        let (results, _) = try await database.records(matching: query, resultsLimit: 5)

        for (_, result) in results {
            if case .success(let record) = result,
               let userID = record["user_id"] as? String,
               let name   = record["display_name"] as? String,
               userID != myID {
                return (userID: userID, displayName: name)
            }
        }
        return nil
    }

    // Send a friend request to another user. Creates a Friendship record with status "pending".
    func sendFriendRequest(toUserID: String) async throws {
        // Check we don't already have a friendship with this person.
        // CloudKit doesn't support OR with multi-condition branches, so run two queries.
        let sentQuery = CKQuery(recordType: "Friendship",
            predicate: NSPredicate(format: "requester_user_id == %@ AND recipient_user_id == %@", myID, toUserID))
        let (sentResults, _) = try await database.records(matching: sentQuery, resultsLimit: 1)
        if sentResults.contains(where: { _, result in
            guard case .success(let record) = result else { return false }
            let status = record["status"] as? String
            return status == "pending" || status == "accepted"
        }) {
            throw FriendError.alreadyExists
        }

        let receivedQuery = CKQuery(recordType: "Friendship",
            predicate: NSPredicate(format: "requester_user_id == %@ AND recipient_user_id == %@", toUserID, myID))
        let (receivedResults, _) = try await database.records(matching: receivedQuery, resultsLimit: 1)
        if receivedResults.contains(where: { _, result in
            guard case .success(let record) = result else { return false }
            let status = record["status"] as? String
            return status == "pending" || status == "accepted"
        }) {
            throw FriendError.alreadyExists
        }

        let record = CKRecord(recordType: "Friendship")
        record["requester_user_id"] = myID
        record["recipient_user_id"] = toUserID
        record["status"]            = "pending"
        record["created_at"]        = Date()
        record["updated_at"]        = Date()

        let requesterPhoneHash = PhoneAuthManager.shared.phoneHash
        if !requesterPhoneHash.isEmpty {
            record["requester_phone_hash"] = requesterPhoneHash
        }

        _ = try await database.save(record)
        print("Friend request sent to \(toUserID)")
    }

    func hasAcceptedFriendship(withUserID userID: String) async throws -> Bool {
        let sentQuery = CKQuery(recordType: "Friendship",
            predicate: NSPredicate(format: "requester_user_id == %@ AND recipient_user_id == %@ AND status == 'accepted'", myID, userID))
        let receivedQuery = CKQuery(recordType: "Friendship",
            predicate: NSPredicate(format: "requester_user_id == %@ AND recipient_user_id == %@ AND status == 'accepted'", userID, myID))

        let (sentResults, _) = try await database.records(matching: sentQuery, resultsLimit: 1)
        if !sentResults.isEmpty { return true }

        let (receivedResults, _) = try await database.records(matching: receivedQuery, resultsLimit: 1)
        return !receivedResults.isEmpty
    }

    // Fetch pending incoming requests (where I am the recipient).
    @MainActor
    func fetchPendingRequests() async {
        guard !myID.isEmpty else { return }
        let predicate = NSPredicate(format: "recipient_user_id == %@ AND status == 'pending'", myID)
        let query = CKQuery(recordType: "Friendship", predicate: predicate)

        do {
            let (results, _) = try await database.records(matching: query)

            var requests: [FriendRequest] = []
            var requesterIDs: [String] = []

            for (_, result) in results {
                if case .success(let record) = result,
                   let requesterID = record["requester_user_id"] as? String {
                    requests.append(FriendRequest(
                        id: record.recordID.recordName,
                        recordID: record.recordID,
                        requesterUserID: requesterID,
                        requesterName: requesterID // will fill in below
                    ))
                    requesterIDs.append(requesterID)
                }
            }

            // Fetch display names for requesters
            if !requesterIDs.isEmpty {
                let namePredicate = NSPredicate(format: "user_id IN %@", requesterIDs)
                let nameQuery = CKQuery(recordType: "UserProfile", predicate: namePredicate)
                let (nameResults, _) = try await database.records(matching: nameQuery)
                var names: [String: String] = [:]
                for (_, result) in nameResults {
                    if case .success(let record) = result,
                       let uid  = record["user_id"] as? String,
                       let name = record["display_name"] as? String {
                        names[uid] = name
                    }
                }
                requests = requests.map { req in
                    FriendRequest(
                        id: req.id,
                        recordID: req.recordID,
                        requesterUserID: req.requesterUserID,
                        requesterName: names[req.requesterUserID] ?? req.requesterUserID
                    )
                }
            }

            pendingRequests = requests
        } catch {
            print("fetchPendingRequests failed: \(error.localizedDescription)")
        }
    }

    // Fetch pending outgoing requests (where I am the requester).
    @MainActor
    func fetchOutgoingPendingRequests() async {
        guard !myID.isEmpty else { return }
        let predicate = NSPredicate(format: "requester_user_id == %@", myID)
        let query = CKQuery(recordType: "Friendship", predicate: predicate)

        do {
            let (results, _) = try await database.records(matching: query)

            var requests: [OutgoingFriendRequest] = []
            var recipientIDs: [String] = []

            for (_, result) in results {
                if case .success(let record) = result,
                   record["status"] as? String == "pending",
                   let recipientID = record["recipient_user_id"] as? String {
                    requests.append(OutgoingFriendRequest(
                        id: record.recordID.recordName,
                        recordID: record.recordID,
                        recipientUserID: recipientID,
                        recipientName: recipientID
                    ))
                    recipientIDs.append(recipientID)
                }
            }

            if !recipientIDs.isEmpty {
                let namePredicate = NSPredicate(format: "user_id IN %@", recipientIDs)
                let nameQuery = CKQuery(recordType: "UserProfile", predicate: namePredicate)
                let (nameResults, _) = try await database.records(matching: nameQuery)
                var names: [String: String] = [:]
                for (_, result) in nameResults {
                    if case .success(let record) = result,
                       let uid = record["user_id"] as? String,
                       let name = record["display_name"] as? String {
                        names[uid] = name
                    }
                }
                requests = requests.map { req in
                    OutgoingFriendRequest(
                        id: req.id,
                        recordID: req.recordID,
                        recipientUserID: req.recipientUserID,
                        recipientName: names[req.recipientUserID] ?? req.recipientName
                    )
                }
            }

            outgoingPendingRequests = requests
        } catch {
            print("fetchOutgoingPendingRequests failed: \(error.localizedDescription)")
        }
    }

    // Accept an incoming friend request — sets status to "accepted".
    func acceptFriendRequest(_ request: FriendRequest) async throws {
        do {
            let record = try await database.record(for: request.recordID)
            record["status"]     = "accepted"
            record["updated_at"] = Date()
            _ = try await database.save(record)
            await MainActor.run {
                pendingRequests.removeAll { $0.id == request.id }
            }
            await fetchOutgoingPendingRequests()
            print("Accepted friend request from \(request.requesterName)")
            Task { @MainActor in await refreshFriendsNow(reason: "accept") }
        } catch {
            print("acceptFriendRequest failed: \(error.localizedDescription)")
            throw error
        }
    }

    // Accepts a reciprocal pending request when the other person already added me.
    // This lets contact suggestions behave like "add back" instead of getting stuck
    // as a local-only pending request.
    func acceptPendingIncomingFriendRequest(fromUserID userID: String) async throws -> Bool {
        guard !myID.isEmpty else { return false }

        let predicate = NSPredicate(
            format: "requester_user_id == %@ AND recipient_user_id == %@ AND status == 'pending'",
            userID,
            myID
        )
        let query = CKQuery(recordType: "Friendship", predicate: predicate)
        let (results, _) = try await database.records(matching: query, resultsLimit: 1)

        guard let record = results.compactMap({ _, result in
            if case .success(let record) = result { return record }
            return nil
        }).first else {
            return false
        }

        record["status"] = "accepted"
        record["updated_at"] = Date()
        _ = try await database.save(record)

        let outgoingPredicate = NSPredicate(
            format: "requester_user_id == %@ AND recipient_user_id == %@ AND status == 'pending'",
            myID,
            userID
        )
        let outgoingQuery = CKQuery(recordType: "Friendship", predicate: outgoingPredicate)
        let (outgoingResults, _) = try await database.records(matching: outgoingQuery)
        let outgoingRecords = outgoingResults.compactMap { _, result in
            if case .success(let record) = result { return record }
            return nil
        }
        for outgoingRecord in outgoingRecords {
            outgoingRecord["status"] = "accepted"
            outgoingRecord["updated_at"] = Date()
            _ = try await database.save(outgoingRecord)
        }

        await MainActor.run {
            pendingRequests.removeAll { $0.requesterUserID == userID }
            outgoingPendingRequests.removeAll { $0.recipientUserID == userID }
        }
        await fetchOutgoingPendingRequests()
        Task { @MainActor in await refreshFriendsNow(reason: "accept-reciprocal") }
        return true
    }

    // Decline or remove — sets status to "rejected".
    func declineFriendRequest(_ request: FriendRequest) async throws {
        do {
            let record = try await database.record(for: request.recordID)
            record["status"]     = "rejected"
            record["updated_at"] = Date()
            _ = try await database.save(record)
            await MainActor.run {
                pendingRequests.removeAll { $0.id == request.id }
            }
            print("Declined friend request from \(request.requesterName)")
        } catch {
            print("declineFriendRequest failed: \(error.localizedDescription)")
            throw error
        }
    }

    // Remove an accepted friend from the leaderboard by marking the friendship as removed.
    func removeFriend(userID friendUserID: String) async throws {
        let sentQuery = CKQuery(recordType: "Friendship",
            predicate: NSPredicate(format: "requester_user_id == %@ AND recipient_user_id == %@ AND status == 'accepted'", myID, friendUserID))
        let receivedQuery = CKQuery(recordType: "Friendship",
            predicate: NSPredicate(format: "requester_user_id == %@ AND recipient_user_id == %@ AND status == 'accepted'", friendUserID, myID))

        let (sentResults, _) = try await database.records(matching: sentQuery)
        let (receivedResults, _) = try await database.records(matching: receivedQuery)
        let records = (sentResults + receivedResults).compactMap { _, result in
            if case .success(let record) = result { return record }
            return nil
        }

        guard !records.isEmpty else { throw FriendError.notFriends }

        for record in records {
            record["status"] = "removed"
            record["updated_at"] = Date()
            _ = try await database.save(record)
        }

        await MainActor.run {
            friends.removeAll { $0.userID == friendUserID }
            cacheLeaderboardData(forceWidgetReload: true)
        }
        print("Removed friend \(friendUserID)")
    }

    enum FriendError: LocalizedError {
        case alreadyExists
        case notFriends
        var errorDescription: String? {
            switch self {
            case .alreadyExists: return "You already have a friendship or pending request with this person."
            case .notFriends: return "That friend connection was already removed or could not be found."
            }
        }
    }

    private func markFriendshipsRemoved(for userID: String) async throws {
        let sentQuery = CKQuery(recordType: "Friendship",
            predicate: NSPredicate(format: "requester_user_id == %@", userID))
        let receivedQuery = CKQuery(recordType: "Friendship",
            predicate: NSPredicate(format: "recipient_user_id == %@", userID))

        let (sentResults, _) = try await database.records(matching: sentQuery)
        let (receivedResults, _) = try await database.records(matching: receivedQuery)
        let records = (sentResults + receivedResults).compactMap { _, result in
            if case .success(let record) = result { return record }
            return nil
        }

        for record in records {
            guard record["status"] as? String != "removed" else { continue }
            record["status"] = "removed"
            record["updated_at"] = Date()
            _ = try await database.save(record)
        }
    }

    // MARK: - Friend Request Push Subscription

    // Registers a CloudKit subscription that fires a silent push whenever someone
    // sends this user a friend request. Guarded by a UserDefaults flag so it only
    // saves to CloudKit once per user ID — subsequent calls are instant no-ops.
    func registerFriendRequestSubscription() async {
        guard !myID.isEmpty else { return }

        let flagKey = "friendRequestSubRegistered-\(myID)"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        let attemptKey = "friendRequestSubLastAttempt-\(myID)"
        let now = Date()
        if let lastAttempt = UserDefaults.standard.object(forKey: attemptKey) as? Date,
           now.timeIntervalSince(lastAttempt) < Self.friendRequestSubscriptionRetryInterval {
            return
        }
        UserDefaults.standard.set(now, forKey: attemptKey)

        let predicate = NSPredicate(
            format: "recipient_user_id == %@ AND status == 'pending'",
            myID
        )
        let subscription = CKQuerySubscription(
            recordType: "Friendship",
            predicate: predicate,
            subscriptionID: "friend-request-incoming-\(myID)",
            options: .firesOnRecordCreation
        )

        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true   // silent push — app wakes to fire a local notification
        info.desiredKeys = ["requester_user_id"] // include sender ID in the push payload
        subscription.notificationInfo = info

        do {
            _ = try await database.save(subscription)
            UserDefaults.standard.set(true, forKey: flagKey)
        } catch {
            print("registerFriendRequestSubscription failed: \(error)")
        }
    }

    // Fetches the display name for a given user ID. Used by the app delegate to
    // personalise the friend-request push notification.
    func fetchDisplayName(forUserID userID: String) async -> String? {
        guard !userID.isEmpty else { return nil }
        let predicate = NSPredicate(format: "user_id == %@", userID)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        do {
            let (results, _) = try await database.records(matching: query, resultsLimit: 1)
            for (_, result) in results {
                if case .success(let record) = result {
                    return record["display_name"] as? String
                }
            }
        } catch {
            print("fetchDisplayName failed: \(error)")
        }
        return nil
    }

    // MARK: - Duplicate Cleanup

    private func cleanupMyDuplicateProfiles() async throws {
        let query = CKQuery(recordType: "UserProfile", predicate: NSPredicate(format: "user_id == %@", myID))
        let (matchResults, _) = try await database.records(matching: query)
        let records: [CKRecord] = matchResults.compactMap {
            if case .success(let r) = $0.1 { return r }
            return nil
        }
        let toDelete = records.map(\.recordID).filter { $0 != myUserProfileRecordID }
        guard !toDelete.isEmpty else { return }
        print("Deleting \(toDelete.count) duplicate profile(s)")
        for recordID in toDelete {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                database.delete(withRecordID: recordID) { _, error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
        }
    }

    private func dedupeMembers(_ members: [MemberData]) -> [MemberData] {
        var byUserID: [String: MemberData] = [:]
        for member in members {
            if let existing = byUserID[member.userID] {
                if member.lastUpdate > existing.lastUpdate { byUserID[member.userID] = member }
            } else {
                byUserID[member.userID] = member
            }
        }
        return Array(byUserID.values).sorted { $0.blocks > $1.blocks }
    }

    // MARK: - Background Sync

    func performBackgroundCheckDetailed() async -> (success: Bool, errorMessage: String?, ckErrorCode: Int?, retryAfterSeconds: Double?) {
        guard !myDisplayName.isEmpty else {
            return (false, "Display name not set", nil, nil)
        }

        do {
            let status = try await container.accountStatus()
            switch status {
            case .available: break
            case .noAccount:
                return (false, "No iCloud account signed in", Int(CKError.Code.notAuthenticated.rawValue), nil)
            default:
                return (false, "iCloud unavailable", nil, nil)
            }
        } catch {
            return (false, "iCloud status check failed: \(error.localizedDescription)", nil, nil)
        }

        do {
            try await saveProfileToCloud()
            return (true, nil, nil, nil)
        } catch {
            let retryAfter = (error as? CKError)?.userInfo[CKErrorRetryAfterKey] as? Double
            let code = (error as? CKError)?.code.rawValue
            print("Background sync failed: \(error.localizedDescription)")
            return (false, error.localizedDescription, code, retryAfter)
        }
    }

    // MARK: - Caching

    private func cacheLeaderboardData(forceWidgetReload: Bool = false) {
        if let encoded = try? CloudKitManager.jsonEncoder.encode(friends) {
            sharedDefaults?.set(encoded, forKey: AppConstants.Keys.cachedLeaderboardData)
        }
        #if canImport(WidgetKit)
        #if canImport(UIKit)
        let isForeground = UIApplication.shared.applicationState == .active
        #else
        let isForeground = false
        #endif
        let now = Date()
        if forceWidgetReload {
            lastWidgetReload = now
            WidgetCenter.shared.reloadTimelines(ofKind: "ScreenMatesGroupWidget")
            return
        }
        let throttle = isForeground ? widgetReloadThrottleForeground : widgetReloadThrottleBackground
        if now.timeIntervalSince(lastWidgetReload) >= throttle {
            lastWidgetReload = now
            WidgetCenter.shared.reloadTimelines(ofKind: "ScreenMatesGroupWidget")
        }
        #endif
    }

    private func loadCachedData() {
        if let data = sharedDefaults?.data(forKey: AppConstants.Keys.cachedLeaderboardData),
           let cached = try? CloudKitManager.jsonDecoder.decode([MemberData].self, from: data) {
            self.friends = cached
            print("Loaded \(cached.count) cached friends from disk")
        }
    }

    private func clearCache() {
        sharedDefaults?.removeObject(forKey: AppConstants.Keys.cachedLeaderboardData)
    }

    // MARK: - Error Handling

    private func handleCloudKitError(_ error: Error) -> ErrorHandler.AppError {
        let ckError = error as? CKError
        switch ckError?.code {
        case .networkUnavailable, .networkFailure:
            return .networkError
        case .notAuthenticated:
            return .cloudKitError("Please sign in to iCloud in Settings")
        case .quotaExceeded:
            return .cloudKitError("iCloud storage quota exceeded")
        default:
            return .cloudKitError(error.localizedDescription)
        }
    }

    // MARK: - Debug Helpers

    var currentBlocksUsed: Int {
        sharedDefaults?.integer(forKey: AppConstants.Keys.dailyBlocksUsed) ?? 0
    }

    func forceSyncNow() {
        Task { @MainActor in await refreshFriendsNow(reason: "manual") }
    }

    func resetMyCountToZero(completion: (() -> Void)? = nil) {
        sharedDefaults?.set(0, forKey: AppConstants.Keys.dailyBlocksUsed)
        sharedDefaults?.set(0, forKey: AppConstants.Keys.lastThresholdIndex)
        sharedDefaults?.set(0, forKey: AppConstants.Keys.lastAutoBatchRolloverIndex)
        print("Reset local block count to 0 - uploading to CloudKit...")

        Task {
            do {
                try await saveProfileToCloud(blocks: 0)
                print("Reset uploaded to CloudKit")
                await self.refreshFriendsNow(reason: "reset")
            } catch {
                print("Reset upload failed: \(error.localizedDescription)")
            }
            completion?()
        }
    }

    func resetAllData() {
        resetLocalAccountState(regenerateUserID: false)
        print("🗑️ All data reset")
    }

    private func resetLocalAccountState(regenerateUserID: Bool) {
        if regenerateUserID {
            KeychainStore.deleteStableUserID()
            myID = KeychainStore.getOrCreateStableUserID()
        }

        myGroupID = ""
        myDisplayName = ""
        isSetupDone = false
        usernameSet = false
        friends = []
        pendingRequests = []
        outgoingPendingRequests = []
        myPersonalGoalMinutes = 0
        UserDefaults.standard.removeObject(forKey: AppConstants.Keys.myPersonalGoalMinutes)
        clearCache()
        sharedDefaults?.removeObject(forKey: AppConstants.Keys.dailyBlocksUsed)
        sharedDefaults?.removeObject(forKey: AppConstants.Keys.lastBlockDate)
        PhoneAuthManager.shared.resetAuthState()
        mirrorIdentityToAppGroup()
    }

    // MARK: - Legacy Group Methods (kept for debug/settings compatibility — Task 4 removes these)

    func ensureGroupSubscription() {
        // Groups replaced by friendships — subscription model pending Task 4 cleanup
    }

    func leaveGroup() {
        myGroupID = ""
        friends = []
        myPersonalGoalMinutes = 0
        UserDefaults.standard.removeObject(forKey: AppConstants.Keys.myPersonalGoalMinutes)
        mirrorIdentityToAppGroup()
        clearCache()
    }

    func createGroup(completion: @escaping (Result<String, ErrorHandler.AppError>) -> Void) {
        completion(.failure(.cloudKitError("Groups have been replaced with friendships.")))
    }

    func validateGroup(_ groupID: String, completion: @escaping (Result<SocialGroup, ErrorHandler.AppError>) -> Void) {
        completion(.failure(.groupNotFound))
    }

    func joinGroup(groupID: String) { }

    func fetchGroupData(useCache: Bool = true) {
        Task { @MainActor in await refreshFriendsNow(reason: "compat") }
    }

    // GroupMembersAsync backward-compat — background task in screenmatesApp calls this.
    func fetchGroupMembersAsync() async throws -> [MemberData] {
        try await fetchFriendsAsync()
    }
}
