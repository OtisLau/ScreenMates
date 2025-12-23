import CloudKit
import SwiftUI
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Manages all CloudKit operations with error handling, caching, and retry logic
class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()
    
    // MARK: - CloudKit Setup
    let container = CKContainer(identifier: AppConstants.cloudKitContainerID)
    lazy var database = container.publicCloudDatabase
    
    // MARK: - Local Storage
    // NOTE: Use Keychain-backed stable ID so reinstall doesn't create a new Cloud identity.
    @AppStorage("my_user_id") var myID: String = ""
    @AppStorage("my_display_name") var myDisplayName: String = ""
    @AppStorage("my_group_id") var myGroupID: String = ""
    @AppStorage("is_setup_done") var isSetupDone: Bool = false
    @AppStorage("username_set") var usernameSet: Bool = false
    @AppStorage("last_subscription_group_id") private var lastSubscriptionGroupID: String = ""
    
    // MARK: - Published State
    @Published var groupMembers: [MemberData] = []
    @Published var currentGroup: SocialGroup? {
        didSet {
            // Mirror goal into App Group so the extension can use it for notifications.
            if let goal = currentGroup?.dailyGoalBlocks {
                sharedDefaults?.set(goal, forKey: AppConstants.Keys.sharedDailyGoalBlocks)
            }
        }
    }
    @Published var isLoading = false
    @Published var lastError: ErrorHandler.AppError?
    @Published var lastSyncTime: Date?
    
    private let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)

    /// Stable record ID so each device overwrites its own profile record (prevents duplicates).
    private var myUserProfileRecordID: CKRecord.ID {
        CKRecord.ID(recordName: myID)
    }
    
    private init() {
        // Hydrate/stabilize myID on first launch (Keychain survives reinstalls).
        if myID.isEmpty {
            myID = KeychainStore.getOrCreateStableUserID()
        } else {
            // Ensure Keychain also has the value so future reinstalls keep it.
            KeychainStore.saveStableUserID(myID)
        }

        loadCachedData()
        mirrorIdentityToAppGroup()
    }

    /// Make identity available to the ScreenTimeMonitor extension (which only has App Group storage).
    private func mirrorIdentityToAppGroup() {
        sharedDefaults?.set(myID, forKey: AppConstants.Keys.sharedUserID)
        sharedDefaults?.set(myDisplayName, forKey: AppConstants.Keys.sharedDisplayName)
        sharedDefaults?.set(myGroupID, forKey: AppConstants.Keys.sharedGroupID)
        sharedDefaults?.set(AppConstants.currentBlockSize, forKey: AppConstants.Keys.sharedBlockSizeMinutes)
    }

    // MARK: - CloudKit Subscriptions (silent pushes)

    /// Creates/updates a CloudKit query subscription so devices can receive silent pushes when
    /// any `UserProfile` in this group changes. iOS may wake the app to refresh cached data,
    /// reducing the need to manually open the app to see updates.
    func ensureGroupSubscription() {
        guard !myGroupID.isEmpty else { return }
        guard myGroupID != lastSubscriptionGroupID else { return }

        let subscriptionID = "group-userprofile-\(myGroupID)"
        let predicate = NSPredicate(format: "group_id == %@", myGroupID)

        let subscription = CKQuerySubscription(
            recordType: "UserProfile",
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )

        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true // silent push
        subscription.notificationInfo = info

        database.save(subscription) { _, error in
            if let error {
                print("❌ Failed to save CloudKit subscription: \(error.localizedDescription)")
                return
            }
            print("✅ CloudKit subscription saved for group \(self.myGroupID)")
            DispatchQueue.main.async {
                self.lastSubscriptionGroupID = self.myGroupID
            }
        }
    }
    
    // MARK: - Group Management
    
    /// Create a new group with retry logic
    func createGroup(completion: @escaping (Result<String, ErrorHandler.AppError>) -> Void) {
        let newGroupID = UUID().uuidString.prefix(6).uppercased()
        // Use a stable record name (groupID) so we never create duplicate group records on retries.
        let group = SocialGroup(recordID: CKRecord.ID(recordName: newGroupID), groupID: newGroupID)
        let record = group.toCKRecord()
        
        isLoading = true
        
        self.database.save(record) { _, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    let appError = self.handleCloudKitError(error)
                    self.lastError = appError
                    completion(.failure(appError))
                } else {
                    self.myGroupID = newGroupID
                    self.currentGroup = group
                    completion(.success(newGroupID))
                    
                    // Create user profile after group creation
                    self.updateMyProfile()
                }
            }
        }
    }
    
    /// Validate that a group exists before joining
    func validateGroup(_ groupID: String, completion: @escaping (Result<SocialGroup, ErrorHandler.AppError>) -> Void) {
        isLoading = true
        
        let predicate = NSPredicate(format: "group_id == %@", groupID)
        let query = CKQuery(recordType: "SocialGroup", predicate: predicate)
        
        self.database.fetch(withQuery: query, inZoneWith: nil, resultsLimit: 1) { result in
            DispatchQueue.main.async {
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
    
    /// Join a group after validation
    func joinGroup(groupID: String) {
        self.myGroupID = groupID
        mirrorIdentityToAppGroup()
        ensureGroupSubscription()
        updateMyProfile()
    }
    
    /// Leave current group
    func leaveGroup() {
        myGroupID = ""
        currentGroup = nil
        groupMembers = []
        mirrorIdentityToAppGroup()
        clearCache()
        lastSubscriptionGroupID = ""
    }
    
    // MARK: - User Profile Management
    
    /// Update user profile with current data
    func updateMyProfile(completion: (() -> Void)? = nil) {
        print("📤 updateMyProfile called")
        print("   - User ID: \(myID)")
        print("   - Display Name: \(myDisplayName)")
        print("   - Group ID: \(myGroupID)")

        // Keep extension identity in sync.
        mirrorIdentityToAppGroup()
        
        guard !myDisplayName.isEmpty else {
            print("⚠️ Display name not set, skipping profile update")
            print("   ❌ This is why you're not showing in leaderboard!")
            completion?()
            return
        }
        
        let currentBlocks = sharedDefaults?.integer(forKey: AppConstants.Keys.dailyBlocksUsed) ?? 0
        let currentStreak = StreakManager.shared.currentStreak
        
        print("   - Blocks: \(currentBlocks)")
        print("   - Streak: \(currentStreak)")

        // Fetch-or-create using stable recordID (recordName == myID) so we don't create duplicates.
        database.fetch(withRecordID: myUserProfileRecordID) { record, error in
            let profileRecord: CKRecord
            if let record {
                profileRecord = record
            } else if let ckError = error as? CKError, ckError.code == .unknownItem {
                profileRecord = CKRecord(recordType: "UserProfile", recordID: self.myUserProfileRecordID)
            } else if let error {
                print("❌ Cloud: Profile Fetch Failed - \(error.localizedDescription)")
                completion?()
                return
            } else {
                profileRecord = CKRecord(recordType: "UserProfile", recordID: self.myUserProfileRecordID)
            }

            profileRecord["user_id"] = self.myID
            profileRecord["display_name"] = self.myDisplayName
            profileRecord["group_id"] = self.myGroupID
            profileRecord["blocks_used"] = currentBlocks
            profileRecord["streak"] = currentStreak
            profileRecord["last_updated"] = Date()
            profileRecord["last_active_date"] = Date()

            self.saveProfileWithRetry(profileRecord, attemptsRemaining: 2, completion: completion)
        }
    }

    private func saveProfileWithRetry(_ record: CKRecord, attemptsRemaining: Int, completion: (() -> Void)?) {
        database.save(record) { _, error in
            if let error = error as? CKError {
                // Common when app + extension update the same record around the same time.
                if error.code == .serverRecordChanged || error.code == .zoneBusy || error.code == .serviceUnavailable || error.code == .requestRateLimited {
                    let retryAfter = (error.userInfo[CKErrorRetryAfterKey] as? Double) ?? 0.5
                    if attemptsRemaining > 0 {
                        print("⚠️ Cloud: Save conflict (\(error.code.rawValue)). Retrying in \(retryAfter)s…")
                        DispatchQueue.global().asyncAfter(deadline: .now() + retryAfter) {
                            // Refetch latest server record then re-apply our fields and save again.
                            self.database.fetch(withRecordID: self.myUserProfileRecordID) { fetched, fetchError in
                                if let fetched = fetched {
                                    fetched["user_id"] = self.myID
                                    fetched["display_name"] = self.myDisplayName
                                    fetched["group_id"] = self.myGroupID
                                    fetched["blocks_used"] = self.sharedDefaults?.integer(forKey: AppConstants.Keys.dailyBlocksUsed) ?? 0
                                    fetched["streak"] = StreakManager.shared.currentStreak
                                    fetched["last_updated"] = Date()
                                    fetched["last_active_date"] = Date()
                                    self.saveProfileWithRetry(fetched, attemptsRemaining: attemptsRemaining - 1, completion: completion)
                                } else {
                                    if let fetchError {
                                        print("❌ Cloud: Retry fetch failed - \(fetchError.localizedDescription)")
                                    }
                                    completion?()
                                }
                            }
                        }
                        return
                    }
                }

                print("❌ Cloud: Profile Save Failed - \(error.localizedDescription)")
                completion?()
                return
            } else if let error {
                print("❌ Cloud: Profile Save Failed - \(error.localizedDescription)")
                completion?()
                return
            }

            print("✅ Cloud: Profile Saved (stable record)")
            DispatchQueue.main.async {
                self.lastSyncTime = Date()
            }
            completion?()
        }
    }
    
    // MARK: - Group Data Fetching
    
    /// Fetch leaderboard data for current group
    func fetchGroupData(useCache: Bool = true) {
        print("📥 fetchGroupData called")
        print("   - Group ID: \(myGroupID)")
        print("   - Use cache: \(useCache)")
        
        guard !myGroupID.isEmpty else {
            print("   ❌ Group ID is empty, aborting")
            return
        }
        
        // Show cached data immediately if available
        if useCache && !groupMembers.isEmpty {
            print("📦 Using cached leaderboard data")
        }
        
        isLoading = true
        
        let predicate = NSPredicate(format: "group_id == %@", myGroupID)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "blocks_used", ascending: false)]
        
        print("   🔍 Querying CloudKit for group: \(myGroupID)")
        
        self.database.fetch(withQuery: query, inZoneWith: nil, resultsLimit: 20) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let (matchResults, _)):
                    print("   📦 CloudKit returned \(matchResults.count) results")
                    
                    var newMembers: [MemberData] = []
                    
                    for match in matchResults {
                        if case .success(let record) = match.1 {
                            let userID = record["user_id"] as? String ?? "Unknown"
                            let displayName = record["display_name"] as? String ?? userID
                            let blocks = record["blocks_used"] as? Int ?? 0
                            let streak = record["streak"] as? Int ?? 0
                            let date = record["last_updated"] as? Date ?? Date()
                            
                            print("      - Found user: \(displayName) (\(blocks) blocks)")
                            
                            newMembers.append(MemberData(
                                userID: userID,
                                displayName: displayName,
                                blocks: blocks,
                                streak: streak,
                                lastUpdate: date
                            ))
                        }
                    }

                    let deduped = self.dedupeMembers(newMembers)

                    self.groupMembers = deduped
                    self.lastSyncTime = Date()
                    self.cacheLeaderboardData()
                    
                    print("   ✅ Fetched \(deduped.count) group members (deduped from \(newMembers.count))")
                    
                case .failure(let error):
                    print("   ❌ Fetch failed: \(error.localizedDescription)")
                    if let ckError = error as? CKError {
                        print("      CKError code: \(ckError.code.rawValue)")
                        print("      CKError: \(ckError)")
                    }
                    self.lastError = self.handleCloudKitError(error)
                }
            }
        }
    }

    // MARK: - Manual refresh (async)

    /// Full refresh pipeline (used by pull-to-refresh and silent pushes).
    @MainActor
    func refreshGroupNow(reason: String? = nil) async {
        if let reason {
            print("🔄 refreshGroupNow (\(reason))")
        } else {
            print("🔄 refreshGroupNow")
        }

        guard !myGroupID.isEmpty else {
            print("   ❌ Group ID is empty, aborting refresh")
            return
        }

        isLoading = true
        defer { isLoading = false }

        // 1) Ensure our own profile is current (stable recordID prevents future duplicates)
        await withCheckedContinuation { cont in
            updateMyProfile {
                cont.resume()
            }
        }

        // 2) Best-effort: delete any old duplicate profiles for *this* user (from older builds)
        do {
            try await cleanupMyDuplicateProfiles()
        } catch {
            print("⚠️ cleanupMyDuplicateProfiles failed: \(error.localizedDescription)")
        }

        // 3) Refresh group details + leaderboard
        do {
            if let group = try await fetchGroupDetailsAsync() {
                currentGroup = group
            }

            let members = try await fetchGroupMembersAsync()
            groupMembers = members
            lastSyncTime = Date()
            cacheLeaderboardData()
        } catch {
            lastError = handleCloudKitError(error)
        }
    }

    private func fetchGroupMembersAsync() async throws -> [MemberData] {
        let predicate = NSPredicate(format: "group_id == %@", myGroupID)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "blocks_used", ascending: false)]

        let (matchResults, _) = try await database.records(matching: query)
        var members: [MemberData] = []

        for (_, result) in matchResults {
            if case .success(let record) = result {
                let userID = record["user_id"] as? String ?? "Unknown"
                let displayName = record["display_name"] as? String ?? userID
                let blocks = record["blocks_used"] as? Int ?? 0
                let streak = record["streak"] as? Int ?? 0
                let date = record["last_updated"] as? Date ?? Date()

                members.append(
                    MemberData(
                        userID: userID,
                        displayName: displayName,
                        blocks: blocks,
                        streak: streak,
                        lastUpdate: date
                    )
                )
            }
        }

        return dedupeMembers(members)
    }

    private func fetchGroupDetailsAsync() async throws -> SocialGroup? {
        let predicate = NSPredicate(format: "group_id == %@", myGroupID)
        let query = CKQuery(recordType: "SocialGroup", predicate: predicate)

        let (matchResults, _) = try await database.records(matching: query)
        for (_, result) in matchResults {
            if case .success(let record) = result {
                return SocialGroup.from(record)
            }
        }
        return nil
    }

    private func cleanupMyDuplicateProfiles() async throws {
        // Clean up legacy duplicates created by older builds / reinstalls.
        // We try two angles:
        // 1) Any records with user_id == myID (should only be one with stable recordName)
        // 2) Any records in my current group with my display_name (common after reinstall when user_id changed)
        let predicate: NSPredicate
        if !myGroupID.isEmpty, !myDisplayName.isEmpty {
            predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "user_id == %@", myID),
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "group_id == %@", myGroupID),
                    NSPredicate(format: "display_name == %@", myDisplayName)
                ])
            ])
        } else {
            predicate = NSPredicate(format: "user_id == %@", myID)
        }

        let query = CKQuery(recordType: "UserProfile", predicate: predicate)

        let (matchResults, _) = try await database.records(matching: query)
        let records: [CKRecord] = matchResults.compactMap { (_, result) in
            if case .success(let record) = result { return record }
            return nil
        }

        // Keep the stable record (recordName == myID), delete everything else.
        let toDelete = records
            .map(\.recordID)
            .filter { $0 != myUserProfileRecordID }

        guard !toDelete.isEmpty else { return }

        print("🧹 Deleting \(toDelete.count) old duplicate UserProfile record(s) for me")
        for recordID in toDelete {
            _ = try await deleteRecordAsync(recordID: recordID)
        }
    }

    private func deleteRecordAsync(recordID: CKRecord.ID) async throws -> CKRecord.ID {
        try await withCheckedThrowingContinuation { cont in
            database.delete(withRecordID: recordID) { deletedID, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let deletedID {
                    cont.resume(returning: deletedID)
                } else {
                    cont.resume(throwing: ErrorHandler.AppError.unknown)
                }
            }
        }
    }

    private func dedupeMembers(_ members: [MemberData]) -> [MemberData] {
        // Dedupe by userID (old duplicates may already exist in CloudKit)
        var byUserID: [String: MemberData] = [:]
        for member in members {
            if let existing = byUserID[member.userID] {
                if member.lastUpdate > existing.lastUpdate {
                    byUserID[member.userID] = member
                }
            } else {
                byUserID[member.userID] = member
            }
        }

        // Secondary dedupe by display name to hide legacy duplicates caused by reinstalls/older builds.
        // This is not perfect (two different people can share a name), but it matches the product goal:
        // "no duplicates in the leaderboard".
        var byName: [String: MemberData] = [:]
        for member in byUserID.values {
            let key = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }

            if let existing = byName[key] {
                if member.lastUpdate != existing.lastUpdate {
                    if member.lastUpdate > existing.lastUpdate { byName[key] = member }
                } else if member.blocks != existing.blocks {
                    if member.blocks > existing.blocks { byName[key] = member }
                }
            } else {
                byName[key] = member
            }
        }

        return Array(byName.values).sorted { lhs, rhs in
            if lhs.blocks != rhs.blocks { return lhs.blocks > rhs.blocks }
            return lhs.lastUpdate > rhs.lastUpdate
        }
    }
    
    /// Fetch group details
    func fetchGroupDetails() {
        guard !myGroupID.isEmpty else { return }
        
        let predicate = NSPredicate(format: "group_id == %@", myGroupID)
        let query = CKQuery(recordType: "SocialGroup", predicate: predicate)
        
        database.fetch(withQuery: query, inZoneWith: nil, resultsLimit: 1) { result in
            if case .success(let (matchResults, _)) = result,
               let firstMatch = matchResults.first,
               case .success(let record) = firstMatch.1,
               let group = SocialGroup.from(record) {
                DispatchQueue.main.async {
                    self.currentGroup = group
                }
            }
        }
    }
    
    /// Update group's daily goal
    func updateGroupGoal(newGoal: Int, completion: @escaping (Result<Void, ErrorHandler.AppError>) -> Void) {
        guard !myGroupID.isEmpty else {
            completion(.failure(.unknown))
            return
        }
        
        let predicate = NSPredicate(format: "group_id == %@", myGroupID)
        let query = CKQuery(recordType: "SocialGroup", predicate: predicate)
        
        database.fetch(withQuery: query, inZoneWith: nil, resultsLimit: 1) { result in
            switch result {
            case .success(let (matchResults, _)):
                if let firstMatch = matchResults.first,
                   case .success(let record) = firstMatch.1 {
                    // Update the goal
                    record["daily_goal_blocks"] = newGoal
                    
                    self.database.save(record) { savedRecord, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                let appError = self.handleCloudKitError(error)
                                completion(.failure(appError))
                            } else {
                                // Update local cache
                                if let saved = savedRecord, let group = SocialGroup.from(saved) {
                                    self.currentGroup = group
                                    self.sharedDefaults?.set(group.dailyGoalBlocks, forKey: AppConstants.Keys.sharedDailyGoalBlocks)
                                }
                                print("✅ Group goal updated to \(newGoal)")
                                completion(.success(()))
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(.groupNotFound))
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    let appError = self.handleCloudKitError(error)
                    completion(.failure(appError))
                }
            }
        }
    }
    
    // MARK: - Background Sync
    
    /// Perform background check (called by background task)
    func performBackgroundCheck() async -> Bool {
        let result = await performBackgroundCheckDetailed()
        return result.success
    }

    /// Perform background sync, returning diagnostics for logging/UI.
    /// This is intentionally verbose so background failures can be debugged from the device.
    func performBackgroundCheckDetailed() async -> (success: Bool, errorMessage: String?, ckErrorCode: Int?, retryAfterSeconds: Double?) {
        print("🕵️‍♂️ Background Task Woke Up!")

        // 1) Basic local preconditions
        guard !myDisplayName.isEmpty else {
            let message = "Display name not set (username empty)"
            print("⚠️ \(message)")
            return (false, message, nil, nil)
        }

        // 2) iCloud availability check (this is the #1 reason CloudKit writes fail)
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                break
            case .noAccount:
                return (false, "No iCloud account signed in on this device", Int(CKError.Code.notAuthenticated.rawValue), nil)
            case .restricted:
                return (false, "iCloud access is restricted on this device", nil, nil)
            case .couldNotDetermine:
                return (false, "Could not determine iCloud account status", nil, nil)
            case .temporarilyUnavailable:
                return (false, "iCloud temporarily unavailable", nil, nil)
            @unknown default:
                return (false, "Unknown iCloud account status", nil, nil)
            }
        } catch {
            return (false, "iCloud account status check failed: \(error.localizedDescription)", nil, nil)
        }

        // 3) Prepare payload
        let currentBlocks = sharedDefaults?.integer(forKey: AppConstants.Keys.dailyBlocksUsed) ?? 0
        let currentStreak = StreakManager.shared.currentStreak

        do {
            // Fetch-or-create using stable record ID so we don't create duplicates.
            let record: CKRecord
            do {
                record = try await database.record(for: myUserProfileRecordID)
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: "UserProfile", recordID: myUserProfileRecordID)
            }

            record["user_id"] = myID
            record["display_name"] = myDisplayName
            record["group_id"] = myGroupID
            record["blocks_used"] = currentBlocks
            record["streak"] = currentStreak
            record["last_updated"] = Date()
            record["last_active_date"] = Date()

            try await database.save(record)

            print("✅ Background Sync: Uploaded \(currentBlocks) blocks")
            return (true, nil, nil, nil)
        } catch {
            let retryAfter = (error as? CKError)?
                .userInfo[CKErrorRetryAfterKey] as? Double

            if let ckError = error as? CKError {
                var message = "CloudKit error (\(ckError.code.rawValue)): \(ckError.localizedDescription)"
                if ckError.code == .unknownItem,
                   ckError.localizedDescription.localizedCaseInsensitiveContains("Did not find record type") {
                    message = "CloudKit schema missing: record type 'UserProfile' not found. Create/deploy it in CloudKit Dashboard. (\(ckError.localizedDescription))"
                }
                print("❌ Background Sync Failed: \(message)")
                return (false, message, ckError.code.rawValue, retryAfter)
            } else {
                let message = "Background sync failed: \(error.localizedDescription)"
                print("❌ \(message)")
                return (false, message, nil, retryAfter)
            }
        }
    }
    
    // MARK: - Caching
    
    private func cacheLeaderboardData() {
        if let encoded = try? JSONEncoder().encode(groupMembers) {
            sharedDefaults?.set(encoded, forKey: AppConstants.Keys.cachedLeaderboardData)
        }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "ScreenMatesGroupWidget")
        #endif
    }
    
    private func loadCachedData() {
        if let data = sharedDefaults?.data(forKey: AppConstants.Keys.cachedLeaderboardData),
           let cached = try? JSONDecoder().decode([MemberData].self, from: data) {
            self.groupMembers = cached
            print("📦 Loaded \(cached.count) cached members")
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
            return .cloudKitError("Cloud storage quota exceeded")
        default:
            return .cloudKitError(error.localizedDescription)
        }
    }
    
    // MARK: - Debug Helpers
    
    /// Get current blocks from shared defaults
    var currentBlocksUsed: Int {
        return sharedDefaults?.integer(forKey: AppConstants.Keys.dailyBlocksUsed) ?? 0
    }
    
    /// Force sync now
    func forceSyncNow() {
        Task { @MainActor in
            await refreshGroupNow(reason: "manual")
        }
    }
    
    /// Reset all data (for debugging)
    func resetAllData() {
        myGroupID = ""
        myDisplayName = ""
        isSetupDone = false
        usernameSet = false
        currentGroup = nil
        groupMembers = []
        clearCache()
        
        // Clear shared defaults
        sharedDefaults?.removeObject(forKey: AppConstants.Keys.dailyBlocksUsed)
        sharedDefaults?.removeObject(forKey: AppConstants.Keys.lastBlockDate)
        
        print("🔄 All data reset")
    }
}
