import SwiftUI
import TokenGrassCore

/// Renders a `GrassGrid` as vector squares — no images, so it stays well under the
/// widget's ~30MB memory budget. Columns left→right (oldest→newest), 7 rows each.
public struct GrassGridView: View {
    private let grid: GrassGrid
    private let theme: GrassTheme
    private let cellSize: CGFloat
    private let spacing: CGFloat
    private let cornerRadius: CGFloat
    private let onDark: Bool

    public init(
        grid: GrassGrid,
        theme: GrassTheme = .githubGreen,
        cellSize: CGFloat = 11,
        spacing: CGFloat = 2.5,
        cornerRadius: CGFloat = 2,
        onDark: Bool = false
    ) {
        self.grid = grid
        self.theme = theme
        self.cellSize = cellSize
        self.spacing = spacing
        self.cornerRadius = cornerRadius
        self.onDark = onDark
    }

    public var body: some View {
        let thresholds = grid.thresholds
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(grid.columns.enumerated()), id: \.offset) { _, column in
                VStack(spacing: spacing) {
                    ForEach(Array(column.enumerated()), id: \.offset) { _, cell in
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(fill(for: cell, thresholds: thresholds))
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
    }

    private func fill(for cell: GrassCell, thresholds: LevelThresholds) -> Color {
        cell.isFuture ? Color.clear : theme.color(for: thresholds.level(for: cell.tokens), onDark: onDark)
    }
}
