import Foundation

// Sarcastic notification templates for each scenario.
// {name} and {time} are replaced at schedule time.
struct NotificationCopy {

    // MARK: - Over Limit

    static let overLimitTitles = [
        "ScreenMates",
        "limit reached",
        "well well well",
    ]

    static let overLimitBodies = [
        "big round of applause for {name}. they went over today's limit",
        "{name} just blew past the limit. we're all very proud",
        "oh nice {name} exceeded the daily limit. cool cool cool",
        "breaking news: {name} has gone over the limit. truly shocking",
        "{name} said 'what limit' apparently",
    ]

    // MARK: - End of Day Summary (10 PM)

    static let endOfDayTitles = [
        "daily recap",
        "ScreenMates",
        "end of day report",
    ]

    static let endOfDayBodies = [
        "{time} of screen time today {name}. nice :)",
        "{name} racked up {time} today. impressive honestly",
        "just {time} of scrolling for {name} today. totally normal",
        "{name} spent {time} on their phone today. very productive",
        "{time} today for {name}. a new personal best maybe",
    ]

    // MARK: - Morning Doom Scroll (9:30 AM)

    static let morningDoomTitles = [
        "good morning",
        "sleep report",
        "ScreenMates",
    ]

    static let morningDoomBodies = [
        "btw {name} was doom scrolling for {time} past midnight last night",
        "good morning. {name} was up scrolling for {time} after midnight",
        "rise and shine. {name} decided sleep was optional last night ({time})",
        "{name} was on their phone for {time} past midnight. just so you know",
        "fun fact: {name} scrolled for {time} instead of sleeping last night",
    ]

    // MARK: - Helpers

    static func randomOverLimit(name: String) -> (title: String, body: String) {
        let title = overLimitTitles.randomElement()!
        let body = overLimitBodies.randomElement()!.replacingOccurrences(of: "{name}", with: name)
        return (title, body)
    }

    static func randomEndOfDay(name: String, time: String) -> (title: String, body: String) {
        let title = endOfDayTitles.randomElement()!
        let body = endOfDayBodies.randomElement()!
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{time}", with: time)
        return (title, body)
    }

    static func randomMorningDoom(name: String, time: String) -> (title: String, body: String) {
        let title = morningDoomTitles.randomElement()!
        let body = morningDoomBodies.randomElement()!
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{time}", with: time)
        return (title, body)
    }

    // Format minutes into a readable string like "1h 30min" or "45min"
    static func formatTime(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)min" }
        else if h > 0 { return "\(h)h" }
        else { return "\(m)min" }
    }
}
