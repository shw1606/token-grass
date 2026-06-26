import WidgetKit
import Foundation
import TokenGrassCore

struct GrassEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
    let isDemo: Bool
}

/// Pure renderer feed: reads the snapshot the app wrote to the App Group.
/// No network here — the widget can't run URLSession. Falls back to demo data
/// when nothing has been synced yet (DESIGN §3.2, §5.1).
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> GrassEntry {
        GrassEntry(date: Date(), snapshot: DemoData.snapshot(), isDemo: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (GrassEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GrassEntry>) -> Void) {
        // Grass is day-granular, so one refresh at the next local midnight is enough.
        let nextMidnight = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(60 * 60)
        completion(Timeline(entries: [currentEntry()], policy: .after(nextMidnight)))
    }

    private func currentEntry() -> GrassEntry {
        if let store = AppGroupStore(), let snapshot = store.load() {
            return GrassEntry(date: Date(), snapshot: snapshot, isDemo: false)
        }
        return GrassEntry(date: Date(), snapshot: DemoData.snapshot(), isDemo: true)
    }
}
