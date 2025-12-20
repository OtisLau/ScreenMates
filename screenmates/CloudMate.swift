import CloudKit
import SwiftUI
import Combine

class CloudMate: ObservableObject {
    static let shared = CloudMate()
    
    // REPLACE with your actual container ID
    let container = CKContainer(identifier: "iCloud.com.otishlau.screenmates")
    lazy var database = container.publicCloudDatabase
    
    // --- LOCAL STORAGE ---
    @AppStorage("my_user_id") var myID: String = UUID().uuidString.prefix(8).uppercased()
    @AppStorage("my_group_id") var myGroupID: String = ""
    @AppStorage("is_setup_done") var isSetupDone: Bool = false
    
    // --- LIVE DATA ---
    @Published var groupMembers: [MemberData] = []
    
    struct MemberData: Identifiable {
        let id = UUID()
        let name: String
        let blocks: Int
        let lastUpdate: Date
    }

    // --- 1. GROUP ACTIONS ---
    
    func createGroup(completion: @escaping (String) -> Void) {
        let newGroupID = UUID().uuidString.prefix(6).uppercased()
        let record = CKRecord(recordType: "SocialGroup")
        record["group_id"] = newGroupID
        record["daily_goal_blocks"] = 12 // Default 3 hours
        
        database.save(record) { _, error in
            DispatchQueue.main.async {
                if error == nil {
                    self.joinGroup(groupID: newGroupID)
                    completion(newGroupID)
                } else {
                    print("Error creating group: \(String(describing: error))")
                }
            }
        }
    }
    
    func joinGroup(groupID: String) {
        self.myGroupID = groupID
        updateMyProfile() // Create the user profile linked to this group
    }
    
    // --- 2. USER SYNC ACTIONS ---
    
    func updateMyProfile() {
        let sharedDefaults = UserDefaults(suiteName: "group.com.otishlau.screenmates")
        let currentBlocks = sharedDefaults?.integer(forKey: "DailyBlocksUsed") ?? 0
        
        let predicate = NSPredicate(format: "user_id == %@", myID)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        database.fetch(withQuery: query, inZoneWith: nil, resultsLimit: 1) { result in
            switch result {
            case .success(let (matchResults, _)):
                if let firstMatch = matchResults.first, case .success(let record) = firstMatch.1 {
                    // Update existing
                    record["group_id"] = self.myGroupID
                    record["blocks_used"] = currentBlocks
                    record["last_updated"] = Date()
                    self.database.save(record) { _,_ in print("✅ Cloud: Profile Updated") }
                } else {
                    // Create New
                    let newRecord = CKRecord(recordType: "UserProfile")
                    newRecord["user_id"] = self.myID
                    newRecord["group_id"] = self.myGroupID
                    newRecord["blocks_used"] = currentBlocks
                    newRecord["last_updated"] = Date()
                    self.database.save(newRecord) { _,_ in print("✅ Cloud: Profile Created") }
                }
            case .failure(let error):
                print("Cloud Error: \(error.localizedDescription)")
            }
        }
    }
    
    func fetchGroupData() {
        guard !myGroupID.isEmpty else { return }
        
        // Find everyone with the same Group ID
        let predicate = NSPredicate(format: "group_id == %@", myGroupID)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "blocks_used", ascending: false)]
        
        database.fetch(withQuery: query, inZoneWith: nil, resultsLimit: 10) { result in
            switch result {
            case .success(let (matchResults, _)):
                var newMembers: [MemberData] = []
                for match in matchResults {
                    if case .success(let record) = match.1 {
                        let name = record["user_id"] as? String ?? "Unknown"
                        let blocks = record["blocks_used"] as? Int ?? 0
                        let date = record["last_updated"] as? Date ?? Date()
                        newMembers.append(MemberData(name: name, blocks: blocks, lastUpdate: date))
                    }
                }
                DispatchQueue.main.async {
                    self.groupMembers = newMembers
                }
            case .failure: break
            }
        }
    }
    
    // --- 3. BACKGROUND SAFETY NET ---
    
    func performBackgroundCheck() async -> Bool {
        print("🕵️‍♂️ Background Task Woke Up!")
        let sharedDefaults = UserDefaults(suiteName: "group.com.otishlau.screenmates")
        let currentBlocks = sharedDefaults?.integer(forKey: "DailyBlocksUsed") ?? 0
        
        // Only upload if we have data
        // We re-use the update logic but make it async for the background task
        let predicate = NSPredicate(format: "user_id == %@", myID)
        let query = CKQuery(recordType: "UserProfile", predicate: predicate)
        
        do {
            let (matchResults, _) = try await database.records(matching: query)
            
            if let firstMatch = matchResults.first, case .success(let record) = firstMatch.1 {
                record["blocks_used"] = currentBlocks
                record["last_updated"] = Date()
                try await database.save(record)
            } else {
                let newRecord = CKRecord(recordType: "UserProfile")
                newRecord["user_id"] = myID
                newRecord["group_id"] = myGroupID
                newRecord["blocks_used"] = currentBlocks
                newRecord["last_updated"] = Date()
                try await database.save(newRecord)
            }
            print("✅ Background Sync: Uploaded \(currentBlocks) blocks")
            return true
        } catch {
            print("❌ Background Sync Failed: \(error.localizedDescription)")
            return false
        }
    }
}
