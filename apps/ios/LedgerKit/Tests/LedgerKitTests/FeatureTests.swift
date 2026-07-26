import ComposableArchitecture
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import LedgerKit

private struct TestEnvelope<T: Encodable>: Encodable {
    var ok = true
    var message = ""
    let data: T
}

func envelope(_ value: some Encodable) throws -> Data {
    try JSONEncoder().encode(TestEnvelope(data: value))
}

/// A real (tiny) PNG, so the upload path exercises the same decode/re-encode the app does.
func sampleImageData(width: Int = 8, height: Int = 8) throws -> Data {
    let context = try #require(
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    context.setFillColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let image = try #require(context.makeImage())
    let output = try #require(CFDataCreateMutable(nil, 0))
    let destination = try #require(
        CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
    )
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
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

@MainActor
struct PhotoScanFeatureTests {
    private static func photoStore(
        identify: @escaping @Sendable (Data) async throws -> PhotoScanResult
    ) -> TestStoreOf<ScanFeature> {
        var state = ScanFeature.State()
        state.scanMode = .photo
        return TestStore(initialState: state) {
            ScanFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.photoScanRepository.identify = identify
        }
    }

    private static func drafts(of identified: PhotoScanIdentified) -> IdentifiedArrayOf<ProductDraft> {
        IdentifiedArray(
            uniqueElements: identified.items.enumerated().map { ProductDraft(id: $0.offset, item: $0.element) }
        )
    }

    @Test
    func theShutterCapturesThenIdentifiesTheItems() async {
        let photo = Data("jpeg".utf8)
        let identified = MockData.photoScanIdentified
        let store = Self.photoStore { data in
            #expect(data == photo)
            return .identified(identified)
        }

        await store.send(.shutterTapped) { $0.phase = .capturing }
        await store.send(.photoCaptured(photo)) {
            $0.capturedPhoto = photo
            $0.phase = .processing
        }
        await store.receive(\.photoScanResponse) {
            $0.phase = .product(identified)
            $0.productDrafts = Self.drafts(of: identified)
        }

        await store.send(.scanAgainTapped) {
            $0.phase = .idle
            $0.capturedPhoto = nil
            $0.productDrafts = []
        }
        await store.finish()
    }

    /// A photo can hold several products, and each one becomes its own editable row.
    @Test
    func everyItemInThePhotoBecomesAnEditableRow() async {
        let identified = MockData.photoScanIdentified
        let store = Self.photoStore { _ in .identified(identified) }

        await store.send(.shutterTapped) { $0.phase = .capturing }
        await store.send(.photoCaptured(Data("jpeg".utf8))) {
            $0.capturedPhoto = Data("jpeg".utf8)
            $0.phase = .processing
        }
        await store.receive(\.photoScanResponse) {
            $0.phase = .product(identified)
            $0.productDrafts = [
                ProductDraft(id: 0, item: identified.items[0]),
                ProductDraft(id: 1, item: identified.items[1]),
                ProductDraft(id: 2, item: identified.items[2]),
            ]
        }

        #expect(store.state.productDrafts.count == 3)
        #expect(store.state.selectedDrafts.count == 3)
        #expect(store.state.productTotal == 0)
    }

    @Test
    func aRejectionIsAResultRatherThanAnError() async {
        let rejected = PhotoScanRejected(reason: .noItem, comment: "Não há nenhum produto na foto.")
        let store = Self.photoStore { _ in .rejected(rejected) }

        await store.send(.shutterTapped) { $0.phase = .capturing }
        await store.send(.photoCaptured(Data("jpeg".utf8))) {
            $0.capturedPhoto = Data("jpeg".utf8)
            $0.phase = .processing
        }
        await store.receive(\.photoScanResponse) { $0.phase = .rejected(rejected) }
    }

    @Test
    func anAIFailureShowsThePhotoErrorPhase() async {
        let store = Self.photoStore { _ in throw PhotoScanFailure.aiUnavailable }

        await store.send(.shutterTapped) { $0.phase = .capturing }
        await store.send(.photoCaptured(Data("jpeg".utf8))) {
            $0.capturedPhoto = Data("jpeg".utf8)
            $0.phase = .processing
        }
        await store.receive(\.photoScanResponse) { $0.phase = .photoFailure(.aiUnavailable) }
    }

    @Test
    func aCameraThatReturnsNothingReportsACaptureFailure() async {
        let store = Self.photoStore { _ in .identified(MockData.photoScanIdentified) }

        await store.send(.shutterTapped) { $0.phase = .capturing }
        await store.send(.photoCaptured(nil)) { $0.phase = .photoFailure(.captureFailed) }
    }

    @Test
    func theShutterIsIgnoredInReceiptMode() async {
        let store = TestStore(initialState: ScanFeature.State()) { ScanFeature() }
        await store.send(.shutterTapped)
    }

    @Test
    func aGalleryPickIdentifiesWithoutTheCamera() async {
        let photo = Data("png".utf8)
        let identified = MockData.photoScanIdentified
        let store = Self.photoStore { _ in .identified(identified) }

        await store.send(.choosePhotoTapped) { $0.photoPickerPresented = true }
        // The picker dismisses itself before the image finishes loading.
        await store.send(.photoPickerPresented(false)) { $0.photoPickerPresented = false }
        await store.send(.photoPicked(photo)) {
            $0.capturedPhoto = photo
            $0.phase = .processing
        }
        await store.receive(\.photoScanResponse) {
            $0.phase = .product(identified)
            $0.productDrafts = Self.drafts(of: identified)
        }
    }

    @Test
    func anUnreadableGalleryImageReportsAnInvalidImage() async {
        let store = Self.photoStore { _ in .identified(MockData.photoScanIdentified) }

        await store.send(.choosePhotoTapped) { $0.photoPickerPresented = true }
        await store.send(.photoPickerPresented(false)) { $0.photoPickerPresented = false }
        await store.send(.photoPicked(nil)) { $0.phase = .photoFailure(.invalidImage) }
    }

    private static func draftStore() -> TestStoreOf<ScanFeature> {
        var state = ScanFeature.State()
        state.phase = .product(MockData.photoScanIdentified)
        state.productDrafts = drafts(of: MockData.photoScanIdentified)
        return TestStore(initialState: state) { ScanFeature() }
    }

    @Test
    func theQuantityAndPriceDriveEachItemTotal() async {
        let store = Self.draftStore()

        await store.send(.productPriceChanged(id: 0, price: 8.90)) { $0.productDrafts[id: 0]?.unitPrice = 8.90 }
        await store.send(.productQuantityChanged(id: 0, quantity: 3)) { $0.productDrafts[id: 0]?.quantity = 3 }
        await store.send(.productPriceChanged(id: 1, price: 4.50)) { $0.productDrafts[id: 1]?.unitPrice = 4.50 }

        #expect(abs(store.state.productTotal - 31.20) < 0.001)
        #expect(store.state.productUnitCount == 5)

        await store.send(.productQuantityChanged(id: 0, quantity: 0)) { $0.productDrafts[id: 0]?.quantity = 1 }
        await store.send(.productPriceChanged(id: 1, price: -2)) { $0.productDrafts[id: 1]?.unitPrice = 0 }
    }

    @Test
    func untickedItemsStayOutOfTheTotal() async {
        let store = Self.draftStore()

        await store.send(.productPriceChanged(id: 0, price: 8.90)) { $0.productDrafts[id: 0]?.unitPrice = 8.90 }
        await store.send(.productPriceChanged(id: 1, price: 4.50)) { $0.productDrafts[id: 1]?.unitPrice = 4.50 }
        await store.send(.productSelectionToggled(id: 1)) { $0.productDrafts[id: 1]?.selected = false }

        #expect(store.state.selectedDrafts.map(\.id) == [0, 2])
        #expect(abs(store.state.productTotal - 8.90) < 0.001)
    }

    @Test
    func savingWithEveryItemUntickedDoesNothing() async {
        let store = Self.draftStore()

        for draft in store.state.productDrafts {
            await store.send(.productSelectionToggled(id: draft.id)) {
                $0.productDrafts[id: draft.id]?.selected = false
            }
        }
        await store.send(.addProductTapped)

        #expect(store.state.productSaved == false)
    }

    @Test
    func savingKeepsTheTickedItems() async {
        let store = Self.draftStore()

        await store.send(.productSelectionToggled(id: 2)) { $0.productDrafts[id: 2]?.selected = false }
        await store.send(.addProductTapped) { $0.productSaved = true }

        #expect(store.state.selectedDrafts.count == 2)
    }
}

struct PhotoScanRepositoryTests {
    @Test
    func theImageIsUploadedAsMultipartJPEG() async throws {
        let png = try sampleImageData()
        let result = try await withDependencies {
            $0.apiClient.send = { request in
                #expect(request.method == "POST")
                #expect(request.path == "scan/photo")
                let contentType = try #require(request.contentType)
                #expect(contentType.hasPrefix("multipart/form-data; boundary="))
                #expect((request.timeout ?? 0) > 60)

                let body = try #require(request.body)
                let separator = try #require(body.range(of: Data("\r\n\r\n".utf8)))
                let header = try #require(String(data: body[..<separator.lowerBound], encoding: .utf8))
                #expect(header.contains(#"name="image""#))
                #expect(header.contains("Content-Type: image/jpeg"))
                // The camera hands back HEIC/PNG; the server only takes JPEG, PNG or WebP.
                #expect(body.range(of: Data([0xFF, 0xD8, 0xFF])) != nil)

                return try envelope(PhotoScanResult.identified(MockData.photoScanIdentified))
            }
        } operation: {
            try await PhotoScanRepository.liveValue.identify(imageData: png)
        }

        #expect(result == .identified(MockData.photoScanIdentified))
    }

    @Test
    func aRejectionDecodesFromTheSameEnvelope() async throws {
        let png = try sampleImageData()
        let rejected = PhotoScanRejected(reason: .unclearImage, comment: "A foto está desfocada demais.")
        let result = try await withDependencies {
            $0.apiClient.send = { _ in try envelope(PhotoScanResult.rejected(rejected)) }
        } operation: {
            try await PhotoScanRepository.liveValue.identify(imageData: png)
        }

        #expect(result == .rejected(rejected))
    }

    @Test
    func dataThatIsNotAnImageNeverReachesTheServer() async throws {
        await #expect(throws: PhotoScanFailure.invalidImage) {
            try await withDependencies {
                $0.apiClient.send = { _ in
                    Issue.record("the client should not upload undecodable data")
                    return Data()
                }
            } operation: {
                try await PhotoScanRepository.liveValue.identify(imageData: Data("not an image".utf8))
            }
        }
    }

    @Test
    func serverErrorCodesMapToPhotoScanFailures() async throws {
        let png = try sampleImageData()
        for (errorCode, expected) in [
            ("invalid_image", PhotoScanFailure.invalidImage),
            ("ai_invalid_output", .aiInvalidOutput),
            ("ai_unavailable", .aiUnavailable),
        ] {
            await #expect(throws: expected) {
                try await withDependencies {
                    $0.apiClient.send = { _ in
                        throw APIError.server(status: 502, errorCode: errorCode, message: nil)
                    }
                } operation: {
                    try await PhotoScanRepository.liveValue.identify(imageData: png)
                }
            }
        }
    }

    @Test
    func transportFailuresReadAsAIUnavailable() async throws {
        let png = try sampleImageData()
        await #expect(throws: PhotoScanFailure.aiUnavailable) {
            try await withDependencies {
                $0.apiClient.send = { _ in throw URLError(.timedOut) }
            } operation: {
                try await PhotoScanRepository.liveValue.identify(imageData: png)
            }
        }
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
