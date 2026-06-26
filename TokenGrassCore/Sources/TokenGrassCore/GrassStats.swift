import Foundation

public extension GrassGrid {
    /// Real (non-future) cells, oldest → newest.
    var realCells: [GrassCell] { allCells.filter { !$0.isFuture } }

    /// Sum of all token counts in the window.
    var totalTokens: Int { realCells.reduce(0) { $0 + $1.tokens } }

    /// Most recent day's tokens (today).
    var todayTokens: Int { realCells.last?.tokens ?? 0 }

    /// Rolling 7-day total ending today.
    var lastWeekTokens: Int { realCells.suffix(7).reduce(0) { $0 + $1.tokens } }

    /// Number of days with any usage (green cells).
    var activeDayCount: Int { realCells.filter { $0.tokens > 0 }.count }
}

/// A month tick for the chart's top axis, positioned by column.
public struct MonthLabel: Equatable, Sendable {
    public let columnIndex: Int
    public let title: String // "Jun"

    public init(columnIndex: Int, title: String) {
        self.columnIndex = columnIndex
        self.title = title
    }
}

public extension DateGrid {
    /// One label per column where a new month begins (GitHub-style top axis).
    ///
    /// A leading label is dropped when the window starts mid-month and the next
    /// month begins within `minColumnGap` columns — otherwise the partial first
    /// month's label collides with the next one (e.g. "NovDec").
    static func monthLabels(
        for grid: GrassGrid,
        calendar: Calendar = .grass(),
        minColumnGap: Int = 3
    ) -> [MonthLabel] {
        let parser = dayKeyFormatter(calendar: calendar)
        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.timeZone = calendar.timeZone
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        monthFormatter.dateFormat = "MMM"

        var labels: [MonthLabel] = []
        var lastMonth: Int?
        for (index, column) in grid.columns.enumerated() {
            guard
                let key = column.first(where: { $0.dateKey != nil })?.dateKey,
                let date = parser.date(from: key)
            else { continue }
            let month = calendar.component(.month, from: date)
            if month != lastMonth {
                labels.append(MonthLabel(columnIndex: index, title: monthFormatter.string(from: date)))
                lastMonth = month
            }
        }

        if labels.count >= 2, labels[1].columnIndex - labels[0].columnIndex < minColumnGap {
            labels.removeFirst()
        }
        return labels
    }
}

/// Compact human-readable token counts: 999, 1.2k, 1.2M.
public enum TokenFormat {
    public static func compact(_ count: Int) -> String {
        let sign = count < 0 ? "-" : ""
        let value = abs(count)
        switch value {
        case 0..<1_000:
            return "\(sign)\(value)"
        case 1_000..<1_000_000:
            return "\(sign)\(trimmed(Double(value) / 1_000))k"
        default:
            return "\(sign)\(trimmed(Double(value) / 1_000_000))M"
        }
    }

    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }
}
