import SwiftUI
import TokenGrassCore

/// Color ramp for the 5-step grass intensity. Shared by the app and the widget.
/// (Lives outside TokenGrassCore so that module stays SwiftUI-free and headless-testable.)
public enum GrassTheme: String, CaseIterable, Sendable {
    case githubGreen
    case claudeOrange

    public var displayName: String {
        switch self {
        case .githubGreen: return "GitHub Green"
        case .claudeOrange: return "Claude Orange"
        }
    }

    /// Cell color. `onDark` selects a ramp tuned for a dark surface (low → dark,
    /// high → bright, like GitHub's dark theme) plus a visible gray for empty days.
    public func color(for level: GrassLevel, onDark: Bool = false) -> Color {
        guard level != .empty else {
            // Measured from the GitHub reference widget: #2e2f36.
            return onDark ? Color(.sRGB, red: 0.180, green: 0.184, blue: 0.212, opacity: 1) : Color.primary.opacity(0.08)
        }
        let ramp = onDark ? darkRamp : lightRamp
        return ramp[level.rawValue - 1]
    }

    /// Near-black background to pair with `onDark` cells. The GitHub reference
    /// widget's true flat background (cell-edge AA eroded away) measures ~#040404
    /// with a modal #000000, so we use a near-pure black: #050505.
    public static let darkSurface = Color(.sRGB, red: 0.02, green: 0.02, blue: 0.02, opacity: 1)

    // Light surface: pale → deep (GitHub light theme direction).
    private var lightRamp: [Color] {
        switch self {
        case .githubGreen:
            return [
                Color(red: 0.60, green: 0.84, blue: 0.55),
                Color(red: 0.25, green: 0.67, blue: 0.36),
                Color(red: 0.13, green: 0.49, blue: 0.27),
                Color(red: 0.08, green: 0.32, blue: 0.18),
            ]
        case .claudeOrange:
            return [
                Color(red: 0.98, green: 0.80, blue: 0.62),
                Color(red: 0.93, green: 0.58, blue: 0.33),
                Color(red: 0.83, green: 0.40, blue: 0.18),
                Color(red: 0.61, green: 0.27, blue: 0.11),
            ]
        }
    }

    // Dark surface: deep → bright (GitHub dark theme direction).
    private var darkRamp: [Color] {
        switch self {
        case .githubGreen:
            // Exact colors measured from the GitHub reference widget.
            return [
                Color(red: 0.153, green: 0.298, blue: 0.161), // #274c29
                Color(red: 0.227, green: 0.451, blue: 0.231), // #3a733b
                Color(red: 0.357, green: 0.686, blue: 0.357), // #5baf5b
                Color(red: 0.439, green: 0.827, blue: 0.439), // #70d370
            ]
        case .claudeOrange:
            // Claude orange at the GitHub reference's exact luminance steps.
            return [
                Color(red: 0.413, green: 0.190, blue: 0.041), // #69300a
                Color(red: 0.621, green: 0.285, blue: 0.061), // #9e4910
                Color(red: 0.914, green: 0.444, blue: 0.131), // #e97121
                Color(red: 0.936, green: 0.589, blue: 0.357), // #ef965b
            ]
        }
    }
}
