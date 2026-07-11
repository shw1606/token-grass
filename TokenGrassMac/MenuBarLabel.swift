import SwiftUI

/// The status-bar item itself: an optional grass tuft that fills with the
/// 5-hour utilization, plus the 5h (and optionally 7d) percentages. When the
/// weekly percentage is hidden, the 5-hour number is shown larger on its own.
struct MenuBarLabel: View {
    @ObservedObject var service: UsageService
    var showGrass: Bool = true
    var showWeekly: Bool = true

    private var available: Bool { service.lastSync != nil }

    var body: some View {
        HStack(spacing: 4) {
            if showGrass {
                GrassGauge(fill: service.fiveHour / 100)
                    .frame(width: 18, height: 20)
            }
            if showWeekly {
                VStack(alignment: .trailing, spacing: -3) {
                    number(service.fiveHour, size: 13, weight: .bold)     // 5-hour session (top, prominent)
                    number(service.sevenDay, size: 10, weight: .medium)   // 7-day weekly (bottom, subdued)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Weekly hidden → give the 5-hour number the full height.
                number(service.fiveHour, size: 16, weight: .bold)
            }
        }
        .padding(.horizontal, 1)
        .fixedSize()
    }

    private func number(_ pct: Double, size: CGFloat, weight: Font.Weight) -> some View {
        Text(available ? "\(Int(pct.rounded()))%" : "—")
            .font(.system(size: size, weight: weight))
            .monospacedDigit()
    }
}

/// A tuft of upright grass blades that fills orange from the bottom to
/// represent a 0…1 level. Degrades gracefully if the menu bar renders it as a
/// template image: the fill (opaque) still reads darker than the faint blades.
struct GrassGauge: View {
    var fill: Double

    private let orange = Color(red: 0.91, green: 0.44, blue: 0.13)

    var body: some View {
        let level = min(max(fill, 0), 1)
        ZStack {
            GrassBladesShape().fill(Color.primary.opacity(0.25))
            GeometryReader { geo in
                orange
                    .frame(height: geo.size.height * level)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .mask(GrassBladesShape())
        }
    }
}

/// Several tapered blades of varying height leaning both ways — a lush tuft.
struct GrassBladesShape: Shape {
    // (baseX, tipX, topY, halfWidth) in unit coords; y is down, base at y=1.
    // Many overlapping blades of varying height/lean make a dense tuft.
    private let blades: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (0.06, -0.02, 0.40, 0.050),
        (0.17, 0.22, 0.14, 0.052),
        (0.28, 0.21, 0.30, 0.048),
        (0.38, 0.43, 0.04, 0.055),
        (0.48, 0.44, 0.24, 0.050),
        (0.57, 0.61, 0.12, 0.052),
        (0.66, 0.60, 0.34, 0.048),
        (0.76, 0.81, 0.02, 0.055),
        (0.86, 0.82, 0.26, 0.050),
        (0.95, 1.02, 0.16, 0.050),
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        for (baseX, tipX, topY, half) in blades {
            let midY = (1.0 + topY) / 2
            path.move(to: p(baseX - half, 1.0))
            path.addQuadCurve(to: p(tipX, topY), control: p(baseX - half * 0.4, midY))
            path.addQuadCurve(to: p(baseX + half, 1.0), control: p(baseX + half * 0.8, midY))
            path.closeSubpath()
        }
        return path
    }
}
