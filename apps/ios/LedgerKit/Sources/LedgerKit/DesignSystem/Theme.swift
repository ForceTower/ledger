import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Color tokens ported from the Caderneta design. The accent is teal; greys and
/// backgrounds reuse the platform's semantic colors so light/dark and dynamic
/// type come for free. Category and accent colors carry explicit light/dark
/// variants to match the design.
extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// A color that resolves to `light` or `dark` based on the current trait.
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
