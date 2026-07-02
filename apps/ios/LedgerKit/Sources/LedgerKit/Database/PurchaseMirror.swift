import ComposableArchitecture
import Foundation

/// Public face of the local purchase mirror for non-TCA callers — the App
/// Intents living in the app target. Resolves the same `databaseClient`
/// dependency the features use, so Siri and the UI can never disagree.
public enum PurchaseMirror {
    public static func summaries() async throws -> [PurchaseSummary] {
        @Dependency(\.databaseClient) var databaseClient
        return try await databaseClient.summaries()
    }

    public static func purchase(id: String) async throws -> Purchase? {
        @Dependency(\.databaseClient) var databaseClient
        return try await databaseClient.purchase(id)
    }

    /// Spending in the calendar month containing `date`, computed from the
    /// mirror — answers work offline and without opening the app.
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

    /// Wire dates are local to the owner's timezone (see `Format`); the month
    /// window has to be cut in the same one.
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
    /// `"2026-03"`.
    public let monthKey: String
    /// `"março"` — reads naturally mid-sentence in dialogs.
    public let monthName: String
    /// `"Março 2026"`.
    public let monthLabel: String
    public let total: Double
    public let purchaseCount: Int
}
