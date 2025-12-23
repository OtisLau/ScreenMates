import Foundation

/// Represents a member in the leaderboard
struct MemberData: Identifiable, Codable {
    /// Stable identity for SwiftUI diffing. We use `userID` to avoid duplicate rows when
    /// old duplicate CloudKit records exist.
    let id: String
    let userID: String
    let displayName: String
    let blocks: Int
    let streak: Int
    let lastUpdate: Date
    
    init(id: String? = nil, userID: String, displayName: String, blocks: Int, streak: Int = 0, lastUpdate: Date) {
        self.id = id ?? userID
        self.userID = userID
        self.displayName = displayName
        self.blocks = blocks
        self.streak = streak
        self.lastUpdate = lastUpdate
    }

    // Backwards-compatible decode (older caches may have used random UUID `id`).
    enum CodingKeys: String, CodingKey {
        case id, userID, displayName, blocks, streak, lastUpdate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let userID = try container.decode(String.self, forKey: .userID)
        let displayName = try container.decode(String.self, forKey: .displayName)
        let blocks = try container.decode(Int.self, forKey: .blocks)
        let streak = try container.decode(Int.self, forKey: .streak)
        let lastUpdate = try container.decode(Date.self, forKey: .lastUpdate)
        let decodedID = try container.decodeIfPresent(String.self, forKey: .id)

        self.init(
            id: decodedID ?? userID,
            userID: userID,
            displayName: displayName,
            blocks: blocks,
            streak: streak,
            lastUpdate: lastUpdate
        )
    }
    
    /// Status based on blocks used vs goal
    func status(goal: Int) -> MemberStatus {
        let percentage = Double(blocks) / Double(goal)
        if blocks >= goal {
            return .overLimit
        } else if percentage >= 0.9 {
            return .danger
        } else if percentage >= 0.75 {
            return .warning
        } else {
            return .safe
        }
    }
}

enum MemberStatus {
    case safe
    case warning
    case danger
    case overLimit
    
    var displayText: String {
        switch self {
        case .safe: return "Under Limit"
        case .warning: return "Approaching Limit"
        case .danger: return "Almost Over"
        case .overLimit: return "Over Limit"
        }
    }
}

