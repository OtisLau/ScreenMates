import WidgetKit
import SwiftUI
import Foundation

// Keys shared with the main app via App Group storage
private enum WidgetConstants {
    static let kind = "ScreenMatesGroupWidget"
    static let appGroupSuite = "group.com.otishlau.screenmates"
    static let cachedLeaderboardKey = "CachedLeaderboardData"
}

// What we store for each person in the cached leaderboard
struct CachedMember: Codable, Identifiable {
    let id: String
    let userID: String
    let displayName: String
    let blocks: Int         // number of 15-min blocks used today
    let lastUpdate: Date

    // Convert blocks to a human-readable time string like "1h 15min" or "45min"
    var formattedTime: String {
        let totalMinutes = blocks * 15
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
        // Placeholder shown while the widget loads for the first time
        SimpleEntry(date: Date(), members: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry = loadEntry()
        // Self-refresh every 15 minutes as a fallback.
        // The main app also calls WidgetCenter.reloadTimelines() whenever fresh data arrives,
        // so in practice the widget updates much more frequently than this.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    // Read the group member list from the shared App Group storage the main app writes to
    private func loadEntry() -> SimpleEntry {
        let defaults = UserDefaults(suiteName: WidgetConstants.appGroupSuite)
        var members: [CachedMember] = []

        if let data = defaults?.data(forKey: WidgetConstants.cachedLeaderboardKey) {
            members = (try? JSONDecoder().decode([CachedMember].self, from: data)) ?? []
        }

        // Only show the first 4 people — widget space is limited
        return SimpleEntry(date: Date(), members: Array(members.prefix(4)))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let members: [CachedMember]
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
                // Shown before anyone has joined a group or synced data
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
                        Text(member.formattedTime)
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
