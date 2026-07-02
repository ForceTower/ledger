import Foundation

/// Brazilian-Portuguese, BRL formatting for user-facing copy. Identifiers stay
/// English; only the rendered strings are localized to the owner's locale.
public enum Format {
    private static let locale = Locale(identifier: "pt_BR")

    private static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = locale
        f.currencyCode = "BRL"
        return f
    }()

    /// `1234.5` → `R$ 1.234,50`.
    public static func brl(_ value: Double) -> String {
        currency.string(from: value as NSNumber) ?? "R$ 0,00"
    }

    /// Parses a `YYYY-MM-DD` wire date into a `Date` at noon UTC (date-only).
    public static func date(fromISO iso: String) -> Date? {
        isoDateParser.date(from: iso)
    }

    private static let isoDateParser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Sao_Paulo")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// `2026-03-26` → `Março 2026` (capitalized).
    static func monthYear(fromISO iso: String) -> String {
        guard let date = date(fromISO: iso) else { return iso }
        return monthYearFormatter.string(from: date).capitalized(with: locale)
    }

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    /// `2026-03-26` → `março` (lowercased, no year).
    static func monthName(fromISO iso: String) -> String {
        guard let date = date(fromISO: iso) else { return iso }
        return monthNameFormatter.string(from: date)
    }

    private static let monthNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "LLLL"
        return f
    }()

    /// `2026-03-26` → `26 mar`.
    public static func dayMonth(fromISO iso: String) -> String {
        guard let date = date(fromISO: iso) else { return iso }
        return dayMonthFormatter.string(from: date)
    }

    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "d MMM"
        return f
    }()

    /// `2026-03-26`, `14:44:08` → `26 mar 2026 · 14:44`.
    static func longDateTime(date iso: String, time: String) -> String {
        let day = date(fromISO: iso).map { dayMonthYearFormatter.string(from: $0) } ?? iso
        let hm = String(time.prefix(5))
        return "\(day) · \(hm)"
    }

    /// `2026-03-26` → `26 mar 2026`.
    public static func dayMonthYear(_ iso: String) -> String {
        guard let date = date(fromISO: iso) else { return iso }
        return dayMonthYearFormatter.string(from: date)
    }

    private static let dayMonthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    /// `1.252`, `kg` → `1,252 kg`; integer quantities drop the decimals.
    static func quantity(_ value: Double, unit: String) -> String {
        let isWhole = value.rounded() == value
        let number: String
        if isWhole {
            number = String(Int(value))
        } else {
            number = quantityFormatter.string(from: value as NSNumber) ?? "\(value)"
        }
        return "\(number) \(unit)"
    }

    private static let quantityFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = locale
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 3
        return f
    }()

    /// `34.9`, `kg` → `R$ 34,90/kg`.
    static func unitPrice(_ value: Double, unit: String) -> String {
        "\(brl(value))/\(unit)"
    }
}
