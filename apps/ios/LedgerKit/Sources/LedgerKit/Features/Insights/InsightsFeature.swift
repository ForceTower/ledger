import ComposableArchitecture
import Foundation

@Reducer
struct InsightsFeature {
    @ObservableState
    struct State: Equatable {
        var snapshot: InsightsSnapshot?
        var didLoad = false

        var isEmpty: Bool { didLoad && snapshot == nil }
    }

    enum Action: Equatable {
        case onAppear
        case snapshotLoaded(InsightsSnapshot?)
        case scanFirstTapped
        case delegate(Delegate)

        enum Delegate: Equatable {
            case switchToScan
        }
    }

    @Dependency(\.purchasesRepository) var purchasesRepository
    @Dependency(\.date.now) var now

    private enum CancelID { case load }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { [now] send in
                    let purchases = try await purchasesRepository.recentPurchases(
                        monthCount: InsightsSnapshot.windowMonthCount
                    )
                    await send(.snapshotLoaded(InsightsSnapshot(purchases: purchases, now: now)))
                } catch: { _, send in
                    await send(.snapshotLoaded(nil))
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .snapshotLoaded(snapshot):
                state.snapshot = snapshot
                state.didLoad = true
                return .none

            case .scanFirstTapped:
                return .send(.delegate(.switchToScan))

            case .delegate:
                return .none
            }
        }
    }
}
