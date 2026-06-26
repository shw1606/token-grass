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

    public func color(for level: GrassLevel) -> Color {
        switch level {
        case .empty:
            // Adaptive faint fill that reads correctly in both light and dark mode.
            return Color.primary.opacity(0.08)
        case .one, .two, .three, .four:
            return ramp[level.rawValue - 1]
        }
    }

    private var ramp: [Color] {
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
}
