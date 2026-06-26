import SwiftUI
import TokenGrassCore

/// Edge-to-edge heatmap: 7 fixed rows sized to fill the height, showing as many
/// of the most-recent weeks as fit the width. No labels — just grass. Tuned for a
/// dark surface, matching the GitHub-style home-screen widget look.
///
/// Pixel-matched to the reference widget: the four grid-corner cells round their
/// *outward* corner to ~0.74·cell so the grid hugs the widget's rounded rect,
/// while every other corner uses the normal ~0.135·cell radius.
public struct PackedGrassView: View {
    private let grid: GrassGrid
    private let theme: GrassTheme
    private let gapRatio: CGFloat

    // Nudged up slightly so SwiftUI's .continuous corners *render* at the reference's
    // measured radii (0.135 inner / 0.74 outward of a cell).
    private let innerRadiusRatio: CGFloat = 0.15
    private let cornerCellRadiusRatio: CGFloat = 0.77

    public init(grid: GrassGrid, theme: GrassTheme = .claudeOrange, gapRatio: CGFloat = 0.26) {
        self.grid = grid
        self.theme = theme
        self.gapRatio = gapRatio
    }

    public var body: some View {
        let thresholds = grid.thresholds
        GeometryReader { proxy in
            let cell = proxy.size.height / (7 + 6 * gapRatio) // fill height with 7 rows
            let gap = cell * gapRatio
            let stride = cell + gap
            let maxColumns = max(1, Int((proxy.size.width + gap) / stride))
            let columns = Array(grid.columns.suffix(maxColumns))
            let lastCol = columns.count - 1
            let inner = cell * innerRadiusRatio
            let outer = cell * cornerCellRadiusRatio

            HStack(spacing: gap) {
                ForEach(columns.indices, id: \.self) { c in
                    VStack(spacing: gap) {
                        ForEach(columns[c].indices, id: \.self) { r in
                            shape(col: c, row: r, lastCol: lastCol, inner: inner, outer: outer)
                                .fill(color(for: columns[c][r], thresholds: thresholds))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }

    private func color(for item: GrassCell, thresholds: LevelThresholds) -> Color {
        // Future days render as empty so the grid stays a solid rounded block.
        let level = item.isFuture ? GrassLevel.empty : thresholds.level(for: item.tokens)
        return theme.color(for: level, onDark: true)
    }

    private func shape(col: Int, row: Int, lastCol: Int, inner: CGFloat, outer: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius:     (col == 0 && row == 0) ? outer : inner,
            bottomLeadingRadius:  (col == 0 && row == 6) ? outer : inner,
            bottomTrailingRadius: (col == lastCol && row == 6) ? outer : inner,
            topTrailingRadius:    (col == lastCol && row == 0) ? outer : inner,
            style: .continuous
        )
    }
}
