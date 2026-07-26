import Foundation

/// Everything the Insights screen shows, derived offline from the mirrored purchases
/// of the reference month (the most recent month with data) and the five before it.
struct InsightsSnapshot: Equatable {
    struct Slice: Equatable, Identifiable {
        var category: Category?
        var label: String
        var amount: Double
        var percent: Int

        var id: String { label }
    }

    struct MonthSpend: Equatable, Identifiable {
        var key: String
        var label: String
        var total: Double
        var isReference: Bool

        var id: String { key }
    }

    struct Highlight: Equatable {
        var category: Category
        var percent: Int
        var delta: Double
        var previousMonthName: String

        var rose: Bool { delta > 0 }
    }

    struct BiggestPurchase: Equatable {
        var store: String
        var date: String
        var amount: Double
    }

    struct PriceRadar: Equatable {
        struct Point: Equatable, Identifiable {
            var monthKey: String
            var label: String
            var price: Double

            var id: String { monthKey }
        }

        var productName: String
        var unit: String
        var currentPrice: Double
        var changePercent: Int
        var sinceLabel: String
        var points: [Point]
    }

    struct StoreRank: Equatable, Identifiable {
        var rank: Int
        var name: String
        var amount: Double
        var fraction: Double

        var id: Int { rank }
    }

    struct WeekdaySpend: Equatable, Identifiable {
        var index: Int
        var letter: String
        var total: Double
        var rank: Int

        var id: Int { index }
    }

    var monthKey: String
    var monthName: String
    var total: Double
    var purchaseCount: Int
    var slices: [Slice]
    var months: [MonthSpend]
    var trendPercent: Int?
    var previousMonthLabel: String?
    var highlight: Highlight?
    var averagePerPurchase: Double
    var savings: Double
    var biggest: BiggestPurchase?
    var dailyPace: Double
    var priceRadar: PriceRadar?
    var topStores: [StoreRank]
    var weekdays: [WeekdaySpend]
    var topWeekdayName: String?
}

extension InsightsSnapshot {
    static let windowMonthCount = 6

    private static let weekdayLetters = ["D", "S", "T", "Q", "Q", "S", "S"]
    private static let weekdayNames = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current
        return calendar
    }()

    init?(purchases: [Purchase], now: Date) {
        guard let monthKey = purchases.map({ String($0.date.prefix(7)) }).max() else { return nil }
        let inMonth = purchases.filter { $0.date.hasPrefix(monthKey) }
        let previousKey = Self.monthKey(at: Self.monthIndex(of: monthKey) - 1)
        let inPrevious = purchases.filter { $0.date.hasPrefix(previousKey) }

        self.monthKey = monthKey
        monthName = Format.monthName(fromISO: "\(monthKey)-01")
        total = inMonth.reduce(0) { $0 + $1.totals.totalPaid }
        purchaseCount = inMonth.count
        slices = Self.slices(of: inMonth)
        months = Self.monthWindow(purchases: purchases, endingAt: monthKey)

        let previousTotal = inPrevious.reduce(0) { $0 + $1.totals.totalPaid }
        if previousTotal > 0 {
            trendPercent = Int(((total - previousTotal) / previousTotal * 100).rounded())
            previousMonthLabel = Format.monthShort(fromISO: "\(previousKey)-01")
        }

        highlight = Self.highlight(current: inMonth, previous: inPrevious, previousKey: previousKey)
        averagePerPurchase = purchaseCount > 0 ? total / Double(purchaseCount) : 0
        savings = inMonth.reduce(0) { $0 + $1.totals.discount }
        biggest = inMonth
            .max { $0.totals.totalPaid < $1.totals.totalPaid }
            .map { BiggestPurchase(store: $0.store.name, date: $0.date, amount: $0.totals.totalPaid) }
        dailyPace = total / Double(Self.dayCount(of: monthKey, now: now))
        priceRadar = Self.priceRadar(purchases: purchases)
        topStores = Self.topStores(of: inMonth)
        (weekdays, topWeekdayName) = Self.weekdays(of: inMonth)
    }

    // MARK: - Month arithmetic

    private static func monthIndex(of key: String) -> Int {
        let year = Int(key.prefix(4)) ?? 0
        let month = Int(key.suffix(2)) ?? 1
        return year * 12 + month - 1
    }

    private static func monthKey(at index: Int) -> String {
        String(format: "%04d-%02d", index / 12, index % 12 + 1)
    }

    private static func dayCount(of monthKey: String, now: Date) -> Int {
        if monthKey == Format.monthKey(of: now) {
            return max(calendar.component(.day, from: now), 1)
        }
        guard
            let monthStart = Format.date(fromISO: "\(monthKey)-01"),
            let days = calendar.range(of: .day, in: .month, for: monthStart)
        else { return 30 }
        return days.count
    }

    // MARK: - Cards

    private static func slices(of purchases: [Purchase]) -> [Slice] {
        var totals: [Category: Double] = [:]
        for item in purchases.flatMap(\.items) {
            totals[item.category, default: 0] += item.total
        }
        let overall = totals.values.reduce(0, +)
        guard overall > 0 else { return [] }

        let ranked = totals
            .filter { $0.key != .other }
            .sorted { $0.value > $1.value }
        let top = ranked.prefix(4)
        let rest = ranked.dropFirst(4).reduce(0) { $0 + $1.value } + (totals[.other] ?? 0)

        let percent = { (amount: Double) in Int((amount / overall * 100).rounded()) }
        var slices = top.map {
            Slice(category: $0.key, label: $0.key.label, amount: $0.value, percent: percent($0.value))
        }
        if rest > 0 {
            slices.append(Slice(category: nil, label: "Outros", amount: rest, percent: percent(rest)))
        }
        return slices
    }

    private static func monthWindow(purchases: [Purchase], endingAt monthKey: String) -> [MonthSpend] {
        let end = monthIndex(of: monthKey)
        var totals: [String: Double] = [:]
        for purchase in purchases {
            totals[String(purchase.date.prefix(7)), default: 0] += purchase.totals.totalPaid
        }
        return ((end - windowMonthCount + 1)...end).map { index in
            let key = Self.monthKey(at: index)
            return MonthSpend(
                key: key,
                label: Format.monthShort(fromISO: "\(key)-01"),
                total: totals[key] ?? 0,
                isReference: index == end
            )
        }
    }

    /// The category whose spend moved the most against the previous month — rises
    /// take priority over falls, since "what got more expensive" is the alert worth reading.
    private static func highlight(
        current: [Purchase],
        previous: [Purchase],
        previousKey: String
    ) -> Highlight? {
        var currentTotals: [Category: Double] = [:]
        var previousTotals: [Category: Double] = [:]
        for item in current.flatMap(\.items) {
            currentTotals[item.category, default: 0] += item.total
        }
        for item in previous.flatMap(\.items) {
            previousTotals[item.category, default: 0] += item.total
        }

        let shifts = previousTotals.compactMap { category, before -> Highlight? in
            guard before > 0 else { return nil }
            let delta = (currentTotals[category] ?? 0) - before
            guard abs(delta) >= 1 else { return nil }
            return Highlight(
                category: category,
                percent: Int((delta / before * 100).rounded()),
                delta: delta,
                previousMonthName: Format.monthName(fromISO: "\(previousKey)-01")
            )
        }
        let rises = shifts.filter(\.rose)
        return (rises.isEmpty ? shifts : rises).max { abs($0.delta) < abs($1.delta) }
    }

    /// The repeatedly-bought product with the longest price history in the window;
    /// Pix rows are skipped — a transfer amount is not a shelf price.
    private static func priceRadar(purchases: [Purchase]) -> PriceRadar? {
        struct Track {
            var name = ""
            var unit = ""
            var latest = ""
            var currentPrice = 0.0
            var pricesByMonth: [String: [Double]] = [:]
        }

        var tracks: [String: Track] = [:]
        for purchase in purchases where purchase.source != .pix {
            let month = String(purchase.date.prefix(7))
            for item in purchase.items {
                let key = item.barcode ?? item.description.lowercased()
                var track = tracks[key] ?? Track()
                track.pricesByMonth[month, default: []].append(item.unitPrice)
                if purchase.date > track.latest {
                    track.latest = purchase.date
                    track.name = item.description
                    track.unit = item.unit
                    track.currentPrice = item.unitPrice
                }
                tracks[key] = track
            }
        }

        let radars = tracks.values
            .filter { $0.pricesByMonth.count >= 3 }
            .compactMap { track -> PriceRadar? in
                let points = track.pricesByMonth
                    .sorted { $0.key < $1.key }
                    .map { month, prices in
                        PriceRadar.Point(
                            monthKey: month,
                            label: Format.monthShort(fromISO: "\(month)-01"),
                            price: prices.reduce(0, +) / Double(prices.count)
                        )
                    }
                guard let first = points.first, let last = points.last, first.price > 0 else { return nil }
                return PriceRadar(
                    productName: track.name,
                    unit: track.unit,
                    currentPrice: track.currentPrice,
                    changePercent: Int(((last.price - first.price) / first.price * 100).rounded()),
                    sinceLabel: first.label,
                    points: points
                )
            }
        return radars.max {
            ($0.points.count, abs($0.changePercent)) < ($1.points.count, abs($1.changePercent))
        }
    }

    private static func topStores(of purchases: [Purchase]) -> [StoreRank] {
        let totals = purchases.reduce(into: [String: Double]()) { totals, purchase in
            totals[purchase.store.name, default: 0] += purchase.totals.totalPaid
        }
        let ranked = totals.sorted { $0.value > $1.value }.prefix(4)
        guard let top = ranked.first, top.value > 0 else { return [] }
        return ranked.enumerated().map { offset, entry in
            StoreRank(rank: offset + 1, name: entry.key, amount: entry.value, fraction: entry.value / top.value)
        }
    }

    private static func weekdays(of purchases: [Purchase]) -> ([WeekdaySpend], String?) {
        var totals = [Double](repeating: 0, count: 7)
        for purchase in purchases {
            guard let date = Format.date(fromISO: purchase.date) else { continue }
            totals[calendar.component(.weekday, from: date) - 1] += purchase.totals.totalPaid
        }
        let order = totals.indices.sorted { totals[$0] > totals[$1] }
        var ranks = [Int](repeating: 0, count: 7)
        for (rank, index) in order.enumerated() {
            ranks[index] = rank
        }
        let spends = totals.indices.map { index in
            WeekdaySpend(index: index, letter: Self.weekdayLetters[index], total: totals[index], rank: ranks[index])
        }
        let topName = order.first.flatMap { totals[$0] > 0 ? Self.weekdayNames[$0] : nil }
        return (spends, topName)
    }
}
