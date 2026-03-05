import WidgetKit
import SwiftUI
import Foundation

// Keys shared with the main app via App Group storage
private enum WidgetConstants {
    static let kind = "ScreenMatesGroupWidget"
    static let appGroupSuite = "group.com.otishlau.screenmates"
    static let cachedLeaderboardKey = "CachedLeaderboardData"
    static let blockSizeKey = "SharedBlockSizeMinutes" // written by main app on launch
}

// What we store for each person in the cached leaderboard
struct CachedMember: Codable, Identifiable {
    let id: String
    let userID: String
    let displayName: String
    let blocks: Int      // raw block count — multiply by blockSize to get minutes
    let lastUpdate: Date

    // Format minutes into "1h 15min" or "45min" etc.
    func formattedTime(blockSize: Int) -> String {
        let totalMinutes = blocks * blockSize
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)min"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)min"
        }
    }
}

// Reads cached group data from App Group storage and builds a timeline entry
struct Provider: TimelineProvider {

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), members: [], blockSizeMinutes: 15)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry = loadEntry()
        // Self-refresh every 15 minutes as a fallback.
        // The main app and extension also call WidgetCenter.reloadTimelines() when new data arrives.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    // Read group members and block size from the shared App Group storage
    private func loadEntry() -> SimpleEntry {
        let defaults = UserDefaults(suiteName: WidgetConstants.appGroupSuite)

        // Read the block size the main app mirrored in (1 in test mode, 15 in production)
        let storedBlockSize = defaults?.integer(forKey: WidgetConstants.blockSizeKey) ?? 0
        let blockSize = storedBlockSize > 0 ? storedBlockSize : 15 // fall back to production size

        var members: [CachedMember] = []
        if let data = defaults?.data(forKey: WidgetConstants.cachedLeaderboardKey) {
            members = (try? JSONDecoder().decode([CachedMember].self, from: data)) ?? []
        }

        return SimpleEntry(date: Date(), members: Array(members.prefix(4)), blockSizeMinutes: blockSize)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let members: [CachedMember]
    let blockSizeMinutes: Int  // passed through so the view can convert blocks → minutes correctly
}

// The actual widget UI
struct MyAppWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ScreenMates")
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)

            if entry.members.isEmpty {
                Text("Open the app to get started.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // One line per person: "Otis  1h 15min"
                ForEach(entry.members) { member in
                    HStack {
                        Text(member.displayName)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(member.formattedTime(blockSize: entry.blockSizeMinutes))
                            .font(.caption)
                            .bold()
                            .monospacedDigit()
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

struct MyAppWidget: Widget {
    let kind: String = WidgetConstants.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MyAppWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("ScreenMates Group")
        .description("See your group's screen time today.")
        .supportedFamilies([.systemSmall])
    }
}
