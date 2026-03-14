import Foundation
import CloudKit

// Represents a group in CloudKit — just an ID, member count, and when it was created.
// Groups are the glue that connects everyone's UserProfile records together.
struct SocialGroup {
    var recordID: CKRecord.ID?
    var groupID: String
    var memberCount: Int
    var createdDate: Date

    init(
        recordID: CKRecord.ID? = nil,
        groupID: String,
        memberCount: Int = 0,
        createdDate: Date = Date()
    ) {
        self.recordID = recordID
        self.groupID = groupID
        self.memberCount = memberCount
        self.createdDate = createdDate
    }

    // Convert to a CloudKit record for saving
    func toCKRecord() -> CKRecord {
        let record: CKRecord
        if let recordID {
            record = CKRecord(recordType: "SocialGroup", recordID: recordID)
        } else {
            record = CKRecord(recordType: "SocialGroup")
        }
        record["group_id"] = groupID
        record["member_count"] = memberCount
        record["created_date"] = createdDate
        return record
    }

    // Build a SocialGroup from a CloudKit record returned by a query
    static func from(_ record: CKRecord) -> SocialGroup? {
        guard let groupID = record["group_id"] as? String else { return nil }
        return SocialGroup(
            recordID: record.recordID,
            groupID: groupID,
            memberCount: record["member_count"] as? Int ?? 0,
            createdDate: record["created_date"] as? Date ?? Date()
        )
    }
}
