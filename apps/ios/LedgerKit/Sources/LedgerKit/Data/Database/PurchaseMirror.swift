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
        let key = monthKey.string(from: date)
        let inMonth = try await summaries().filter { $0.date.hasPrefix(key) }
        return MonthlySpending(
            monthKey: key,
            monthName: Format.monthName(fromISO: "\(key)-01"),
            monthLabel: Format.monthYear(fromISO: "\(key)-01"),
            total: inMonth.reduce(0) { $0 + $1.totalPaid },
            purchaseCount: inMonth.count
        )
    }

    private static let monthKey: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Sao_Paulo")
        f.dateFormat = "yyyy-MM"
        return f
    }()
}

public struct MonthlySpending: Equatable, Sendable {
    public let monthKey: String
    public let monthName: String
    public let monthLabel: String
    public let total: Double
    public let purchaseCount: Int
}
