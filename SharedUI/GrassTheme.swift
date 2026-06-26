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
            return onDark ? Color(.sRGB, white: 0.22, opacity: 1) : Color.primary.opacity(0.08)
        }
        let ramp = onDark ? darkRamp : lightRamp
        return ramp[level.rawValue - 1]
    }

    /// Near-black background to pair with `onDark` cells (matches the reference widget).
    public static let darkSurface = Color(.sRGB, red: 0.11, green: 0.11, blue: 0.12, opacity: 1)

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
            return [
                Color(red: 0.05, green: 0.27, blue: 0.16),
                Color(red: 0.00, green: 0.43, blue: 0.20),
                Color(red: 0.15, green: 0.65, blue: 0.25),
                Color(red: 0.22, green: 0.83, blue: 0.33),
            ]
        case .claudeOrange:
            return [
                Color(red: 0.30, green: 0.16, blue: 0.07),
                Color(red: 0.55, green: 0.29, blue: 0.12),
                Color(red: 0.82, green: 0.46, blue: 0.20),
                Color(red: 0.97, green: 0.64, blue: 0.31),
            ]
        }
    }
}
