import CloudKit
import SwiftUI
import Combine

class CloudMate: ObservableObject {
    static let shared = CloudMate()
    
    // REPLACE with your container ID if different
    let container = CKContainer(identifier: "iCloud.com.otishlau.screenmates")
    lazy var database = container.publicCloudDatabase
    
    @Published var lastSyncStatus: String = "Idle"
    @Published var friendStatus: String = "Unknown"
    
    // 1. Your Permanent ID
    var myID: String {
        let key = "MyUniqueScreenMateID"
        if let existingID = UserDefaults.standard.string(forKey: key) {
            return existingID
        }
        let newID = UUID().uuidString.prefix(8).uppercased()
        UserDefaults.standard.set(newID, forKey: key)
        return String(newID)
    }

    // 2. Upload Status (When App is Open)
    func logThresholdEvent() {
        let record = CKRecord(recordType: "ScreenEvent")
        record["timestamp"] = Date()
        record["eventType"] = "limit_reached"
        record["user_id"] = myID
        
        database.save(record) { record, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.lastSyncStatus = "Error: \(error.localizedDescription)"
                    print("❌ Cloud Error: \(error.localizedDescription)")
                } else {
                    self.lastSyncStatus = "✅ Saved! (ID: \(self.myID))"
                }
            }
        }
    }
    
    // 3. Check Friend's Status
    func checkFriendStatus(friendCode: String) {
        if friendCode.isEmpty { return }
        self.friendStatus = "Checking..."
        
        let predicate = NSPredicate(format: "user_id == %@", friendCode)
        let query = CKQuery(recordType: "ScreenEvent", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        database.fetch(withQuery: query, inZoneWith: nil, desiredKeys: ["timestamp"], resultsLimit: 1) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (matchResults, _)):
                    if let firstMatch = matchResults.first {
                        switch firstMatch.1 {
                        case .success(let record):
                            if let date = record["timestamp"] as? Date {
                                if Calendar.current.isDateInToday(date) {
                                    self.friendStatus = "🔴 LIMIT HIT at \(date.formatted(date: .omitted, time: .shortened))"
                                } else {
                                    self.friendStatus = "🟢 Safe (Last hit: \(date.formatted(date: .abbreviated, time: .shortened)))"
                                }
                            }
                        case .failure: self.friendStatus = "⚠️ Error reading record"
                        }
                    } else {
                        self.friendStatus = "🟢 Clean (No limits hit yet)"
                    }
                case .failure(let error):
                    self.friendStatus = "❌ Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // 4. Background "Safety Net" Check
    // This runs silently when the app is closed to upload missed violations
    func performBackgroundCheck() async -> Bool {
        print("🕵️‍♂️ Background Task Woke Up!")
        
        let sharedDefaults = UserDefaults(suiteName: "group.com.otishlau.screenmates")
        
        // Check if there is a pending limit event that wasn't uploaded
        guard let lastHitDate = sharedDefaults?.object(forKey: "LastLimitHitDate") as? Date else {
            print("💤 Nothing to report.")
            return true // "Success" (nothing broke, just nothing to do)
        }
        
        print("🚨 Found a hidden violation from: \(lastHitDate)")
        
        // Upload it
        let record = CKRecord(recordType: "ScreenEvent")
        record["timestamp"] = lastHitDate // Use the ACTUAL time it happened
        record["eventType"] = "limit_reached"
        record["user_id"] = myID
        
        do {
            try await database.save(record)
            print("✅ Background Upload Success!")
            
            // Clear the evidence so we don't upload it twice
            sharedDefaults?.removeObject(forKey: "LastLimitHitDate")
            return true
        } catch {
            print("❌ Background Upload Failed: \(error.localizedDescription)")
            return false // Tell iOS we failed so it might retry later
        }
    }
}
