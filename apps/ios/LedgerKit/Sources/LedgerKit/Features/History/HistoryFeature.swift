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
        var sections: [MonthSection] = []
        var hero: HeroStats?
        @Presents var detail: PurchaseDetailFeature.State?

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

    static func makeSections(_ summaries: [PurchaseSummary]) -> [MonthSection] {
        let groups = Dictionary(grouping: summaries) { String($0.date.prefix(7)) }
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

    static func makeHero(summaries: [PurchaseSummary], categorySpending: [Category: Double]) -> HeroStats? {
        guard !summaries.isEmpty else { return nil }
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

        let topCategories = categorySpending
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

    /// Derivation runs once per state change here, not on every render.
    private static func rebuildDerived(_ state: inout State) {
        let visible: [PurchaseSummary]
        if state.searchText.isEmpty {
            visible = state.summaries
        } else if let results = state.searchResults {
            visible = results
        } else {
            let query = state.searchText.lowercased()
            visible = state.summaries.filter { $0.store.lowercased().contains(query) }
        }
        state.sections = makeSections(visible)
        state.hero = state.searchText.isEmpty
            ? makeHero(summaries: state.summaries, categorySpending: state.monthCategorySpending)
            : nil
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
                state.isSyncing = true
                return sync()

            case let .localLoaded(summaries):
                state.summaries = summaries
                state.didLoad = true
                Self.rebuildDerived(&state)
                return loadCategorySpending(summaries)

            case let .categorySpendingLoaded(spending):
                state.monthCategorySpending = spending
                Self.rebuildDerived(&state)
                return .none

            case .syncFinished:
                state.isSyncing = false
                return .none

            case let .searchChanged(text):
                state.searchText = text
                guard !text.isEmpty else {
                    state.searchResults = nil
                    Self.rebuildDerived(&state)
                    return .cancel(id: CancelID.search)
                }
                Self.rebuildDerived(&state)
                return .run { send in
                    await send(.searchResults(try await purchasesRepository.search(query: text)))
                } catch: { _, _ in
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case let .searchResults(results):
                state.searchResults = results
                Self.rebuildDerived(&state)
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
        guard !summaries.isEmpty else { return .none }
        return .run { send in
            let purchases = try await purchasesRepository.recentPurchases(monthCount: 1)
            let totals = purchases.reduce(into: [Category: Double]()) { totals, purchase in
                for item in purchase.items {
                    totals[item.category, default: 0] += item.total
                }
            }
            await send(.categorySpendingLoaded(totals))
        } catch: { _, _ in
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
