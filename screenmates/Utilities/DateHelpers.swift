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
    
    /// Check if a date is today
    static func isToday(_ date: Date) -> Bool {
        return Calendar.current.isDateInToday(date)
    }
}
