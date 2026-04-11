import CloudKit

// An incoming pending friend request shown in FriendsView.
struct FriendRequest: Identifiable {
    let id: String          // CKRecord recordName
    let recordID: CKRecord.ID
    let requesterUserID: String
    let requesterName: String
}
