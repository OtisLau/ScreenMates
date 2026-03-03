import Foundation

// One person in your group — just their name, how long they've used their phone today,
// and when we last heard from them.
struct MemberData: Identifiable, Codable {
    // We use userID as the stable ID so SwiftUI doesn't create duplicate rows
    // if the same person has old records in CloudKit.
    let id: String
    let userID: String
    let displayName: String
    let blocks: Int         // number of 15-min blocks used today
    let lastUpdate: Date    // when this data was last synced

    init(id: String? = nil, userID: String, displayName: String, blocks: Int, lastUpdate: Date) {
        self.id = id ?? userID
        self.userID = userID
        self.displayName = displayName
        self.blocks = blocks
        self.lastUpdate = lastUpdate
    }

    // How many minutes of screen time this person has used today
    var minutesUsed: Int {
        blocks * 15 // production block size is 15 minutes
    }
}
