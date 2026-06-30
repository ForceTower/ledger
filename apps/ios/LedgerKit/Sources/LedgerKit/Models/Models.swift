import Foundation

/// Wire types mirroring `packages/shared-types` / `docs/api-contract.md`. All
/// fields are English; money is a plain number (BRL), dates are `YYYY-MM-DD`,
/// times `HH:MM:SS`.

public struct StoreInfo: Codable, Equatable, Sendable {
    public var name: String
    public var legalName: String?
    public var cnpj: String?
    public var address: String?
}

public struct Receipt: Codable, Equatable, Sendable {
    public var number: Int?
    public var series: Int?
    public var accessKey: String
}

public struct PurchaseItem: Codable, Equatable, Sendable, Identifiable {
    public var seq: Int
    public var description: String
    public var code: String
    public var barcode: String?
    public var quantity: Double
    public var unit: String
    public var unitPrice: Double
    public var total: Double
    public var category: Category

    public var id: Int { seq }
}

public struct Totals: Codable, Equatable, Sendable {
    public var itemCount: Int
    public var gross: Double
    public var discount: Double
    public var totalPaid: Double
}

public struct Payment: Codable, Equatable, Sendable, Identifiable {
    public var code: Int?
    public var method: String
    public var amount: Double
    public var change: Double?

    public var id: String { "\(code.map(String.init) ?? "?")-\(method)" }
}

public struct Purchase: Codable, Equatable, Sendable, Identifiable {
    public enum Source: String, Codable, Equatable, Sendable { case nfce, manual }

    public var id: String
    public var date: String
    public var time: String
    public var source: Source
    public var store: StoreInfo
    public var receipt: Receipt?
    public var items: [PurchaseItem]
    public var totals: Totals
    public var payments: [Payment]
    public var taxesTotal: Double?

    /// Items grouped by category, in canonical category order, each group sorted
    /// by descending value — drives the detail screen's sectioned list.
    var itemsByCategory: [(category: Category, items: [PurchaseItem])] {
        let grouped: [Category: [PurchaseItem]] = Dictionary(grouping: items, by: { $0.category })
        let groups: [(category: Category, items: [PurchaseItem])] = grouped.map { key, value in
            (category: key, items: value.sorted { $0.total > $1.total })
        }
        return groups.sorted { $0.category.sortIndex < $1.category.sortIndex }
    }
}

public struct PurchaseSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var store: String
    public var date: String
    public var time: String
    public var totalPaid: Double
    public var itemCount: Int
    public var categories: [Category: Int]

    /// Proportion-bar segments in canonical category order.
    var categorySegments: [(category: Category, count: Int)] {
        let segments: [(category: Category, count: Int)] = categories.map { key, value in
            (category: key, count: value)
        }
        return segments.sorted { $0.category.sortIndex < $1.category.sortIndex }
    }
}
