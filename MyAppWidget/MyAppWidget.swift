import WidgetKit
import SwiftUI

private enum WidgetConstants {
    static let kind = "ScreenMatesGroupWidget"
    static let appGroupSuite = "group.com.otishlau.screenmates"
    static let cachedLeaderboardKey = "CachedLeaderboardData"
    static let blockSizeKey = "SharedBlockSizeMinutes"
    static let goalMinutesKey = "SharedGoalMinutes"
    static let userIDKey = "SharedMyUserID"
}

struct CachedMember: Codable, Identifiable {
    let id: String
    let userID: String
    let displayName: String
    let blocks: Int
    let lastUpdate: Date
    let postMidnightBlocks: Int?
    let personalGoalMinutes: Int?

    // Backward-compat decode — old cache entries without personalGoalMinutes still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                  = try c.decode(String.self, forKey: .id)
        userID              = try c.decode(String.self, forKey: .userID)
        displayName         = try c.decode(String.self, forKey: .displayName)
        blocks              = try c.decode(Int.self,    forKey: .blocks)
        lastUpdate          = try c.decode(Date.self,   forKey: .lastUpdate)
        postMidnightBlocks  = try? c.decode(Int.self,   forKey: .postMidnightBlocks)
        personalGoalMinutes = try? c.decode(Int.self,   forKey: .personalGoalMinutes)
    }

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
    let myGoalMinutes: Int
    let myUserID: String
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), members: [], blockSizeMinutes: 15, myGoalMinutes: 0, myUserID: "")
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
        let myGoalMinutes = defaults?.integer(forKey: WidgetConstants.goalMinutesKey) ?? 0
        let myUserID = defaults?.string(forKey: WidgetConstants.userIDKey) ?? ""
        var members: [CachedMember] = []
        if let data = defaults?.data(forKey: WidgetConstants.cachedLeaderboardKey) {
            members = (try? JSONDecoder().decode([CachedMember].self, from: data)) ?? []
        }
        members.sort { $0.blocks > $1.blocks }
        return SimpleEntry(
            date: Date(),
            members: Array(members.prefix(4)),
            blockSizeMinutes: blockSize,
            myGoalMinutes: myGoalMinutes,
            myUserID: myUserID
        )
    }
}


// MARK: - Single member row
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
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.35))
                .frame(width: 16, alignment: .center)

            Text(member.displayName)
                .font(.system(size: isTop ? 16 : 14, weight: isTop ? .semibold : .regular))
                .foregroundStyle(isTop ? Color.white : Color.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                if hours > 0 {
                    Text("\(hours)")
                        .font(.system(size: isTop ? 13 : 12, weight: .semibold, design: .rounded))
                    Text("h")
                        .font(.system(size: isTop ? 10 : 9, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .padding(.trailing, 2)
                }
                Text("\(mins)")
                    .font(.system(size: isTop ? 13 : 12, weight: .semibold, design: .rounded))
                Text("m")
                    .font(.system(size: isTop ? 10 : 9, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .foregroundStyle(Color.white)
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

// MARK: - Dot grid background
private struct WidgetDotGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 22
            let dotSize: CGFloat = 2.2
            let dotColor = Color.white.opacity(0.11)
            let cols = Int(size.width / spacing) + 2
            let rows = Int(size.height / spacing) + 2
            // Guard against runaway loop during placeholder/snapshot with large sizes
            guard cols < 200, rows < 200 else { return }
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
            ctx.fill(path, with: .color(dotColor))
        }
    }
}

// MARK: - Pie slice mask
private struct PieSlice: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        guard fraction > 0 else { return Path() }
        guard fraction < 1 else { return Path(rect) }
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(rect.width, rect.height)
        p.move(to: center)
        p.addArc(center: center, radius: radius,
                 startAngle: .degrees(-90),
                 endAngle: .degrees(-90 + 360 * fraction),
                 clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Progress border
private struct WidgetProgressBorder: View {
    let remaining: Double

    private var ringColor: Color {
        if remaining < 0.10 { return Color(UIColor.systemRed).opacity(0.85) }
        if remaining < 0.25 { return Color(red: 1.0, green: 0.75, blue: 0.2).opacity(0.9) }
        return Color.white.opacity(0.88)
    }

    var body: some View {
        ContainerRelativeShape()
            .strokeBorder(ringColor, lineWidth: 4)
            .clipShape(PieSlice(fraction: remaining))
    }
}

// MARK: - Widget entry view
struct MyAppWidgetEntryView: View {
    var entry: Provider.Entry

    // Progress border shows how much of YOUR personal limit remains.
    private var myRemaining: Double {
        guard entry.myGoalMinutes > 0 else { return 0 }
        let me = entry.members.first { $0.userID == entry.myUserID }
        guard let me else { return 0 }
        let used = min(Double(me.minutesUsed(blockSize: entry.blockSizeMinutes)) / Double(entry.myGoalMinutes), 1.0)
        return 1.0 - used
    }

    var body: some View {
        ZStack {
            WidgetDotGrid()

            if entry.members.isEmpty {
                Text("Open app to start")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entry.members.enumerated()), id: \.element.id) { index, member in
                        WidgetMemberRow(
                            rank: index + 1,
                            member: member,
                            blockSize: entry.blockSizeMinutes,
                            isTop: index == 0
                        )
                        .padding(.vertical, 10)
                        if index < entry.members.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            if entry.myGoalMinutes > 0 {
                WidgetProgressBorder(remaining: myRemaining)
            }
        }
    }
}

struct MyAppWidget: Widget {
    let kind: String = WidgetConstants.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MyAppWidgetEntryView(entry: entry)
                .environment(\.colorScheme, .dark)
                .containerBackground(for: .widget) {
                    Color.black
                }
        }
        .configurationDisplayName("ScreenMates")
        .description("Top friends by screen time today.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
