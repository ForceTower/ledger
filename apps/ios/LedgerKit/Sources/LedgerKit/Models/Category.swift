import SwiftUI

/// Wire-level category slugs (English, per `docs/api-contract.md`). Display
/// labels are Brazilian Portuguese — the owner's locale — and each carries the
/// accent color from the Caderneta design.
public enum Category: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
    case produce
    case meat
    case dairyDeli = "dairy_deli"
    case bakery
    case grocery
    case beverages
    case snacksSweets = "snacks_sweets"
    case frozen
    case cleaning
    case hygiene
    case pet
    case household
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .produce: "Hortifrúti"
        case .meat: "Carnes"
        case .dairyDeli: "Frios e Laticínios"
        case .bakery: "Padaria"
        case .grocery: "Mercearia"
        case .beverages: "Bebidas"
        case .snacksSweets: "Doces e Snacks"
        case .frozen: "Congelados"
        case .cleaning: "Limpeza"
        case .hygiene: "Higiene"
        case .pet: "Pet"
        case .household: "Bazar e Utilidades"
        case .other: "Outros"
        }
    }

    public var color: Color {
        switch self {
        case .meat: .adaptive(light: Color(hex: 0xD9544D), dark: Color(hex: 0xF26B63))
        case .grocery: .adaptive(light: Color(hex: 0xE0A33E), dark: Color(hex: 0xF0B658))
        case .produce: .adaptive(light: Color(hex: 0x56AA5B), dark: Color(hex: 0x6FC274))
        case .beverages: Color(hex: 0x4C8DE0)
        case .cleaning: Color(hex: 0x9B72CF)
        case .hygiene: Color(hex: 0xDB6FA6)
        case .bakery: Color(hex: 0xC9894B)
        case .dairyDeli: Color(hex: 0x46AEBE)
        case .snacksSweets: Color(hex: 0xE07A5F)
        case .frozen: Color(hex: 0x5AA9D6)
        case .pet: Color(hex: 0x7E8AA2)
        case .household: Color(hex: 0x9A8C98)
        case .other: .secondary
        }
    }

    /// Canonical display order so proportion bars and legends stay consistent.
    var sortIndex: Int { Category.allCases.firstIndex(of: self) ?? 0 }
}
