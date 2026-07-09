import SwiftUI
import TokenGrassCore

/// Which layout the Mac menu shows the usage history in. Mac-only setting.
enum GrassDisplayMode: String {
    case grass, calendar
}

/// A vertical, month-by-month calendar: same underlying usage data and color
/// scale as the grass heatmap, but laid out as familiar calendar pages (month
/// header, weekday row, day-numbered cells) stacked top-to-bottom, most recent
/// month first.
struct MonthCalendarView: View {
    let grid: GrassGrid
    let theme: GrassTheme

    private let calendar = Calendar.grass()
    private let columnSpacing: CGFloat = 2
    private let contentPadding: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            // Cell size derived from the actual width we're given, so the 7
            // columns always span edge-to-edge — no leftover gap, no need to
            // hardcode a size that only fits one particular popover width.
            let cellSize = self.cellSize(for: proxy.size.width)
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(monthKeys, id: \.self) { monthKey in
                            monthBlock(monthKey, cellSize: cellSize).id(monthKey)
                        }
                    }
                    .padding(contentPadding)
                }
                .scrollIndicators(.hidden)
                // Hiding the indicator doesn't remove the scroll view's own
                // implicit content margin (leaves a few extra points on the
                // trailing edge even with no visible scrollbar) — zero it
                // explicitly so left/right padding actually matches.
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .onAppear {
                    // Months are oldest-first; land on the most recent one
                    // (the last in the list) so the current month is visible
                    // right away instead of requiring a scroll down.
                    if let latest = monthKeys.last {
                        scrollProxy.scrollTo(latest, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func cellSize(for containerWidth: CGFloat) -> CGFloat {
        // Exact (unrounded) division — flooring to a whole point left a few
        // points of unclaimed space that piled up on one side instead of
        // splitting evenly, since the grid isn't centered. A fractional cell
        // size renders fine and makes the 7 columns land exactly edge-to-edge.
        let available = containerWidth - contentPadding * 2 - columnSpacing * 6
        return max(10, available / 7)
    }

    // MARK: - Data

    private var thresholds: LevelThresholds { grid.thresholds }

    private var cellsByDate: [String: GrassCell] {
        Dictionary(uniqueKeysWithValues: grid.allCells.compactMap { cell in
            cell.dateKey.map { ($0, cell) }
        })
    }

    /// "yyyy-MM" keys present in the grid, oldest first.
    private var monthKeys: [String] {
        Set(cellsByDate.keys.map { String($0.prefix(7)) }).sorted(by: <)
    }

    // MARK: - Rendering

    @ViewBuilder private func monthBlock(_ monthKey: String, cellSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(monthTitle(monthKey))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            weekdayHeader(cellSize: cellSize)
            let weeks = weeksInMonth(monthKey)
            VStack(spacing: columnSpacing) {
                ForEach(weeks.indices, id: \.self) { row in
                    HStack(spacing: columnSpacing) {
                        ForEach(weeks[row].indices, id: \.self) { col in
                            dayCell(weeks[row][col], cellSize: cellSize)
                        }
                    }
                }
            }
        }
    }

    private func weekdayHeader(cellSize: CGFloat) -> some View {
        HStack(spacing: columnSpacing) {
            ForEach(["일", "월", "화", "수", "목", "금", "토"], id: \.self) { label in
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: cellSize)
            }
        }
    }

    @ViewBuilder private func dayCell(_ day: DayCell?, cellSize: CGFloat) -> some View {
        if let day {
            Text("\(day.dayNumber)")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(day.isFuture ? Color.secondary.opacity(0.35) : .white.opacity(0.92))
                .frame(width: cellSize, height: cellSize)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(day.isFuture ? Color.clear : color(for: day))
                )
        } else {
            Color.clear.frame(width: cellSize, height: cellSize)
        }
    }

    private func color(for day: DayCell) -> Color {
        theme.color(for: thresholds.level(for: day.tokens), onDark: true)
    }

    // MARK: - Month grid construction

    private struct DayCell {
        let dayNumber: Int
        let tokens: Int
        let isFuture: Bool
    }

    private func weeksInMonth(_ monthKey: String) -> [[DayCell?]] {
        guard
            let year = Int(monthKey.prefix(4)),
            let month = Int(monthKey.suffix(2)),
            let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
            let range = calendar.range(of: .day, in: .month, for: monthStart)
        else { return [] }

        let todayStart = calendar.startOfDay(for: Date())
        let formatter = Self.dayKeyFormatter(calendar: calendar)
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells: [DayCell?] = Array(repeating: nil, count: leadingBlanks)
        for day in range {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
            let key = formatter.string(from: date)
            let tokens = cellsByDate[key]?.tokens ?? 0
            cells.append(DayCell(dayNumber: day, tokens: tokens, isFuture: date > todayStart))
        }
        while cells.count % 7 != 0 { cells.append(nil) }

        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private func monthTitle(_ monthKey: String) -> String {
        guard
            let year = Int(monthKey.prefix(4)),
            let month = Int(monthKey.suffix(2)),
            let date = calendar.date(from: DateComponents(year: year, month: month, day: 1))
        else { return monthKey }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: date)
    }

    private static func dayKeyFormatter(calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}
