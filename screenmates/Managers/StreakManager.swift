import Foundation
import Combine

/// Manages user streak tracking
class StreakManager: ObservableObject {
    static let shared = StreakManager()
    
    private let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupSuite)
    
    private init() {}
    
    // MARK: - Streak Tracking
    
    /// Get the current streak count
    var currentStreak: Int {
        get {
            return sharedDefaults?.integer(forKey: AppConstants.Keys.currentStreak) ?? 0
        }
        set {
            sharedDefaults?.set(newValue, forKey: AppConstants.Keys.currentStreak)
        }
    }
    
    /// Get the last check date
    private var lastCheckDate: Date? {
        get {
            return sharedDefaults?.object(forKey: AppConstants.Keys.lastCheckDate) as? Date
        }
        set {
            sharedDefaults?.set(newValue, forKey: AppConstants.Keys.lastCheckDate)
        }
    }
    
    /// Check and update streak based on current blocks usage
    func updateStreak(blocksUsed: Int, dailyGoal: Int) -> Bool {
        // Check if it's a new day
        guard DateHelpers.isNewDay(since: lastCheckDate) else {
            return false // Not a new day, no update needed
        }
        
        // Get yesterday's blocks (before midnight reset)
        let wasUnderLimit = blocksUsed < dailyGoal
        
        if wasUnderLimit {
            // Increment streak
            currentStreak += 1
            print("🔥 Streak incremented to \(currentStreak)")
        } else {
            // Reset streak
            currentStreak = 0
            print("💔 Streak reset (went over limit)")
        }
        
        // Update last check date
        lastCheckDate = Date()
        
        return wasUnderLimit
    }
    
    /// Check if user is under limit (for real-time streak validation)
    func isUnderLimit(blocksUsed: Int, dailyGoal: Int) -> Bool {
        return blocksUsed < dailyGoal
    }
    
    /// Reset streak (for debugging or manual reset)
    func resetStreak() {
        currentStreak = 0
        lastCheckDate = nil
        print("🔄 Streak manually reset")
    }
    
    /// Get streak status message
    func streakMessage() -> String {
        if currentStreak == 0 {
            return "Start your streak today!"
        } else if currentStreak == 1 {
            return "🔥 1 day streak"
        } else {
            return "🔥 \(currentStreak) day streak"
        }
    }
}
