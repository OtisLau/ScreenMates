import Foundation

struct NotificationCopy {

    struct NotificationTemplate {
        let body: String
        let severity: Severity
    }

    enum Severity: String, CaseIterable {
        case mild
        case spicy
        case nuclear
    }

    // MARK: - Over Limit

    static let overLimitTemplates: [NotificationTemplate] = [
        .init(body: "{weekday} and you already hit {time}. the {limit} goal never stood a chance.", severity: .mild),
        .init(body: "{time} today and it’s not even dinner. congrats on speedrunning the limit.", severity: .mild),
        .init(body: "phone time at {time}, goal was {limit}. math says chill, you said nah.", severity: .mild),
        .init(body: "blew past {limit} by {overage}. you’re the reason screen time charts look scary.", severity: .spicy),
        .init(body: "{weekday} check-in: goal {limit}, actual {time}. explain this to the group chat.", severity: .spicy),
        .init(body: "{name} is farming {time} of scrolling. {limit} was a suggestion apparently.", severity: .spicy),
        .init(body: "{time} and counting. put the phone down before we file a missing person report for your attention span.", severity: .nuclear),
        .init(body: "limit was {limit}, you delivered {time}. that’s a performance review waiting to happen.", severity: .nuclear),
        .init(body: "{weekday} is canceled because you chose {time} of screen time. overage: {overage}. do better.", severity: .nuclear)
    ]

    // MARK: - End of Day Summary

    static let endOfDayTemplates: [NotificationTemplate] = [
        .init(body: "{weekday} wrap: {time} logged. thats a part-time job worth of doom scrolls.", severity: .mild),
        .init(body: "{time} today which is wild considering the goal was {limit}. maybe see a cloud instead of iCloud.", severity: .mild),
        .init(body: "rent is due because you basically worked a shift on your phone ({time}).", severity: .spicy),
        .init(body: "{time} of usage, {overage} over goal. the squad saw the stats and is concerned.", severity: .spicy),
        .init(body: "{weekday} L recap: {time} online, zero hours offline. we will be discussing this.", severity: .nuclear),
        .init(body: "you torched {time} today. accountants are flagging your screen time as a liability.", severity: .nuclear)
    ]

    // MARK: - Morning Doom Scroll

    static let morningDoomTemplates: [NotificationTemplate] = [
        .init(body: "we saw the midnight shift: {time} of doom scrolling. go touch sunlight maybe.", severity: .mild),
        .init(body: "normal people slept. you ran {time} of thumb cardio past midnight.", severity: .mild),
        .init(body: "{time} after midnight? tomorrow is already tired and mad at you.", severity: .spicy),
        .init(body: "you essentially pulled a night shift on your phone ({time}). enjoy the zombie vibes.", severity: .spicy),
        .init(body: "vampire hours detected: {time} of scrolling. melatonin has left the chat.", severity: .nuclear),
        .init(body: "screens from 12–?? for {time}. at this point the moon is filing a complaint.", severity: .nuclear)
    ]

    // MARK: - Weekly Roast

    static let weeklyRoastTemplates: [NotificationTemplate] = [
        .init(body: "averaged {time} a day. that’s a career-high in procrastination.", severity: .mild),
        .init(body: "{weeklyHours} total hours this week. basically hired your phone full-time.", severity: .mild),
        .init(body: "sat on your phone more than you stood up this week. talent!", severity: .spicy),
        .init(body: "screen time graph is vertical. we triple-checked {weeklyHours} hours and it’s still reckless.", severity: .spicy),
        .init(body: "if scrolling was homework you’d be valedictorian. {time} daily is unreal.", severity: .nuclear),
        .init(body: "phone dominated every single day. consider filing it on your taxes.", severity: .nuclear)
    ]

    // MARK: - Generators (Title = Name)

    static func randomOverLimit(name: String, usedMinutes: Int, goalMinutes: Int, date: Date = Date()) -> (title: String, body: String) {
        let severity = severityForOverage(minutesOver: usedMinutes - goalMinutes)
        let template = pickTemplate(from: overLimitTemplates, severity: severity)
        let replacements: [String: String] = [
            "name": name,
            "time": formatTime(usedMinutes),
            "limit": formatTime(goalMinutes),
            "overage": formatTime(max(usedMinutes - goalMinutes, 0)),
            "weekday": weekdayString(from: date)
        ]
        let body = format(template: template, replacements: replacements)
        return (title: name, body: body)
    }

    static func randomEndOfDay(name: String, usedMinutes: Int, goalMinutes: Int, date: Date = Date()) -> (title: String, body: String) {
        let severity = severityForOverage(minutesOver: usedMinutes - goalMinutes)
        let template = pickTemplate(from: endOfDayTemplates, severity: severity)
        let replacements: [String: String] = [
            "name": name,
            "time": formatTime(usedMinutes),
            "limit": formatTime(goalMinutes),
            "overage": formatTime(max(usedMinutes - goalMinutes, 0)),
            "weekday": weekdayString(from: date)
        ]
        let body = format(template: template, replacements: replacements)
        return (title: name, body: body)
    }

    static func randomMorningDoom(name: String, postMidnightMinutes: Int, date: Date = Date()) -> (title: String, body: String) {
        let severity = severityForLateNight(minutes: postMidnightMinutes)
        let template = pickTemplate(from: morningDoomTemplates, severity: severity)
        let replacements: [String: String] = [
            "name": name,
            "time": formatTime(postMidnightMinutes),
            "weekday": weekdayString(from: date)
        ]
        let body = format(template: template, replacements: replacements)
        return (title: name, body: body)
    }

    static func randomWeeklyRoast(name: String, averageMinutes: Int, weeklyHours: Int) -> (title: String, body: String) {
        let severity = severityForWeekly(hours: weeklyHours)
        let template = pickTemplate(from: weeklyRoastTemplates, severity: severity)
        let replacements: [String: String] = [
            "name": name,
            "time": formatTime(averageMinutes),
            "weeklyHours": "\(weeklyHours)",
            "weekday": weekdayString(from: Date())
        ]
        let body = format(template: template, replacements: replacements)
        return (title: name, body: body)
    }

    // MARK: - Time Formatting

    // Format minutes into a readable string like "1h 30min" or "45min"
    static func formatTime(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)min" }
        else if h > 0 { return "\(h)h" }
        else { return "\(m)min" }
    }

    private static func format(template: NotificationTemplate, replacements: [String: String]) -> String {
        var body = template.body
        for (key, value) in replacements {
            body = body.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return body
    }

    private static func pickTemplate(from templates: [NotificationTemplate], severity: Severity) -> NotificationTemplate {
        let filtered = templates.filter { $0.severity == severity }
        return (filtered.isEmpty ? templates : filtered).randomElement()!
    }

    private static func weekdayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private static func severityForOverage(minutesOver: Int) -> Severity {
        switch minutesOver {
        case ..<30:
            return .mild
        case 30..<90:
            return .spicy
        default:
            return .nuclear
        }
    }

    private static func severityForLateNight(minutes: Int) -> Severity {
        switch minutes {
        case ..<45:
            return .mild
        case 45..<90:
            return .spicy
        default:
            return .nuclear
        }
    }

    private static func severityForWeekly(hours: Int) -> Severity {
        switch hours {
        case ..<30:
            return .mild
        case 30..<42:
            return .spicy
        default:
            return .nuclear
        }
    }
}
