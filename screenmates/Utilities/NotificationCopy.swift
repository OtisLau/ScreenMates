import Foundation

struct NotificationCopy {

    // MARK: - Over Limit

    static let overLimitBodies = [
        "{time} today be serious",
        "just blew past the limit like it wasnt even there",
        "went right past the limit of {limit}",
        "the limit meant nothing to you pal",
        "thats enough phone for today respectfully",
        "put the phone down gently",
        "go outside for 10 minutes",
        "this is why we set the limit",
        "we had one rule",
        "be honest you knew the limit was there",
        "saw the limit and said not today",
        "unbelievable performance today",
        "strong phone usage today",
        "this is getting hard to defend",
        "we need to talk about this",
        "tough look today",
        "the phone is winning",
        "you lost today",
        "this is becoming a pattern",
        "please just stand up and walk around"
    ]

    // MARK: - End of Day Summary (10 PM)

    static let endOfDayTitles = [
        "daily recap",
        "the damage report",
        "so about today",
        "end of day report",
        "tonight's highlights",
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
        "rise and shame",
        "last night was rough",
        "about last night",
    ]

    static let morningDoomBodies = [
        "btw {name} was doom scrolling for {time} past midnight last night",
        "good morning. {name} was up scrolling for {time} after midnight",
        "rise and shine. {name} decided sleep was optional last night ({time})",
        "{name} was on their phone for {time} past midnight. just so you know",
        "fun fact: {name} scrolled for {time} instead of sleeping last night",
    ]

    // MARK: - Helpers

    static func randomOverLimit(name: String, time: String, limit: String) -> (title: String, body: String) {
        var body = overLimitBodies.randomElement()!
        body = body.replacingOccurrences(of: "{time}", with: time)
        body = body.replacingOccurrences(of: "{limit}", with: limit)
        return (title: name, body: body)
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
