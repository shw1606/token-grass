import Foundation

/// One square in the heatmap.
public struct GrassCell: Hashable, Sendable {
    /// "yyyy-MM-dd" for real days; `nil` for future padding cells in the last week.
    public let dateKey: String?
    public let tokens: Int
    public let isFuture: Bool

    public init(dateKey: String?, tokens: Int, isFuture: Bool) {
        self.dateKey = dateKey
        self.tokens = tokens
        self.isFuture = isFuture
    }
}

/// Column-major heatmap: `columns` runs oldest (left) → newest (right); each column
/// holds exactly 7 cells, top → bottom by weekday starting at the calendar's first weekday.
public struct GrassGrid: Sendable {
    public let columns: [[GrassCell]]
    public let weeks: Int

    public init(columns: [[GrassCell]], weeks: Int) {
        self.columns = columns
        self.weeks = weeks
    }

    public var allCells: [GrassCell] { columns.flatMap { $0 } }

    /// Percentile thresholds computed over the real (non-future) days in this grid.
    public var thresholds: LevelThresholds {
        LevelThresholds.compute(from: allCells.filter { !$0.isFuture }.map(\.tokens))
    }
}

public enum DateGrid {
    /// Build a `weeks × 7` grid ending on the week that contains `today`.
    /// The last column is the current week; days after `today` are future padding.
    public static func makeGrid(
        usage: [String: Int],
        today: Date = Date(),
        weeks: Int = 53,
        calendar: Calendar = .grass()
    ) -> GrassGrid {
        guard weeks > 0 else { return GrassGrid(columns: [], weeks: 0) }
        let calendar = calendar
        let todayStart = calendar.startOfDay(for: today)
        let weekday = calendar.component(.weekday, from: todayStart)
        let offsetFromWeekStart = (weekday - calendar.firstWeekday + 7) % 7

        guard
            let currentWeekStart = calendar.date(byAdding: .day, value: -offsetFromWeekStart, to: todayStart),
            let gridStart = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: currentWeekStart)
        else {
            return GrassGrid(columns: [], weeks: 0)
        }

        let formatter = dayKeyFormatter(calendar: calendar)
        var columns: [[GrassCell]] = []
        columns.reserveCapacity(weeks)

        for col in 0..<weeks {
            guard let weekStart = calendar.date(byAdding: .day, value: 7 * col, to: gridStart) else { continue }
            var cells: [GrassCell] = []
            cells.reserveCapacity(7)
            for row in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: row, to: weekStart) else { continue }
                if day > todayStart {
                    cells.append(GrassCell(dateKey: nil, tokens: 0, isFuture: true))
                } else {
                    let key = formatter.string(from: day)
                    cells.append(GrassCell(dateKey: key, tokens: usage[key] ?? 0, isFuture: false))
                }
            }
            columns.append(cells)
        }
        return GrassGrid(columns: columns, weeks: weeks)
    }

    /// Ordered "yyyy-MM-dd" keys for every real (non-future) day in the grid window.
    /// Shared by the demo generator so the demo fills exactly the rendered window.
    public static func realDateKeys(
        today: Date = Date(),
        weeks: Int = 53,
        calendar: Calendar = .grass()
    ) -> [String] {
        makeGrid(usage: [:], today: today, weeks: weeks, calendar: calendar)
            .allCells.compactMap { $0.dateKey }
    }

    static func dayKeyFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
