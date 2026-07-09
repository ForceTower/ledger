import ComposableArchitecture
import Foundation
import Testing

@testable import LedgerKit

private struct TestEnvelope<T: Encodable>: Encodable {
    var ok = true
    var message = ""
    let data: T
}

func envelope(_ value: some Encodable) throws -> Data {
    try JSONEncoder().encode(TestEnvelope(data: value))
}

func categorySpending(of purchases: [Purchase]) -> [LedgerKit.Category: Double] {
    purchases.reduce(into: [:]) { totals, purchase in
        for item in purchase.items {
            totals[item.category, default: 0] += item.total
        }
    }
}

@MainActor
struct ScanFeatureTests {
    nonisolated static let validURL =
        "http://nfe.sefaz.ba.gov.br/.../NFCEC_consulta_chave_acesso.aspx?p=12345678901234567890123456789012345678901234|2|1|1|A1B2C3"

    @Test
    func scanningAValidCodeDetectsThenSavesAResult() async {
        let response = ScanResponse(status: .saved, purchase: MockData.atacadao, warnings: [])
        let store = TestStore(initialState: ScanFeature.State()) {
            ScanFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.scanRepository.scan = { url in
                #expect(url == Self.validURL)
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
    func aFailedScanShowsTheErrorPhase() async {
        let store = TestStore(initialState: ScanFeature.State()) {
            ScanFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.scanRepository.scan = { _ in throw ScanFailure.expired }
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
        await store.send(.codeScanned(Self.validURL))
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

struct ScanRepositoryTests {
    @Test
    func aSavedScanLandsInTheLocalMirror() async throws {
        let database = try inMemoryDatabase()
        let response = try await withDependencies {
            $0.database = database
            $0.apiClient.send = { request in
                #expect(request.method == "POST")
                #expect(request.path == "scan")
                return try envelope(ScanResponse(status: .saved, purchase: MockData.atacadao, warnings: []))
            }
        } operation: {
            try await ScanRepository.liveValue.scan(url: ScanFeatureTests.validURL)
        }

        #expect(response.status == .saved)
        let mirrored = try await MirrorStore(writer: database).purchase(id: MockData.atacadao.id)
        #expect(mirrored == MockData.atacadao)
    }

    @Test
    func serverErrorCodesMapToScanFailures() async throws {
        let database = try inMemoryDatabase()
        await #expect(throws: ScanFailure.expired) {
            try await withDependencies {
                $0.database = database
                $0.apiClient.send = { _ in
                    throw APIError.server(status: 502, errorCode: "expired", message: "not found")
                }
            } operation: {
                try await ScanRepository.liveValue.scan(url: ScanFeatureTests.validURL)
            }
        }
    }

    @Test
    func transportFailuresReadAsUnavailable() async throws {
        let database = try inMemoryDatabase()
        await #expect(throws: ScanFailure.unavailable) {
            try await withDependencies {
                $0.database = database
                $0.apiClient.send = { _ in throw URLError(.notConnectedToInternet) }
            } operation: {
                try await ScanRepository.liveValue.scan(url: ScanFeatureTests.validURL)
            }
        }
    }
}

@MainActor
struct HistoryFeatureTests {
    @Test
    func firstAppearanceServesTheMirrorThenSyncsTheFeed() async throws {
        let database = try inMemoryDatabase()
        let store = TestStore(initialState: HistoryFeature.State()) {
            HistoryFeature()
        } withDependencies: {
            $0.purchasesRepository = .liveValue
            $0.database = database
            $0.apiClient.send = { _ in
                try envelope(
                    PurchasePage(
                        items: MockData.purchases,
                        page: 1,
                        pageSize: 5,
                        total: MockData.purchases.count,
                        hasMore: false
                    )
                )
            }
        }

        await store.send(.onAppear) {
            $0.didStartInitialSync = true
            $0.isSyncing = true
        }
        await store.receive(\.localLoaded) { $0.didLoad = true }
        await store.receive(\.localLoaded) { $0.summaries = MockData.summaries }
        await store.receive(\.syncFinished) { $0.isSyncing = false }
        await store.receive(\.categorySpendingLoaded) {
            $0.monthCategorySpending = categorySpending(of: [MockData.atacadao, MockData.assai, MockData.paoDeAcucar])
        }
    }

    @Test
    func syncPagesThroughTheWholeFeed() async throws {
        let database = try inMemoryDatabase()
        var state = HistoryFeature.State()
        state.didStartInitialSync = true
        state.didLoad = true
        let store = TestStore(initialState: state) {
            HistoryFeature()
        } withDependencies: {
            $0.purchasesRepository = .liveValue
            $0.database = database
            $0.apiClient.send = { request in
                switch request.query.first?.value {
                case "1":
                    try envelope(PurchasePage(items: [MockData.atacadao], page: 1, pageSize: 1, total: 2, hasMore: true))
                default:
                    try envelope(PurchasePage(items: [MockData.carrefour], page: 2, pageSize: 1, total: 2, hasMore: false))
                }
            }
        }

        await store.send(.refresh) { $0.isSyncing = true }
        await store.receive(\.localLoaded) {
            $0.summaries = [MockData.atacadao.summary, MockData.carrefour.summary]
        }
        await store.receive(\.syncFinished) { $0.isSyncing = false }
        await store.receive(\.categorySpendingLoaded) {
            $0.monthCategorySpending = categorySpending(of: [MockData.atacadao])
        }
    }

    @Test
    func aFailedSyncKeepsWhatTheMirrorHolds() async throws {
        let database = try inMemoryDatabase()
        try await MirrorStore(writer: database).save(MockData.purchases)
        let store = TestStore(initialState: HistoryFeature.State()) {
            HistoryFeature()
        } withDependencies: {
            $0.purchasesRepository = .liveValue
            $0.database = database
            $0.apiClient.send = { _ in throw URLError(.notConnectedToInternet) }
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
        await store.receive(\.categorySpendingLoaded) {
            $0.monthCategorySpending = categorySpending(of: [MockData.atacadao, MockData.assai, MockData.paoDeAcucar])
        }
    }

    @Test
    func searchMatchesItemDescriptionsFromTheMirror() async throws {
        let database = try inMemoryDatabase()
        try await MirrorStore(writer: database).save(MockData.purchases)
        let store = TestStore(initialState: HistoryFeature.State()) {
            HistoryFeature()
        } withDependencies: {
            $0.purchasesRepository = .liveValue
            $0.database = database
        }

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

struct PurchaseMirrorTests {
    @Test
    func monthlySpendingAggregatesTheMirrorsMonth() async throws {
        let database = try inMemoryDatabase()
        try await MirrorStore(writer: database).save(MockData.purchases)

        let march = try await withDependencies {
            $0.purchasesRepository = .liveValue
            $0.database = database
        } operation: {
            try await PurchaseMirror.monthlySpending(containing: Format.date(fromISO: "2026-03-15")!)
        }

        #expect(march.total == 208.75 + 156.40 + 92.15)
        #expect(march.purchaseCount == 3)
        #expect(march.monthName == "março")
        #expect(march.monthLabel == "Março 2026")
    }

    @Test
    func monthlySpendingIsZeroForAMonthWithoutPurchases() async throws {
        let database = try inMemoryDatabase()
        let empty = try await withDependencies {
            $0.purchasesRepository = .liveValue
            $0.database = database
        } operation: {
            try await PurchaseMirror.monthlySpending(containing: Format.date(fromISO: "2026-07-02")!)
        }

        #expect(empty.total == 0)
        #expect(empty.purchaseCount == 0)
    }
}

@MainActor
struct PurchaseDetailFeatureTests {
    @Test
    func detailComesFromTheMirrorWithoutTouchingTheAPI() async throws {
        let database = try inMemoryDatabase()
        try await MirrorStore(writer: database).save([MockData.atacadao])
        let store = TestStore(initialState: PurchaseDetailFeature.State(summary: MockData.atacadao.summary)) {
            PurchaseDetailFeature()
        } withDependencies: {
            $0.purchasesRepository = .liveValue
            $0.database = database
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.purchaseLoaded) {
            $0.purchase = MockData.atacadao
            $0.isLoading = false
        }
    }

    @Test
    func aMirrorMissFallsBackToTheAPIAndBackfills() async throws {
        let database = try inMemoryDatabase()
        let store = TestStore(initialState: PurchaseDetailFeature.State(summary: MockData.assai.summary)) {
            PurchaseDetailFeature()
        } withDependencies: {
            $0.purchasesRepository = .liveValue
            $0.database = database
            $0.apiClient.send = { request in
                #expect(request.path == "purchases/\(MockData.assai.id)")
                return try envelope(MockData.assai)
            }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.purchaseLoaded) {
            $0.purchase = MockData.assai
            $0.isLoading = false
        }

        let backfilled = try await MirrorStore(writer: database).purchase(id: MockData.assai.id)
        #expect(backfilled == MockData.assai)
    }

    @Test
    func offlineWithoutAMirrorHitShowsTheFailureState() async throws {
        let database = try inMemoryDatabase()
        let store = TestStore(initialState: PurchaseDetailFeature.State(summary: MockData.assai.summary)) {
            PurchaseDetailFeature()
        } withDependencies: {
            $0.purchasesRepository = .liveValue
            $0.database = database
            $0.apiClient.send = { _ in throw URLError(.notConnectedToInternet) }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.loadFailed) {
            $0.isLoading = false
            $0.loadFailed = true
        }
    }
}
