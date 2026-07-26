import Foundation

public enum Format {
    private static let locale = Locale(identifier: "pt_BR")

    private static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = locale
        f.currencyCode = "BRL"
        return f
    }()

    private static let currencyWhole: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = locale
        f.currencyCode = "BRL"
        f.maximumFractionDigits = 0
        return f
    }()

    public static func brl(_ value: Double) -> String {
        currency.string(from: value as NSNumber) ?? "R$ 0,00"
    }

    /// Rounded to whole reais, for tight spots where the cents do not earn their width.
    public static func brlWhole(_ value: Double) -> String {
        currencyWhole.string(from: value as NSNumber) ?? "R$ 0"
    }

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

    /// "2026-03-01" → "mar" — the axis-label form of a month.
    static func monthShort(fromISO iso: String) -> String {
        guard let date = date(fromISO: iso) else { return iso }
        return monthShortFormatter.string(from: date)
            .replacingOccurrences(of: ".", with: "")
            .lowercased(with: locale)
    }

    private static let monthShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "LLL"
        return f
    }()

    /// "yyyy-MM" of a date in the ledger's home timezone.
    public static func monthKey(of date: Date) -> String {
        monthKeyFormatter.string(from: date)
    }

    private static let monthKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Sao_Paulo")
        f.dateFormat = "yyyy-MM"
        return f
    }()

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

    static func longDateTime(date iso: String, time: String) -> String {
        let day = date(fromISO: iso).map { dayMonthYearFormatter.string(from: $0) } ?? iso
        let hm = String(time.prefix(5))
        return "\(day) · \(hm)"
    }

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

    static func unitPrice(_ value: Double, unit: String) -> String {
        "\(brl(value))/\(unit)"
    }
}
