import ComposableArchitecture
import Foundation

/// The purchases list — grouped by month, searchable, pull-to-refresh — with a
/// native push to a purchase detail.
@Reducer
struct HistoryFeature {
    @ObservableState
    struct State: Equatable {
        var summaries: [PurchaseSummary] = []
        var isLoading = false
        var didLoad = false
        var searchText = ""
        @Presents var detail: PurchaseDetailFeature.State?

        var filtered: [PurchaseSummary] {
            guard !searchText.isEmpty else { return summaries }
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

        /// "R$ 457,30 em março · 3 notas" — the latest month's spend and total count.
        var summaryLine: String? {
            guard let latest = sections.first else { return nil }
            let month = Format.monthName(fromISO: latest.purchases[0].date)
            return "\(Format.brl(latest.total)) em \(month) · \(summaries.count) notas"
        }

        var isEmpty: Bool { didLoad && !isLoading && summaries.isEmpty }
    }

    struct MonthSection: Identifiable, Equatable {
        var id: String
        var title: String
        var total: Double
        var purchases: [PurchaseSummary]
    }

    enum Action: Equatable {
        case onAppear
        case refresh
        case purchasesLoaded([PurchaseSummary])
        case searchChanged(String)
        case purchaseTapped(PurchaseSummary)
        case scanFirstTapped
        case detail(PresentationAction<PurchaseDetailFeature.Action>)
        case delegate(Delegate)

        enum Delegate: Equatable {
            case switchToScan
        }
    }

    @Dependency(\.apiClient) var apiClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard !state.didLoad else { return .none }
                state.isLoading = true
                return load()

            case .refresh:
                return load()

            case let .purchasesLoaded(summaries):
                state.summaries = summaries
                state.isLoading = false
                state.didLoad = true
                return .none

            case let .searchChanged(text):
                state.searchText = text
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

    private func load() -> Effect<Action> {
        .run { send in
            let summaries = try await apiClient.loadPurchases()
            await send(.purchasesLoaded(summaries))
        }
    }
}
