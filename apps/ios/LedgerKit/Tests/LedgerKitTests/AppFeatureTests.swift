import ComposableArchitecture
import Testing

@testable import LedgerKit

/// `TestStore` drives the reducer and *asserts on every state change*. If a
/// mutation happens that isn't described, or an effect emits an action that
/// isn't `receive`d, the test fails. That exhaustiveness is TCA's headline feature.
@MainActor
struct AppFeatureTests {
    @Test
    func incrementAndDecrement() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        await store.send(.incrementButtonTapped) {
            $0.count = 1
        }
        await store.send(.incrementButtonTapped) {
            $0.count = 2
        }
        await store.send(.decrementButtonTapped) {
            $0.count = 1
        }
    }
}
