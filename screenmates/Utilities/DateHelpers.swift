import Foundation

/// Helper functions for date formatting and calculations
struct DateHelpers {
    
    /// Convert a date to relative time string ("2m ago", "1h ago", etc.)
    static func relativeTime(from date: Date) -> String {
        let now = Date()
        let seconds = Int(now.timeIntervalSince(date))
        
        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "\(hours)h ago"
        } else {
            let days = seconds / 86400
            if days == 1 {
                return "Yesterday"
            } else {
                return "\(days)d ago"
            }
        }
    }
    
    /// Calculate time remaining until midnight
    static func timeUntilMidnight() -> String {
        let calendar = Calendar.current
        let now = Date()
        
        guard let midnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime
        ) else {
            return "Unknown"
        }
        
        let components = calendar.dateComponents([.hour, .minute], from: now, to: midnight)
        let hours = components.hour ?? 0
        let minutes = components.minute ?? 0
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    /// Check if a date is today
    static func isToday(_ date: Date) -> Bool {
        return Calendar.current.isDateInToday(date)
    }
    
    /// Check if it's a new day since last check
    static func isNewDay(since lastDate: Date?) -> Bool {
        guard let lastDate = lastDate else { return true }
        return !Calendar.current.isDateInToday(lastDate)
    }
}
