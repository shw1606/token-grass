import SwiftUI
import TokenGrassCore

/// Sizes the grass to fill the available space — the largest square that lets
/// `weeks × 7` cells fit. Shared by the widget and the app's widget previews so
/// both compute cell size identically.
public struct FittedGrassView: View {
    private let grid: GrassGrid
    private let theme: GrassTheme
    private let spacingRatio: CGFloat
    private let showMonthLabels: Bool

    public init(
        grid: GrassGrid,
        theme: GrassTheme = .githubGreen,
        spacingRatio: CGFloat = 0.18,
        showMonthLabels: Bool = false
    ) {
        self.grid = grid
        self.theme = theme
        self.spacingRatio = spacingRatio
        self.showMonthLabels = showMonthLabels
    }

    public var body: some View {
        GeometryReader { proxy in
            let cell = cellSize(in: proxy.size)
            let spacing = cell * spacingRatio
            content(cell: cell, spacing: spacing)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func content(cell: CGFloat, spacing: CGFloat) -> some View {
        if showMonthLabels {
            GrassChartView(grid: grid, theme: theme, cellSize: cell, spacing: spacing, showMonthLabels: true)
        } else {
            GrassGridView(grid: grid, theme: theme, cellSize: cell, spacing: spacing, cornerRadius: max(1, cell * 0.2))
        }
    }

    private func cellSize(in size: CGSize) -> CGFloat {
        let columns = CGFloat(max(grid.weeks, 1))
        let monthAxisRows: CGFloat = showMonthLabels ? 1.4 : 0
        let widthPer = size.width / (columns + (columns - 1) * spacingRatio)
        let heightPer = size.height / (7 + 6 * spacingRatio + monthAxisRows)
        return max(2, min(widthPer, heightPer))
    }
}
