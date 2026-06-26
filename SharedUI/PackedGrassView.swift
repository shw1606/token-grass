import SwiftUI
import TokenGrassCore

/// Edge-to-edge heatmap: 7 fixed rows sized to fill the height, showing as many
/// of the most-recent weeks as fit the width. No labels — just grass. Tuned for a
/// dark surface, matching the GitHub-style home-screen widget look.
public struct PackedGrassView: View {
    private let grid: GrassGrid
    private let theme: GrassTheme
    private let gapRatio: CGFloat

    public init(grid: GrassGrid, theme: GrassTheme = .claudeOrange, gapRatio: CGFloat = 0.18) {
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
            HStack(spacing: gap) {
                ForEach(columns.indices, id: \.self) { c in
                    VStack(spacing: gap) {
                        ForEach(columns[c].indices, id: \.self) { r in
                            let item = columns[c][r]
                            RoundedRectangle(cornerRadius: max(1, cell * 0.22), style: .continuous)
                                .fill(item.isFuture ? Color.clear : theme.color(for: thresholds.level(for: item.tokens), onDark: true))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }
}
