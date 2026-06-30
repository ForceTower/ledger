import ComposableArchitecture
import Testing

@testable import LedgerKit

/// `TestStore` drives each reducer and asserts on every state change — the
/// exhaustiveness that is TCA's headline feature. The clock and API client are
/// overridden so the flows resolve instantly and deterministically.

@MainActor
struct ScanFeatureTests {
    /// A SEFAZ NFC-e QR payload: `?p=` + a 44-digit access key + the `|2|1|1|hash` tail.
    nonisolated private static let validURL =
        "http://nfe.sefaz.ba.gov.br/.../NFCEC_consulta_chave_acesso.aspx?p=12345678901234567890123456789012345678901234|2|1|1|A1B2C3"

    @Test
    func scanningAValidCodeDetectsThenSavesAResult() async {
        let response = ScanResponse(status: .saved, purchase: MockData.atacadao, warnings: [])
        let store = TestStore(initialState: ScanFeature.State()) {
            ScanFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.apiClient.scan = { url in
                #expect(url == Self.validURL) // the decoded URL flows through unchanged
                return response
            }
        }

        await store.send(.codeScanned(Self.validURL)) { $0.phase = .detecting }
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

        await store.send(.codeScanned(Self.validURL)) { $0.phase = .detecting }
        await store.receive(\.detected) { $0.phase = .processing }
        await store.receive(\.scanResponse) { $0.phase = .failure(.expired) }
    }

    @Test
    func aNonNFCeCodeShowsInvalidQR() async {
        let store = TestStore(initialState: ScanFeature.State()) { ScanFeature() }
        await store.send(.codeScanned("https://example.com")) { $0.phase = .failure(.invalidQR) }
    }

    @Test
    func aCodeScannedWhileBusyIsIgnored() async {
        var state = ScanFeature.State()
        state.phase = .processing
        let store = TestStore(initialState: state) { ScanFeature() }
        await store.send(.codeScanned(Self.validURL)) // guarded: no state change, no effect
    }

    @Test
    func onAppearMarksCameraUnavailable() async {
        let store = TestStore(initialState: ScanFeature.State()) {
            ScanFeature()
        } withDependencies: {
            $0.cameraClient.isAvailable = { false }
        }
        await store.send(.onAppear) { $0.cameraAvailable = false }
    }

    @Test
    func onAppearRequestsAccessWhenUndetermined() async {
        let store = TestStore(initialState: ScanFeature.State()) {
            ScanFeature()
        } withDependencies: {
            $0.cameraClient.authorizationStatus = { .notDetermined }
            $0.cameraClient.requestAccess = { false }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.onAppear)
        await store.receive(\.cameraAuthorizationResponse)
        #expect(store.state.cameraAuthorized == false)
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
