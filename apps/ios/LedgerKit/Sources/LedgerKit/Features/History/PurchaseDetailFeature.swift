import ComposableArchitecture

/// A single purchase, pushed from History. The summary renders the header
/// immediately; the full purchase comes from the local mirror (so details open
/// offline), falling back to the API — and back-filling the mirror — only when
/// the mirror doesn't have it yet.
@Reducer
struct PurchaseDetailFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        var summary: PurchaseSummary
        var purchase: Purchase?
        var isLoading = false
        var loadFailed = false

        var id: String { summary.id }
    }

    enum Action: Equatable {
        case onAppear
        case purchaseLoaded(Purchase)
        case loadFailed
    }

    @Dependency(\.apiClient) var apiClient
    @Dependency(\.databaseClient) var databaseClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.purchase == nil else { return .none }
                state.isLoading = true
                state.loadFailed = false
                return .run { [id = state.summary.id] send in
                    if let local = try await databaseClient.purchase(id) {
                        await send(.purchaseLoaded(local))
                        return
                    }
                    let fetched = try await apiClient.loadPurchase(id)
                    try await databaseClient.save([fetched])
                    await send(.purchaseLoaded(fetched))
                } catch: { _, send in
                    await send(.loadFailed)
                }

            case let .purchaseLoaded(purchase):
                state.purchase = purchase
                state.isLoading = false
                return .none

            case .loadFailed:
                state.isLoading = false
                state.loadFailed = true
                return .none
            }
        }
    }
}
