import ComposableArchitecture
import Foundation

@Reducer
struct HistoryFeature {
    @ObservableState
    struct State: Equatable {
        var summaries: [PurchaseSummary] = []
        var searchResults: [PurchaseSummary]?
        var monthCategorySpending: [Category: Double] = [:]
        var isSyncing = false
        var didLoad = false
        var didStartInitialSync = false
        var searchText = ""
        @Presents var detail: PurchaseDetailFeature.State?

        var filtered: [PurchaseSummary] {
            guard !searchText.isEmpty else { return summaries }
            if let searchResults { return searchResults }
            let query = searchText.lowercased()
            return summaries.filter { $0.store.lowercased().contains(query) }
        }

        var sections: [MonthSection] {
            let groups = Dictionary(grouping: filtered) { String($0.date.prefix(7)) }
            return groups
                .map { key, value in
                    let sorted = value.sorted { $0.date > $1.date }
                    return MonthSection(
                        id: key,
                        title: Format.monthYear(fromISO: sorted[0].date),
                        total: value.reduce(0) { $0 + $1.totalPaid },
                        purchases: sorted
                    )
                }
                .sorted { $0.id > $1.id }
        }

        var hero: HeroStats? {
            guard searchText.isEmpty, !summaries.isEmpty else { return nil }
            let byMonth = Dictionary(grouping: summaries) { String($0.date.prefix(7)) }
            let months = byMonth.keys.sorted(by: >)
            guard let currentKey = months.first, let current = byMonth[currentKey] else { return nil }

            let total = current.reduce(0) { $0 + $1.totalPaid }
            var trendPercent: Int?
            if let previousKey = months.dropFirst().first, let previous = byMonth[previousKey] {
                let previousTotal = previous.reduce(0) { $0 + $1.totalPaid }
                if previousTotal > 0 {
                    trendPercent = Int(((total - previousTotal) / previousTotal * 100).rounded())
                }
            }

            let byDay = Dictionary(grouping: current, by: \.date)
                .map { (date: $0.key, total: $0.value.reduce(0) { $0 + $1.totalPaid }) }
                .sorted { $0.date < $1.date }
            var running = 0.0
            let points = byDay.map { day in
                running += day.total
                return HeroStats.Point(date: day.date, cumulative: running)
            }

            let topCategories = monthCategorySpending
                .map { (category: $0.key, amount: $0.value) }
                .sorted { $0.amount > $1.amount }
                .prefix(3)

            return HeroStats(
                monthName: Format.monthName(fromISO: currentKey + "-01"),
                total: total,
                purchaseCount: current.count,
                average: total / Double(current.count),
                trendPercent: trendPercent,
                points: points,
                topCategories: Array(topCategories)
            )
        }

        var isEmpty: Bool { didLoad && !isSyncing && summaries.isEmpty }

        var isInitialLoading: Bool { !didLoad || (summaries.isEmpty && isSyncing) }
    }

    struct MonthSection: Identifiable, Equatable {
        var id: String
        var title: String
        var total: Double
        var purchases: [PurchaseSummary]
    }

    struct HeroStats: Equatable {
        struct Point: Identifiable, Equatable {
            var date: String
            var cumulative: Double

            var id: String { date }
        }

        var monthName: String
        var total: Double
        var purchaseCount: Int
        var average: Double
        var trendPercent: Int?
        var points: [Point]
        var topCategories: [(category: Category, amount: Double)]

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.monthName == rhs.monthName
                && lhs.total == rhs.total
                && lhs.purchaseCount == rhs.purchaseCount
                && lhs.trendPercent == rhs.trendPercent
                && lhs.points == rhs.points
                && lhs.topCategories.elementsEqual(rhs.topCategories, by: { $0 == $1 })
        }
    }

    enum Action: Equatable {
        case onAppear
        case refresh
        case localLoaded([PurchaseSummary])
        case categorySpendingLoaded([Category: Double])
        case syncFinished
        case searchChanged(String)
        case searchResults([PurchaseSummary])
        case purchaseTapped(PurchaseSummary)
        case scanFirstTapped
        case detail(PresentationAction<PurchaseDetailFeature.Action>)
        case delegate(Delegate)

        enum Delegate: Equatable {
            case switchToScan
        }
    }

    @Dependency(\.purchasesRepository) var purchasesRepository

    private enum CancelID { case sync, search, categorySpending }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard !state.didStartInitialSync else { return loadLocal() }
                state.didStartInitialSync = true
                state.isSyncing = true
                return .concatenate(loadLocal(), sync())

            case .refresh:
                guard !state.isSyncing else { return .none }
                state.isSyncing = true
                return sync()

            case let .localLoaded(summaries):
                state.summaries = summaries
                state.didLoad = true
                return loadCategorySpending(summaries)

            case let .categorySpendingLoaded(spending):
                state.monthCategorySpending = spending
                return .none

            case .syncFinished:
                state.isSyncing = false
                return .none

            case let .searchChanged(text):
                state.searchText = text
                guard !text.isEmpty else {
                    state.searchResults = nil
                    return .cancel(id: CancelID.search)
                }
                return .run { send in
                    await send(.searchResults(try await purchasesRepository.search(query: text)))
                } catch: { _, _ in
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case let .searchResults(results):
                state.searchResults = results
                return .none

            case let .purchaseTapped(summary):
                state.detail = PurchaseDetailFeature.State(summary: summary)
                return .none

            case .scanFirstTapped:
                return .send(.delegate(.switchToScan))

            case .detail, .delegate:
                return .none
            }
        }
        .ifLet(\.$detail, action: \.detail) { PurchaseDetailFeature() }
    }

    private func loadLocal() -> Effect<Action> {
        .run { send in
            await send(.localLoaded(try await purchasesRepository.summaries()))
        } catch: { _, send in
            await send(.localLoaded([]))
        }
    }

    private func loadCategorySpending(_ summaries: [PurchaseSummary]) -> Effect<Action> {
        guard let latestMonth = summaries.map({ String($0.date.prefix(7)) }).max() else { return .none }
        let ids = summaries.filter { $0.date.hasPrefix(latestMonth) }.map(\.id)
        return .run { send in
            var totals: [Category: Double] = [:]
            for id in ids {
                guard let purchase = try? await purchasesRepository.purchase(id: id) else { continue }
                for item in purchase.items {
                    totals[item.category, default: 0] += item.total
                }
            }
            await send(.categorySpendingLoaded(totals))
        }
        .cancellable(id: CancelID.categorySpending, cancelInFlight: true)
    }

    private func sync() -> Effect<Action> {
        .run { send in
            try await purchasesRepository.refresh()
            await send(.localLoaded(try await purchasesRepository.summaries()))
            await send(.syncFinished)
        } catch: { _, send in
            await send(.syncFinished)
        }
        .cancellable(id: CancelID.sync, cancelInFlight: true)
    }
}
