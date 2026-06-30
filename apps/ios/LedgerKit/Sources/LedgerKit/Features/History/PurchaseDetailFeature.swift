import ComposableArchitecture

/// A single purchase, pushed from History. The summary renders the header
/// immediately while the full purchase (items, totals, store) loads.
@Reducer
struct PurchaseDetailFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        var summary: PurchaseSummary
        var purchase: Purchase?
        var isLoading = false

        var id: String { summary.id }
    }

    enum Action: Equatable {
        case onAppear
        case purchaseLoaded(Purchase)
    }

    @Dependency(\.apiClient) var apiClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.purchase == nil else { return .none }
                state.isLoading = true
                return .run { [id = state.summary.id] send in
                    let purchase = try await apiClient.loadPurchase(id)
                    await send(.purchaseLoaded(purchase))
                }

            case let .purchaseLoaded(purchase):
                state.purchase = purchase
                state.isLoading = false
                return .none
            }
        }
    }
}
