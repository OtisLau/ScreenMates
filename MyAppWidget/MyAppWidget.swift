import WidgetKit
import SwiftUI
import Foundation

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8)  & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

private enum W {
    static let background  = Color(hex: 0x0D1117)
    static let surface     = Color(hex: 0x161B22)
    static let text        = Color(hex: 0xE6EDF3)
    static let secondary   = Color(hex: 0x7D8590)
    static let muted       = Color(hex: 0x484F58)
    static let accent      = Color(hex: 0x9E6BE8)
}

private enum WidgetConstants {
    static let kind = "ScreenMatesGroupWidget"
    static let appGroupSuite = "group.com.otishlau.screenmates"
    static let cachedLeaderboardKey = "CachedLeaderboardData"
    static let blockSizeKey = "SharedBlockSizeMinutes"
}

struct CachedMember: Codable, Identifiable {
    let id: String
    let userID: String
    let displayName: String
    let blocks: Int
    let lastUpdate: Date

    func formattedTime(blockSize: Int) -> String {
        let total = blocks * blockSize
        let h = total / 60
        let m = total % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        else if h > 0      { return "\(h)h" }
        else               { return "\(m)m" }
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), members: [], blockSizeMinutes: 15)
    }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(loadEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry = loadEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
    private func loadEntry() -> SimpleEntry {
        let defaults = UserDefaults(suiteName: WidgetConstants.appGroupSuite)
        let bs = defaults?.integer(forKey: WidgetConstants.blockSizeKey) ?? 0
        let blockSize = bs > 0 ? bs : 15
        var members: [CachedMember] = []
        if let data = defaults?.data(forKey: WidgetConstants.cachedLeaderboardKey) {
            members = (try? JSONDecoder().decode([CachedMember].self, from: data)) ?? []
        }
        // Sort fewest blocks first (winning = less screen time)
        members.sort { $0.blocks < $1.blocks }
        return SimpleEntry(date: Date(), members: Array(members.prefix(5)), blockSizeMinutes: blockSize)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let members: [CachedMember]
    let blockSizeMinutes: Int
}

struct MyAppWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        if entry.members.isEmpty {
            Text("Open app to start")
                .font(.system(size: 12))
                .foregroundColor(W.secondary)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(entry.members) { member in
                    HStack {
                        Text(member.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(W.text)
                            .lineLimit(1)
                        Spacer()
                        Text(member.formattedTime(blockSize: entry.blockSizeMinutes))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(W.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }
}

struct MyAppWidget: Widget {
    let kind: String = WidgetConstants.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MyAppWidgetEntryView(entry: entry)
                .containerBackground(W.background, for: .widget)
        }
        .configurationDisplayName("ScreenMates Group")
        .description("Your group's screen time.")
        .supportedFamilies([.systemSmall])
    }
}
