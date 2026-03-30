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

    // MARK: - End of Day Summary

    static let endOfDayBodies = [
        "{time} today thats a full shift",
        "{time} today rent is due",
        "{time} today go look at a tree",
        "{time} today what are we doing",
        "{time} today be honest what were you even doing",
        "{time} today impressive in the worst way",
        "{time} today mathematically this is not looking good",
        "{time} today we ran the numbers and they are bad",
        "{time} today we need to talk",
        "{time} today this is getting out of hand",
        "{time} today this will be reviewed tomorrow",
        "{time} today strong performance unfortunately",
        "{time} today blink twice if you need help",
        "{time} today stand up immediately",
        "{time} today thats basically a part time job"
    ]

    // MARK: - Morning Doom Scroll

    static let morningDoomBodies = [
        "was doom scrolling for {time} past midnight last night",
        "while normal people slept you were scrolling for {time}",
        "{time} of scrolling after midnight tough look",
        "was up scrolling for {time} instead of sleeping",
        "sleep tried to happen but scrolling happened instead for {time}",
        "fought sleep and won unfortunately",
        "decided tomorrow would be tired",
        "chose phone over sleep again",
        "you were not supposed to be awake for {time}",
        "thats why youre tired today",
        "we saw what you were doing last night"
    ]

    // MARK: - Helpers

    static func randomOverLimit(name: String, time: String, limit: String) -> (title: String, body: String) {
        var body = overLimitBodies.randomElement()!
        body = body.replacingOccurrences(of: "{time}", with: time)
        body = body.replacingOccurrences(of: "{limit}", with: limit)
        return (title: name, body: body)
    }

    static func randomEndOfDay(name: String, time: String) -> (title: String, body: String) {
        var body = endOfDayBodies.randomElement()!
        body = body.replacingOccurrences(of: "{time}", with: time)
        return (title: name, body: body)
    }

    static func randomMorningDoom(name: String, time: String) -> (title: String, body: String) {
        var body = morningDoomBodies.randomElement()!
        body = body.replacingOccurrences(of: "{time}", with: time)
        return (title: name, body: body)
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
