import WidgetKit
import SwiftUI

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

    func minutesUsed(blockSize: Int) -> Int { blocks * blockSize }

    func formattedTime(blockSize: Int) -> String {
        let total = minutesUsed(blockSize: blockSize)
        let h = total / 60
        let m = total % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        else if h > 0      { return "\(h)h" }
        else               { return "\(m)m" }
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let members: [CachedMember]
    let blockSizeMinutes: Int
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
        members.sort { $0.blocks < $1.blocks }
        return SimpleEntry(date: Date(), members: Array(members.prefix(4)), blockSizeMinutes: blockSize)
    }
}

// MARK: - Dot grid background (mirrors AppBackground in the main app)
private struct WidgetDotGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 18
            let dotSize: CGFloat = 1.8
            let cols = Int(size.width / spacing) + 2
            let rows = Int(size.height / spacing) + 2
            var path = Path()
            for row in 0...rows {
                for col in 0...cols {
                    path.addEllipse(in: CGRect(
                        x: CGFloat(col) * spacing - dotSize / 2,
                        y: CGFloat(row) * spacing - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    ))
                }
            }
            context.fill(path, with: .color(.white.opacity(0.11)))
        }
    }
}

// MARK: - Single member row (mirrors GroupMemberRow style)
private struct WidgetMemberRow: View {
    let rank: Int
    let member: CachedMember
    let blockSize: Int
    let isTop: Bool

    private var hours: Int { member.minutesUsed(blockSize: blockSize) / 60 }
    private var mins: Int  { member.minutesUsed(blockSize: blockSize) % 60 }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.3))
                .frame(width: 14, alignment: .center)

            Text(member.displayName)
                .font(.system(size: 13, weight: isTop ? .semibold : .regular, design: .rounded))
                .foregroundStyle(.white.opacity(isTop ? 0.92 : 0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 2)

            // Matches the h/m superscript style from GroupMemberRow
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                if hours > 0 {
                    Text("\(hours)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("h")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.trailing, 1)
                }
                Text("\(mins)")
                    .font(.system(size: hours > 0 ? 11 : 13, weight: .semibold, design: .rounded))
                Text("m")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .foregroundStyle(.white.opacity(isTop ? 0.85 : 0.5))
            .fixedSize()
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Widget entry view
struct MyAppWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        if entry.members.isEmpty {
            Text("Open app to start")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(entry.members.enumerated()), id: \.element.id) { index, member in
                    WidgetMemberRow(
                        rank: index + 1,
                        member: member,
                        blockSize: entry.blockSizeMinutes,
                        isTop: index == 0
                    )
                    if index < entry.members.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 1)
                            .padding(.horizontal, 2)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct MyAppWidget: Widget {
    let kind: String = WidgetConstants.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MyAppWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.black
                    WidgetDotGrid()
                }
        }
        .configurationDisplayName("ScreenMates Group")
        .description("Your group's screen time.")
        .supportedFamilies([.systemSmall])
    }
}
