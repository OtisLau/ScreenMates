import CloudKit
import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

// Handles everything CloudKit: saving your profile, fetching your group's data,
// background sync, and real-time push subscriptions.
class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()

    // MARK: - CloudKit
    let container = CKContainer(identifier: AppConstants.cloudKitContainerID)
    lazy var database = container.publicCloudDatabase

    // MARK: - Who am I?
    // These are persisted across app launches via @AppStorage (UserDefaults).
    @AppStorage("my_user_id") var myID: String = ""
    @AppStorage("my_display_name") var myDisplayName: String = ""
    @AppStorage("my_group_id") var myGroupID: String = ""
    @AppStorage("is_setup_done") var isSetupDone: Bool = false
    @AppStorage("username_set") var usernameSet: Bool = false

    // Shared group daily limit — synced from the SocialGroup CloudKit record.
    @Published var groupGoalMinutes: Int = 0
    private var lastGoalUpdateTime: Date = .distantPast

    // Tracks which group we last subscribed to so we don't re-subscribe every launch
    @AppStorage("last_subscription_group_id") private var lastSubscriptionGroupID: String = ""

    // MARK: - UI State
    @Published var groupMembers: [MemberData] = []
    @Published var isLoading = false
    @Published var lastError: ErrorHandler.AppError?
    @Published var lastSyncTime: Date?

    // Shared storage accessible by the ScreenTimeMonitor extension and widget
    private let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)

    // Reusable encoder/decoder — avoids repeated allocation on every cache read/write
    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder = JSONDecoder()

    // Throttle widget timeline reloads to avoid OOM-killing the widget process.
    // Use a faster cadence while app is active and a slower one in background.
    private var lastWidgetReload: Date = .distantPast
    private let widgetReloadThrottleForeground: TimeInterval = 30        // 30 seconds
    private let widgetReloadThrottleBackground: TimeInterval = 15 * 60   // 15 minutes

    // The CloudKit record ID for this user — always the same so we never create duplicates.
    // Computed lazily from myID; CKRecord.ID is cheap but no need to reallocate on every access.
    private var myUserProfileRecordID: CKRecord.ID {
        CKRecord.ID(recordName: myID)
    }

    private init() {
        // On first launch, generate a stable user ID stored in Keychain.
        // This survives app reinstalls so the same person never gets two CloudKit records.
        if myID.isEmpty {
            myID = KeychainStore.getOrCreateStableUserID()
        } else {
            KeychainStore.saveStableUserID(myID)
        }

        loadCachedData()
        mirrorIdentityToAppGroup()
        groupGoalMinutes = UserDefaults.standard.integer(forKey: "cached_group_goal_minutes")
    }

    // Copy identity and config into shared App Group storage so the background extension can read it
    // (extensions can't access @AppStorage or AppConstants from the main app target directly).
    private func mirrorIdentityToAppGroup() {
        sharedDefaults?.set(myID, forKey: AppConstants.Keys.sharedUserID)
        sharedDefaults?.set(myDisplayName, forKey: AppConstants.Keys.sharedDisplayName)
        sharedDefaults?.set(myGroupID, forKey: AppConstants.Keys.sharedGroupID)
        sharedDefaults?.set(AppConstants.currentBlockSize, forKey: AppConstants.Keys.sharedBlockSizeMinutes)
        sharedDefaults?.set(groupGoalMinutes, forKey: AppConstants.Keys.sharedGoalMinutes)
    }

    // MARK: - CloudKit Subscriptions

    // Set up a silent push subscription so when any group member updates their data,
    // all other devices get woken up to refresh — without anyone needing to open the app.
    func ensureGroupSubscription() {
        guard !myGroupID.isEmpty else { return }
        guard myGroupID != lastSubscriptionGroupID else { return }

        let newGroupID = myGroupID

        // Delete the old subscription first so stale silent pushes stop arriving for
        // groups the user has left. CloudKit caps subscriptions at 400; orphaned ones
        // accumulate silently across group changes and reinstalls.
        if !lastSubscriptionGroupID.isEmpty {
            let oldSubscriptionID = "group-userprofile-\(lastSubscriptionGroupID)"
            database.delete(withSubscriptionID: oldSubscriptionID) { [weak self] _, error in
                if let error {
                    print(" Failed to delete old subscription '\(oldSubscriptionID)': \(error.localizedDescription)")
                } else {
                    print(" Deleted old subscription for group \(self?.lastSubscriptionGroupID ?? "")")
                }
            }
        }

        let subscriptionID = "group-userprofile-\(newGroupID)"
        let predicate = NSPredicate(format: "group_id == %@", newGroupID)

        let subscription = CKQuerySubscription(
            recordType: "UserProfile",
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )

        // Silent push = wakes the app in the background without showing a notification to the user
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info

        database.save(subscription) { [weak self] _, error in
            if let error {
                print(" CloudKit subscription failed: \(error.localizedDescription)")
                return
            }
            print(" Subscribed to group \(newGroupID)")
            DispatchQueue.main.async { [weak self] in
                self?.lastSubscriptionGroupID = newGroupID
            }
        }
    }

    // MARK: - Group Management

    // Create a new group and save it to CloudKit. Returns the 6-char group code.
    func createGroup(completion: @escaping (Result<String, ErrorHandler.AppError>) -> Void) {
        let newGroupID = UUID().uuidString.prefix(6).uppercased()
        let group = SocialGroup(recordID: CKRecord.ID(recordName: newGroupID), groupID: newGroupID)
        let record = group.toCKRecord()

        isLoading = true

        database.save(record) { [weak self] _, error in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isLoading = false

                if let error = error {
                    let appError = self.handleCloudKitError(error)
                    self.lastError = appError
                    completion(.failure(appError))
                } else {
                    self.myGroupID = newGroupID
                    self.mirrorIdentityToAppGroup()
                    self.updateMyProfile()
                    completion(.success(newGroupID))
                }
            }
        }
    }

    // Check that a group code actually exists in CloudKit before letting someone join
    func validateGroup(_ groupID: String, completion: @escaping (Result<SocialGroup, ErrorHandler.AppError>) -> Void) {
        isLoading = true

        let predicate = NSPredicate(format: "group_id == %@", groupID)
        let query = CKQuery(recordType: "SocialGroup", predicate: predicate)

        database.fetch(withQuery: query, inZoneWith: nil, resultsLimit: 1) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isLoading = false

                switch result {
                case .success(let (matchResults, _)):
                    if let firstMatch = matchResults.first,
                       case .success(let record) = firstMatch.1,
                       let group = SocialGroup.from(record) {
                        completion(.success(group))
                    } else {
                        self.lastError = .groupNotFound
                        completion(.failure(.groupNotFound))
                    }
                case .failure(let error):
                    let appError = self.handleCloudKitError(error)
                    self.lastError = appError
                    completion(.failure(appError))
                }
            }
        }
    }

    // Join a group: save the group ID locally, sync to the extension, subscribe to updates
    func joinGroup(groupID: String) {
        myGroupID = groupID
        mirrorIdentityToAppGroup()
        ensureGroupSubscription()
        updateMyProfile()
    }

    // Leave the current group and wipe all local state
    func leaveGroup() {
        myGroupID = ""
        groupMembers = []
        groupGoalMinutes = 0
        UserDefaults.standard.removeObject(forKey: "cached_group_goal_minutes")
        mirrorIdentityToAppGroup()
        clearCache()
        lastSubscriptionGroupID = ""
    }

    // MARK: - Group Goal (shared daily limit)

    // Fetch the group's shared daily limit from CloudKit
    func fetchGroupGoal() {
        guard !myGroupID.isEmpty else { return }
        let predicate = NSPredicate(format: "group_id == %@", myGroupID)
        let query = CKQuery(recordType: "SocialGroup", predicate: predicate)

        database.fetch(withQuery: query, inZoneWith: nil, resultsLimit: 1) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if case .success(let (matchResults, _)) = result,
                   let firstMatch = matchResults.first,
                   case .success(let record) = firstMatch.1 {
                    let fetched = record["goal_minutes"] as? Int ?? 0
                    // Skip if we just saved a local goal — wait for CloudKit to propagate
                    guard Date().timeIntervalSince(self.lastGoalUpdateTime) > 10 else { return }
                    self.groupGoalMinutes = fetched
                    // Persist locally so it shows instantly on next launch
                    UserDefaults.standard.set(fetched, forKey: "cached_group_goal_minutes")
                    self.sharedDefaults?.set(fetched, forKey: AppConstants.Keys.sharedGoalMinutes)
                }
            }
        }
    }

    // Update the daily limit locally and (if in a group) in CloudKit.
    func updateGroupGoal(_ minutes: Int) {
        groupGoalMinutes = minutes
        lastGoalUpdateTime = Date()
        UserDefaults.standard.set(minutes, forKey: "cached_group_goal_minutes")
        sharedDefaults?.set(minutes, forKey: AppConstants.Keys.sharedGoalMinutes)

        guard !myGroupID.isEmpty else { return }
        let recordID = CKRecord.ID(recordName: myGroupID)
        database.fetch(withRecordID: recordID) { [weak self] record, error in
            guard let self else { return }
            guard let record else {
                print(" Group record not found for goal update")
                return
            }
            record["goal_minutes"] = minutes
            self.database.save(record) { _, error in
                if let error {
                    print(" Group goal save failed: \(error.localizedDescription)")
                } else {
                    print(" Group goal saved: \(minutes) min")
                }
            }
        }
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

        record["user_id"] = myID
        record["display_name"] = myDisplayName
        record["group_id"] = myGroupID
        record["blocks_used"] = currentBlocks
        record["post_midnight_blocks"] = postMidnightBlocks
        record["last_updated"] = Date()
        record["last_active_date"] = Date()
        if !phoneHash.isEmpty { record["phone_hash"] = phoneHash }

        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Conflict — re-fetch and retry once
            let latest = try await database.record(for: myUserProfileRecordID)
            latest["user_id"] = myID
            latest["display_name"] = myDisplayName
            latest["group_id"] = myGroupID
            latest["blocks_used"] = currentBlocks
            latest["post_midnight_blocks"] = postMidnightBlocks
            latest["last_updated"] = Date()
            latest["last_active_date"] = Date()
            if !phoneHash.isEmpty { latest["phone_hash"] = phoneHash }
            _ = try await database.save(latest)
        }

        await MainActor.run { lastSyncTime = Date() }
        print(" Profile saved: \(currentBlocks) blocks")
    }

    // Save this user's current screen time to CloudKit so their group can see it.
    func updateMyProfile(completion: (() -> Void)? = nil) {
        mirrorIdentityToAppGroup()

        guard !myDisplayName.isEmpty else {
            print(" Skipping profile update — display name not set yet")
            completion?()
            return
        }

        Task {
            do {
                try await saveProfileToCloud()
            } catch {
                print(" Profile save failed: \(error.localizedDescription)")
            }
            completion?()
        }
    }

    // MARK: - Fetching Group Data

    // Pull the latest screen time data for everyone in the group from CloudKit
    func fetchGroupData(useCache: Bool = true) {
        guard !myGroupID.isEmpty else { return }

        isLoading = true
        let refreshingGroupID = myGroupID

        Task { @MainActor in
            defer { isLoading = false }
            do {
                let members = try await fetchGroupMembersAsync()
                guard refreshingGroupID == myGroupID else {
                    print(" Discarding stale fetch results — group changed mid-fetch")
                    return
                }
                groupMembers = members
                lastSyncTime = Date()
                cacheLeaderboardData()
                print(" Fetched \(members.count) group members")
            } catch {
                print(" Fetch failed: \(error.localizedDescription)")
                lastError = handleCloudKitError(error)
            }
        }
    }

    // Full refresh: update your own profile then fetch everyone else's.
    // Called by pull-to-refresh, the 60-second timer, and incoming silent pushes.
    //
    // Silent pushes mean "a group member's record changed — go fetch."
    // We must NOT upload our own profile in response: doing so triggers another push,
    // which triggers another upload, creating an infinite feedback loop that hammers
    // CloudKit until it activates error-rate mitigation.
    @MainActor
    func refreshGroupNow(reason: String? = nil) async {
        // Snapshot the group ID at the start of the refresh. If the user leaves the group
        // while the CloudKit fetch is in-flight, we discard the stale results instead of
        // writing them back to groupMembers (which was already cleared by leaveGroup()).
        let refreshingGroupID = myGroupID
        guard !refreshingGroupID.isEmpty else { return }
        print(" Refreshing group (\(reason ?? ""))")

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
            let members = try await fetchGroupMembersAsync()
            // Only apply results if we're still in the same group we started refreshing for.
            guard myGroupID == refreshingGroupID else {
                print(" Discarding stale fetch results — group changed mid-refresh")
                return
            }
            groupMembers = members
            lastSyncTime = Date()
            let forceWidgetReload = reason == "pull-to-refresh" || reason == "manual" || reason == "appear"
            cacheLeaderboardData(forceWidgetReload: forceWidgetReload)
            fetchGroupGoal()

            // Evaluate notification scenarios after every group refresh
            NotificationManager.shared.evaluateAndSchedule(
                groupMembers: members,
                myUserID: myID,
                goalMinutes: groupGoalMinutes
            )
        } catch {
            lastError = handleCloudKitError(error)
        }
    }

    func fetchGroupMembersAsync() async throws -> [MemberData] {
        let predicate = NSPredicate(format: "group_id == %@", myGroupID)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "blocks_used", ascending: false)]

        let (matchResults, _) = try await database.records(matching: query)
        var members: [MemberData] = []

        for (_, result) in matchResults {
            if case .success(let record) = result {
                let userID = record["user_id"] as? String ?? record.recordID.recordName
                members.append(MemberData(
                    userID: userID,
                    displayName: record["display_name"] as? String ?? userID,
                    blocks: record["blocks_used"] as? Int ?? 0,
                    lastUpdate: record["last_updated"] as? Date ?? Date(),
                    postMidnightBlocks: record["post_midnight_blocks"] as? Int ?? 0
                ))
            }
        }

        return dedupeMembers(members)
    }

    // Fetch UserProfile records whose phone_hash matches any of the provided hashes.
    // Used by ContactsPermissionView to discover which contacts are on ScreenMates.
    func fetchUsersByPhoneHashes(_ hashes: [String]) async throws -> [(userID: String, displayName: String, phoneHash: String)] {
        guard !hashes.isEmpty else { return [] }
        let predicate = NSPredicate(format: "phone_hash IN %@", hashes)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        let (matchResults, _) = try await database.records(matching: query)
        return matchResults.compactMap { _, result in
            guard case .success(let record) = result,
                  let userID      = record["user_id"]      as? String,
                  let displayName = record["display_name"] as? String,
                  let phoneHash   = record["phone_hash"]   as? String
            else { return nil }
            return (userID: userID, displayName: displayName, phoneHash: phoneHash)
        }
    }

    // Remove old duplicate CloudKit records created by earlier builds or reinstalls
    private func cleanupMyDuplicateProfiles() async throws {
        // Only operate on records that explicitly belong to this user ID.
        // Never match by display name; multiple users can legitimately share a name.
        let query = CKQuery(recordType: "UserProfile", predicate: NSPredicate(format: "user_id == %@", myID))
        let (matchResults, _) = try await database.records(matching: query)
        let records: [CKRecord] = matchResults.compactMap {
            if case .success(let r) = $0.1 { return r }
            return nil
        }

        // Keep the record whose name matches our stable user ID, delete everything else
        let toDelete = records.map(\.recordID).filter { $0 != myUserProfileRecordID }
        guard !toDelete.isEmpty else { return }

        print(" Deleting \(toDelete.count) duplicate profile(s)")
        for recordID in toDelete {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                database.delete(withRecordID: recordID) { _, error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
        }
    }

    // If multiple CloudKit records exist for the same user ID, keep only the most recent one.
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

    // Called by the 15-minute background task while the app is closed.
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
            print(" Background sync failed: \(error.localizedDescription)")
            return (false, error.localizedDescription, code, retryAfter)
        }
    }

    // MARK: - Caching

    // Save the group member list to App Group storage so the widget can read it
    // without needing to hit CloudKit directly.
    private func cacheLeaderboardData(forceWidgetReload: Bool = false) {
        if let encoded = try? CloudKitManager.jsonEncoder.encode(groupMembers) {
            sharedDefaults?.set(encoded, forKey: AppConstants.Keys.cachedLeaderboardData)
        }
        // Throttle widget reloads dynamically:
        // - active app: faster updates for visible UX
        // - background app: conservative cadence for battery/stability
        // Widget still has its own 15-minute timeline fallback.
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

    // Load cached group data on launch so the UI shows something instantly
    private func loadCachedData() {
        if let data = sharedDefaults?.data(forKey: AppConstants.Keys.cachedLeaderboardData),
           let cached = try? CloudKitManager.jsonDecoder.decode([MemberData].self, from: data) {
            self.groupMembers = cached
            print(" Loaded \(cached.count) cached members from disk")
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
        Task { @MainActor in await refreshGroupNow(reason: "manual") }
    }

    // Zero out this user's block count locally and push 0 to CloudKit immediately.
    func resetMyCountToZero(completion: (() -> Void)? = nil) {
        sharedDefaults?.set(0, forKey: AppConstants.Keys.dailyBlocksUsed)
        sharedDefaults?.set(0, forKey: AppConstants.Keys.lastThresholdIndex)
        sharedDefaults?.set(0, forKey: AppConstants.Keys.lastAutoBatchRolloverIndex)
        print(" Reset local block count to 0 — uploading to CloudKit...")

        Task {
            do {
                try await saveProfileToCloud(blocks: 0)
                print(" Reset uploaded to CloudKit")
                await MainActor.run { [weak self] in
                    Task { await self?.refreshGroupNow(reason: "reset") }
                }
            } catch {
                print(" Reset upload failed: \(error.localizedDescription)")
            }
            completion?()
        }
    }

    func resetAllData() {
        myGroupID = ""
        myDisplayName = ""
        isSetupDone = false
        usernameSet = false
        groupMembers = []
        clearCache()
        sharedDefaults?.removeObject(forKey: AppConstants.Keys.dailyBlocksUsed)
        sharedDefaults?.removeObject(forKey: AppConstants.Keys.lastBlockDate)
        print(" All data reset")
    }
}
