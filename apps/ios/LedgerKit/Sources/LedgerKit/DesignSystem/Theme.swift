import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    static func adaptive(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        let l = UIColor(light)
        let d = UIColor(dark)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? d : l })
        #else
        return light
        #endif
    }
}

// MARK: - Brand

extension Color {
    static let appAccent = Color.adaptive(light: Color(hex: 0x0E7C74), dark: Color(hex: 0x2FD3C3))
    static let appAccentTint = Color.adaptive(
        light: Color(hex: 0x0E7C74, alpha: 0.12),
        dark: Color(hex: 0x2FD3C3, alpha: 0.16)
    )
    static let appAccentForeground = Color.adaptive(light: .white, dark: Color(hex: 0x04302B))
}

// MARK: - Hero & gradients

extension Color {
    static let heroInk = Color(hex: 0xEAFBF8)
    static let heroInkSecondary = Color(hex: 0xE8FBF8, alpha: 0.72)
}

enum AppGradient {
    static let accent = LinearGradient(
        colors: [
            .adaptive(light: Color(hex: 0x17B3A5), dark: Color(hex: 0x39E3D3)),
            .adaptive(light: Color(hex: 0x0C736B), dark: Color(hex: 0x18A99B)),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let hero = RadialGradient(
        stops: [
            .init(color: .adaptive(light: Color(hex: 0x1BC3B3), dark: Color(hex: 0x12B7A8)), location: 0),
            .init(color: .adaptive(light: Color(hex: 0x0E8E83), dark: Color(hex: 0x0B7E74)), location: 0.42),
            .init(color: .adaptive(light: Color(hex: 0x075F58), dark: Color(hex: 0x053E3A)), location: 1),
        ],
        center: UnitPoint(x: 0.12, y: 0.08),
        startRadius: 0,
        endRadius: 460
    )
}

// MARK: - Semantic surfaces

extension Color {
    static var appBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(white: 0.95)
        #endif
    }

    static var appElevated: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        .white
        #endif
    }

    static var appFill: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemFill)
        #else
        Color(white: 0.9)
        #endif
    }

    static var appFillSubtle: Color {
        #if canImport(UIKit)
        Color(uiColor: .quaternarySystemFill)
        #else
        Color(white: 0.93)
        #endif
    }

    static var appSeparator: Color {
        #if canImport(UIKit)
        Color(uiColor: .separator)
        #else
        Color(white: 0.8)
        #endif
    }

    static var label3: Color {
        #if canImport(UIKit)
        Color(uiColor: .tertiaryLabel)
        #else
        .secondary
        #endif
    }
}

// MARK: - Theme override

public enum AppTheme: String, CaseIterable, Equatable, Sendable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: "Sistema"
        case .light: "Claro"
        case .dark: "Escuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
