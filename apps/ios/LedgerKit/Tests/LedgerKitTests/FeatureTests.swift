import ComposableArchitecture
import Testing

@testable import LedgerKit

/// `TestStore` drives each reducer and asserts on every state change — the
/// exhaustiveness that is TCA's headline feature. The clock and API client are
/// overridden so the flows resolve instantly and deterministically.

@MainActor
struct ScanFeatureTests {
    @Test
    func tappingTheViewfinderDetectsThenSavesAResult() async {
        let response = ScanResponse(status: .saved, purchase: MockData.atacadao, warnings: [])
        let store = TestStore(initialState: ScanFeature.State()) {
            ScanFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.apiClient.scan = { _ in response }
        }

        await store.send(.scanTapped) { $0.phase = .detecting }
        await store.receive(\.detected) { $0.phase = .processing }
        await store.receive(\.scanResponse) { $0.phase = .result(response) }

        await store.send(.scanAgainTapped) { $0.phase = .idle }
    }

    @Test
    func aFailedScanShowsTheErrorPhase() async {
        let store = TestStore(initialState: ScanFeature.State()) {
            ScanFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.apiClient.scan = { _ in throw ScanFailure.expired }
        }

        await store.send(.scanTapped) { $0.phase = .detecting }
        await store.receive(\.detected) { $0.phase = .processing }
        await store.receive(\.scanResponse) { $0.phase = .failure(.expired) }
    }

    @Test
    func settingsTapBubblesUpAsADelegate() async {
        let store = TestStore(initialState: ScanFeature.State()) { ScanFeature() }
        await store.send(.settingsTapped)
        await store.receive(\.delegate)
    }
}

@MainActor
struct HistoryFeatureTests {
    @Test
    func loadsPurchasesOnAppear() async {
        let store = TestStore(initialState: HistoryFeature.State()) {
            HistoryFeature()
        } withDependencies: {
            $0.apiClient.loadPurchases = { MockData.summaries }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.purchasesLoaded) {
            $0.summaries = MockData.summaries
            $0.isLoading = false
            $0.didLoad = true
        }
    }

    @Test
    func tappingAPurchasePushesDetail() async {
        let summary = MockData.summaries[0]
        let store = TestStore(initialState: HistoryFeature.State()) { HistoryFeature() }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.purchaseTapped(summary)) {
            $0.detail = PurchaseDetailFeature.State(summary: summary)
        }
    }
}
