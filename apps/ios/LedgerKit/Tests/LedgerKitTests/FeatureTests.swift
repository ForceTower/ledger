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
        await store.finish()
    }

    @Test
    func aSavedScanLandsInTheLocalMirror() async throws {
        let db = DatabaseClient.inMemory()
        let response = ScanResponse(status: .saved, purchase: MockData.atacadao, warnings: [])
        let store = TestStore(initialState: ScanFeature.State()) {
            ScanFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.databaseClient = db
            $0.apiClient.scan = { _ in response }
        }

        await store.send(.codeScanned(Self.validURL)) { $0.phase = .detecting }
        await store.receive(\.detected) { $0.phase = .processing }
        await store.receive(\.scanResponse) { $0.phase = .result(response) }
        await store.finish()

        let mirrored = try await db.purchase(MockData.atacadao.id)
        #expect(mirrored == MockData.atacadao)
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
    func firstAppearanceServesTheMirrorThenSyncsTheFeed() async {
        let store = TestStore(initialState: HistoryFeature.State()) {
            HistoryFeature()
        } withDependencies: {
            $0.databaseClient = .inMemory()
            $0.apiClient.loadPurchases = { page in
                PurchasePage(
                    items: MockData.purchases,
                    page: page,
                    pageSize: 5,
                    total: MockData.purchases.count,
                    hasMore: false
                )
            }
        }

        await store.send(.onAppear) {
            $0.didStartInitialSync = true
            $0.isSyncing = true
        }
        // The (still empty) mirror answers first; sync then fills it and re-reads.
        await store.receive(\.localLoaded) { $0.didLoad = true }
        await store.receive(\.localLoaded) { $0.summaries = MockData.summaries }
        await store.receive(\.syncFinished) { $0.isSyncing = false }
    }

    @Test
    func syncPagesThroughTheWholeFeed() async {
        var state = HistoryFeature.State()
        state.didStartInitialSync = true
        state.didLoad = true
        let store = TestStore(initialState: state) {
            HistoryFeature()
        } withDependencies: {
            $0.databaseClient = .inMemory()
            $0.apiClient.loadPurchases = { page in
                switch page {
                case 1: PurchasePage(items: [MockData.atacadao], page: 1, pageSize: 1, total: 2, hasMore: true)
                default: PurchasePage(items: [MockData.carrefour], page: 2, pageSize: 1, total: 2, hasMore: false)
                }
            }
        }

        await store.send(.refresh) { $0.isSyncing = true }
        await store.receive(\.localLoaded) {
            $0.summaries = [MockData.atacadao.summary, MockData.carrefour.summary]
        }
        await store.receive(\.syncFinished) { $0.isSyncing = false }
    }

    @Test
    func aFailedSyncKeepsWhatTheMirrorHolds() async throws {
        struct Offline: Error {}
        let db = DatabaseClient.inMemory()
        try await db.save(MockData.purchases)
        let store = TestStore(initialState: HistoryFeature.State()) {
            HistoryFeature()
        } withDependencies: {
            $0.databaseClient = db
            $0.apiClient.loadPurchases = { _ in throw Offline() }
        }

        await store.send(.onAppear) {
            $0.didStartInitialSync = true
            $0.isSyncing = true
        }
        await store.receive(\.localLoaded) {
            $0.summaries = MockData.summaries
            $0.didLoad = true
        }
        await store.receive(\.syncFinished) { $0.isSyncing = false }
    }

    @Test
    func searchMatchesItemDescriptionsFromTheMirror() async throws {
        let db = DatabaseClient.inMemory()
        try await db.save(MockData.purchases)
        let store = TestStore(initialState: HistoryFeature.State()) {
            HistoryFeature()
        } withDependencies: {
            $0.databaseClient = db
        }

        // "bacon" appears only in an Atacadão item, never in a store name.
        await store.send(.searchChanged("bacon")) { $0.searchText = "bacon" }
        await store.receive(\.searchResults) { $0.searchResults = [MockData.atacadao.summary] }

        await store.send(.searchChanged("")) {
            $0.searchText = ""
            $0.searchResults = nil
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

@MainActor
struct PurchaseDetailFeatureTests {
    @Test
    func detailComesFromTheMirrorWithoutTouchingTheAPI() async throws {
        struct Offline: Error {}
        let db = DatabaseClient.inMemory()
        try await db.save([MockData.atacadao])
        let store = TestStore(initialState: PurchaseDetailFeature.State(summary: MockData.atacadao.summary)) {
            PurchaseDetailFeature()
        } withDependencies: {
            $0.databaseClient = db
            $0.apiClient.loadPurchase = { _ in throw Offline() }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        // Equality against the original proves the record graph round-trips
        // losslessly through the mirror.
        await store.receive(\.purchaseLoaded) {
            $0.purchase = MockData.atacadao
            $0.isLoading = false
        }
    }

    @Test
    func aMirrorMissFallsBackToTheAPIAndBackfills() async throws {
        let db = DatabaseClient.inMemory()
        let store = TestStore(initialState: PurchaseDetailFeature.State(summary: MockData.assai.summary)) {
            PurchaseDetailFeature()
        } withDependencies: {
            $0.databaseClient = db
            $0.apiClient.loadPurchase = { MockData.purchase(id: $0) }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.purchaseLoaded) {
            $0.purchase = MockData.assai
            $0.isLoading = false
        }

        let backfilled = try await db.purchase(MockData.assai.id)
        #expect(backfilled == MockData.assai)
    }

    @Test
    func offlineWithoutAMirrorHitShowsTheFailureState() async {
        struct Offline: Error {}
        let store = TestStore(initialState: PurchaseDetailFeature.State(summary: MockData.assai.summary)) {
            PurchaseDetailFeature()
        } withDependencies: {
            $0.databaseClient = .inMemory()
            $0.apiClient.loadPurchase = { _ in throw Offline() }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.loadFailed) {
            $0.isLoading = false
            $0.loadFailed = true
        }
    }
}
