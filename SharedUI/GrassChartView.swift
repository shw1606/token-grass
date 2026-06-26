import SwiftUI
import TokenGrassCore

/// Grass grid with a GitHub-style month axis on top. Used where there's room
/// (app, medium/large widgets). Small widgets use the bare `GrassGridView`.
public struct GrassChartView: View {
    private let grid: GrassGrid
    private let theme: GrassTheme
    private let cellSize: CGFloat
    private let spacing: CGFloat
    private let showMonthLabels: Bool

    public init(
        grid: GrassGrid,
        theme: GrassTheme = .githubGreen,
        cellSize: CGFloat = 11,
        spacing: CGFloat = 2.5,
        showMonthLabels: Bool = true
    ) {
        self.grid = grid
        self.theme = theme
        self.cellSize = cellSize
        self.spacing = spacing
        self.showMonthLabels = showMonthLabels
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showMonthLabels {
                monthAxis
            }
            GrassGridView(
                grid: grid,
                theme: theme,
                cellSize: cellSize,
                spacing: spacing,
                cornerRadius: max(1, cellSize * 0.2)
            )
        }
    }

    private var columnStride: CGFloat { cellSize + spacing }

    private var monthAxis: some View {
        let labels = DateGrid.monthLabels(for: grid)
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(height: max(9, cellSize)) // reserve the axis row
            ForEach(labels.indices, id: \.self) { index in
                Text(labels[index].title)
                    .font(.system(size: max(7, cellSize * 0.85), weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(x: CGFloat(labels[index].columnIndex) * columnStride)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}
