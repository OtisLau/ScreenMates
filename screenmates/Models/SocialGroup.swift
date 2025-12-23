import Foundation
import CloudKit

/// Represents a social group in CloudKit
struct SocialGroup {
    var recordID: CKRecord.ID?
    var groupID: String
    var dailyGoalBlocks: Int
    var memberCount: Int
    var createdDate: Date
    
    init(
        recordID: CKRecord.ID? = nil,
        groupID: String,
        dailyGoalBlocks: Int = AppConstants.defaultDailyGoalBlocks,
        memberCount: Int = 0,
        createdDate: Date = Date()
    ) {
        self.recordID = recordID
        self.groupID = groupID
        self.dailyGoalBlocks = dailyGoalBlocks
        self.memberCount = memberCount
        self.createdDate = createdDate
    }
    
    /// Convert to CloudKit record
    func toCKRecord() -> CKRecord {
        let record = recordID != nil ? CKRecord(recordType: "SocialGroup", recordID: recordID!) : CKRecord(recordType: "SocialGroup")
        record["group_id"] = groupID
        record["daily_goal_blocks"] = dailyGoalBlocks
        record["member_count"] = memberCount
        record["created_date"] = createdDate
        return record
    }
    
    /// Create from CloudKit record
    static func from(_ record: CKRecord) -> SocialGroup? {
        guard let groupID = record["group_id"] as? String else {
            return nil
        }
        
        return SocialGroup(
            recordID: record.recordID,
            groupID: groupID,
            dailyGoalBlocks: record["daily_goal_blocks"] as? Int ?? AppConstants.defaultDailyGoalBlocks,
            memberCount: record["member_count"] as? Int ?? 0,
            createdDate: record["created_date"] as? Date ?? Date()
        )
    }
}
