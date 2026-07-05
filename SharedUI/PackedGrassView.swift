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

    public init(grid: GrassGrid, theme: GrassTheme = .claudeOrange, gapRatio: CGFloat = 0.28) {
        self.grid = grid
        self.theme = theme
        self.gapRatio = gapRatio
    }

    public var body: some View {
        let thresholds = grid.thresholds
        GeometryReader { proxy in
            let g = gapRatio
            // Fill the WIDTH (like GitHub): use the fewest columns whose square
            // cells span the full width while still fitting 7 rows in the height.
            // A wide widget gets more (smaller) columns and a little vertical
            // margin; a square widget lands on 7 columns filling both axes.
            let cellByHeight = proxy.size.height / (7 + 6 * g)
            let needed = (proxy.size.width / cellByHeight + g) / (1 + g)
            let nCols = max(1, min(Int(needed.rounded(.up)), grid.columns.count))
            let cell = proxy.size.width / (CGFloat(nCols) + CGFloat(nCols - 1) * g)
            let gap = cell * g
            let columns = Array(grid.columns.suffix(nCols))
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
            // Grid fills the width exactly; center the (possibly shorter) stack
            // vertically so the top/bottom margins are even.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func color(for item: GrassCell, thresholds: LevelThresholds) -> Color {
        // Future days in the current week render blank (no cell), like GitHub —
        // the current week is a short stub at the right edge, not a full column.
        guard !item.isFuture else { return .clear }
        return theme.color(for: thresholds.level(for: item.tokens), onDark: true)
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
