import Foundation

// One person in the friends leaderboard — their name, usage, and personal daily limit.
struct MemberData: Identifiable, Codable {
    // We use userID as the stable ID so SwiftUI doesn't create duplicate rows
    // if the same person has old records in CloudKit.
    let id: String
    let userID: String
    let displayName: String
    let blocks: Int                // number of blocks used today
    let lastUpdate: Date           // when this data was last synced
    let postMidnightBlocks: Int    // blocks accumulated between 12AM–4AM
    let personalGoalMinutes: Int   // this person's own daily limit (0 = no limit)

    init(
        id: String? = nil,
        userID: String,
        displayName: String,
        blocks: Int,
        lastUpdate: Date,
        postMidnightBlocks: Int = 0,
        personalGoalMinutes: Int = 0
    ) {
        self.id = id ?? userID
        self.userID = userID
        self.displayName = displayName
        self.blocks = blocks
        self.lastUpdate = lastUpdate
        self.postMidnightBlocks = postMidnightBlocks
        self.personalGoalMinutes = personalGoalMinutes
    }

    // Custom decode so old cached entries without personalGoalMinutes still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                 = try c.decode(String.self, forKey: .id)
        userID             = try c.decode(String.self, forKey: .userID)
        displayName        = try c.decode(String.self, forKey: .displayName)
        blocks             = try c.decode(Int.self,    forKey: .blocks)
        lastUpdate         = try c.decode(Date.self,   forKey: .lastUpdate)
        postMidnightBlocks = (try? c.decode(Int.self,  forKey: .postMidnightBlocks)) ?? 0
        personalGoalMinutes = (try? c.decode(Int.self, forKey: .personalGoalMinutes)) ?? 0
    }

    var minutesUsed: Int {
        blocks * AppConstants.currentBlockSize
    }

    var postMidnightMinutes: Int {
        postMidnightBlocks * AppConstants.currentBlockSize
    }
}
