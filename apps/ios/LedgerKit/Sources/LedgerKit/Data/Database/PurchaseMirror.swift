import ComposableArchitecture
import Foundation

public enum PurchaseMirror {
    public static func summaries() async throws -> [PurchaseSummary] {
        @Dependency(\.purchasesRepository) var purchases
        return try await purchases.summaries()
    }

    public static func purchase(id: String) async throws -> Purchase? {
        @Dependency(\.purchasesRepository) var purchases
        return try await purchases.purchase(id: id)
    }

    public static func monthlySpending(containing date: Date) async throws -> MonthlySpending {
        let key = Format.monthKey(of: date)
        let inMonth = try await summaries().filter { $0.date.hasPrefix(key) }
        return MonthlySpending(
            monthKey: key,
            monthName: Format.monthName(fromISO: "\(key)-01"),
            monthLabel: Format.monthYear(fromISO: "\(key)-01"),
            total: inMonth.reduce(0) { $0 + $1.totalPaid },
            purchaseCount: inMonth.count
        )
    }
}

public struct MonthlySpending: Equatable, Sendable {
    public let monthKey: String
    public let monthName: String
    public let monthLabel: String
    public let total: Double
    public let purchaseCount: Int
}
