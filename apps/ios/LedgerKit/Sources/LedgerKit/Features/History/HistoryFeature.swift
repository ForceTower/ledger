import ComposableArchitecture
import Foundation

@Reducer
struct HistoryFeature {
    @ObservableState
    struct State: Equatable {
        var summaries: [PurchaseSummary] = []
        var searchResults: [PurchaseSummary]?
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

        var summaryLine: String? {
            guard let latest = sections.first else { return nil }
            let month = Format.monthName(fromISO: latest.purchases[0].date)
            return "\(Format.brl(latest.total)) em \(month) · \(summaries.count) notas"
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

    enum Action: Equatable {
        case onAppear
        case refresh
        case localLoaded([PurchaseSummary])
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

    private enum CancelID { case sync, search }

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
