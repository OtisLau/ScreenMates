//
//  MyAppWidget.swift
//  MyAppWidget
//
//  Created by Otis Lau on 2025-12-22.
//

import WidgetKit
import SwiftUI
import Foundation

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
    let streak: Int
    let lastUpdate: Date
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), members: [
            .init(id: "A", userID: "A", displayName: "You", blocks: 12, streak: 2, lastUpdate: .now),
            .init(id: "B", userID: "B", displayName: "Josh", blocks: 9, streak: 1, lastUpdate: .now),
            .init(id: "C", userID: "C", displayName: "Yanic", blocks: 3, streak: 0, lastUpdate: .now),
        ], blockSizeMinutes: 1)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh periodically; the app will also explicitly reload timelines when it caches new data.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> SimpleEntry {
        let defaults = UserDefaults(suiteName: WidgetConstants.appGroupSuite)
        let blockSize = defaults?.integer(forKey: WidgetConstants.blockSizeKey) ?? 0
        let blockSizeMinutes = blockSize > 0 ? blockSize : 1

        var members: [CachedMember] = []
        if let data = defaults?.data(forKey: WidgetConstants.cachedLeaderboardKey) {
            members = (try? JSONDecoder().decode([CachedMember].self, from: data)) ?? []
        }

        // Only show a small list for the small widget.
        members = Array(members.prefix(4))

        return SimpleEntry(date: Date(), members: members, blockSizeMinutes: blockSizeMinutes)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let members: [CachedMember]
    let blockSizeMinutes: Int
}

struct MyAppWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ScreenMates")
                .font(.headline)

            if entry.members.isEmpty {
                Text("Open the app to sync your group.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.members) { m in
                        HStack {
                            Text(m.displayName)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(m.blocks * entry.blockSizeMinutes) min")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct MyAppWidget: Widget {
    let kind: String = WidgetConstants.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MyAppWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Group Leaderboard")
        .description("Shows your ScreenMates group and their screen time.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    MyAppWidget()
} timeline: {
    SimpleEntry(date: .now, members: [
        .init(id: "A", userID: "A", displayName: "You", blocks: 12, streak: 2, lastUpdate: .now),
        .init(id: "B", userID: "B", displayName: "Josh", blocks: 9, streak: 1, lastUpdate: .now),
        .init(id: "C", userID: "C", displayName: "Yanic", blocks: 3, streak: 0, lastUpdate: .now),
    ], blockSizeMinutes: 1)
}
