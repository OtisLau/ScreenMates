import Foundation

// One person in your group — just their name, how long they've used their phone today,
// and when we last heard from them.
struct MemberData: Identifiable, Codable {
    // We use userID as the stable ID so SwiftUI doesn't create duplicate rows
    // if the same person has old records in CloudKit.
    let id: String
    let userID: String
    let displayName: String
    let blocks: Int         // number of blocks used today (block size depends on test vs production mode)
    let lastUpdate: Date    // when this data was last synced
    let postMidnightBlocks: Int // blocks accumulated between 12AM–4AM (for doom scroll notifications)

    init(id: String? = nil, userID: String, displayName: String, blocks: Int, lastUpdate: Date, postMidnightBlocks: Int = 0) {
        self.id = id ?? userID
        self.userID = userID
        self.displayName = displayName
        self.blocks = blocks
        self.lastUpdate = lastUpdate
        self.postMidnightBlocks = postMidnightBlocks
    }

    // How many minutes of screen time this person has used today.
    // Uses AppConstants.currentBlockSize so test mode (1 min blocks) and
    // production (15 min blocks) both display correctly.
    var minutesUsed: Int {
        blocks * AppConstants.currentBlockSize
    }

    var postMidnightMinutes: Int {
        postMidnightBlocks * AppConstants.currentBlockSize
    }
}
