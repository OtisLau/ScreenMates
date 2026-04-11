import CloudKit

// An incoming pending friend request shown in FriendsView.
struct FriendRequest: Identifiable {
    let id: String          // CKRecord recordName
    let recordID: CKRecord.ID
    let requesterUserID: String
    let requesterName: String
}

// A pending friend request sent by the current user.
struct OutgoingFriendRequest: Identifiable {
    let id: String          // CKRecord recordName
    let recordID: CKRecord.ID
    let recipientUserID: String
    let recipientName: String
}
