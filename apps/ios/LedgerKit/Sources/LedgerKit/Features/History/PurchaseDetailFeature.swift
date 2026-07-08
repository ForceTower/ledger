import ComposableArchitecture

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

    @Dependency(\.purchasesRepository) var purchasesRepository

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.purchase == nil else { return .none }
                state.isLoading = true
                state.loadFailed = false
                return .run { [id = state.summary.id] send in
                    if let purchase = try await purchasesRepository.purchase(id: id) {
                        await send(.purchaseLoaded(purchase))
                    } else {
                        await send(.loadFailed)
                    }
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
