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
    nonisolated static let validKey = "12345678901234567890123456789012345678901234"
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
        await store.receive(\.detected) {
            $0.phase = .processing
            $0.scannedAccessKey = Self.validKey
        }
        await store.receive(\.scanResponse) { $0.phase = .result(response) }

        await store.send(.scanAgainTapped) {
            $0.phase = .idle
            $0.scannedAccessKey = nil
        }
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
        await store.receive(\.detected) {
            $0.phase = .processing
            $0.scannedAccessKey = Self.validKey
        }
        await store.receive(\.scanResponse) { $0.phase = .failure(.expired) }
    }

    @Test
    func aRejectedQRFallsBackToTheKeyConsultation() async {
        let imageBytes = Data("jpeg-bytes".utf8)
        let challenge = KeyScanChallenge(
            challengeId: "ch1",
            captchaImage: imageBytes.base64EncodedString(),
            expiresIn: 300
        )
        let response = ScanResponse(status: .saved, purchase: MockData.atacadao, warnings: [])
        let store = TestStore(initialState: ScanFeature.State()) {
            ScanFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.scanRepository.scan = { _ in throw ScanFailure.qrRejected }
            $0.scanRepository.startKeyChallenge = { key in
                #expect(key == Self.validKey)
                return challenge
            }
            $0.scanRepository.completeKeyChallenge = { challengeId, captcha in
                #expect(challengeId == "ch1")
                #expect(captcha == "AB12")
                return response
            }
        }

        await store.send(.codeScanned(Self.validURL)) { $0.phase = .detecting }
        await store.receive(\.detected) {
            $0.phase = .processing
            $0.scannedAccessKey = Self.validKey
        }
        await store.receive(\.scanResponse) { $0.phase = .failure(.qrRejected) }

        await store.send(.consultByKeyTapped) { $0.phase = .processing }
        await store.receive(\.keyChallengeResponse) {
            $0.phase = .captcha(CaptchaChallenge(challengeId: "ch1", image: imageBytes))
        }

        await store.send(.captchaAnswerChanged("AB12")) { $0.captchaAnswer = "AB12" }
        await store.send(.submitCaptchaTapped) { $0.captchaBusy = true }
        await store.receive(\.keyScanResponse) {
            $0.captchaBusy = false
            $0.captchaAnswer = ""
            $0.phase = .result(response)
        }
        await store.finish()
    }

    @Test
    func aWrongCaptchaFetchesAFreshImageAndComplains() async {
        let freshImage = Data("fresh".utf8)
        var state = ScanFeature.State()
        state.phase = .captcha(CaptchaChallenge(challengeId: "spent", image: Data("stale".utf8)))
        state.scannedAccessKey = Self.validKey
        state.captchaAnswer = "WRONG"
        let store = TestStore(initialState: state) {
            ScanFeature()
        } withDependencies: {
            $0.scanRepository.completeKeyChallenge = { _, _ in throw ScanFailure.captchaRejected }
            $0.scanRepository.startKeyChallenge = { _ in
                KeyScanChallenge(
                    challengeId: "ch2",
                    captchaImage: freshImage.base64EncodedString(),
                    expiresIn: 300
                )
            }
        }

        await store.send(.submitCaptchaTapped) { $0.captchaBusy = true }
        await store.receive(\.keyScanResponse) {
            $0.captchaError = "Código incorreto. Tente de novo com a nova imagem."
        }
        await store.receive(\.keyChallengeResponse) {
            $0.captchaBusy = false
            $0.captchaAnswer = ""
            $0.phase = .captcha(CaptchaChallenge(challengeId: "ch2", image: freshImage))
        }
        await store.finish()
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
            uniqueElements: identified.items.enumerated().map { index, item in
                ProductDraft(id: index, item: item, quantity: item.quantity ?? 1, unitPrice: item.unitPrice ?? 0)
            }
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

    /// A photo can hold several products, and each one becomes its own editable row — with the
    /// price and quantity the AI managed to read already filled in.
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
                ProductDraft(id: 1, item: identified.items[1], quantity: 2, unitPrice: 3.50),
                ProductDraft(id: 2, item: identified.items[2], unitPrice: 2.75),
            ]
        }

        #expect(store.state.productDrafts.count == 3)
        #expect(store.state.selectedDrafts.count == 3)
        #expect(store.state.productTotal == 9.75)
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

        // 3 × 8.90, plus the AI-prefilled 2 × 4.50 and 1 × 2.75.
        #expect(abs(store.state.productTotal - 38.45) < 0.001)
        #expect(store.state.productUnitCount == 6)

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
        #expect(abs(store.state.productTotal - 11.65) < 0.001)
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

@MainActor
struct TransferScanFeatureTests {
    private static func transferStore(
        interpret: @escaping @Sendable (Data?, String?) async throws -> TransferScanResult = { _, _ in
            MockData.transferScan
        },
        save: @escaping @Sendable (TransferSaveRequest) async throws -> TransferSaveResult = { request in
            TransferSaveResult(
                transfer: request.transfer,
                purchase: MockData.pixPurchase(request.transfer, category: request.category)
            )
        }
    ) -> TestStoreOf<ScanFeature> {
        var state = ScanFeature.State()
        state.scanMode = .transfer
        return TestStore(initialState: state) {
            ScanFeature()
        } withDependencies: {
            $0.transferScanRepository.interpret = interpret
            $0.transferScanRepository.save = save
        }
    }

    /// Reading is not saving: the owner reviews the AI's guess before anything is written down.
    @Test
    func readingAComprovanteThenSavingItTakesTwoSteps() async {
        let scan = MockData.transferScan
        let requests = LockIsolated<[TransferSaveRequest]>([])
        let store = Self.transferStore(save: { request in
            requests.withValue { $0.append(request) }
            return TransferSaveResult(
                transfer: request.transfer,
                purchase: MockData.pixPurchase(request.transfer, category: request.category)
            )
        })

        await store.send(.transferTextChanged(MockData.transferReceiptText)) {
            $0.transferText = MockData.transferReceiptText
        }
        await store.send(.interpretTransferTapped) { $0.phase = .processing }
        await store.receive(\.transferScanResponse) {
            $0.phase = .transfer(scan)
            $0.transferCategory = scan.category
            $0.transferLinked = true
        }

        await store.send(.saveTransferTapped) { $0.transferSaving = true }
        await store.receive(\.transferSaveResponse) {
            $0.transferSaving = false
            $0.phase = .transferSaved(TransferSaveResult(
                transfer: scan.transfer,
                purchase: MockData.pixPurchase(scan.transfer, category: scan.category)
            ))
        }

        #expect(requests.value.count == 1)
        #expect(requests.value.first?.linkedPurchaseId == scan.match?.purchaseId)
    }

    /// The AI needs a print or some text; with neither, the button does nothing.
    @Test
    func anEmptyComprovanteIsNeverSentToTheAI() async {
        let store = Self.transferStore(interpret: { _, _ in
            Issue.record("nothing should be interpreted without an input")
            return MockData.transferScan
        })

        #expect(store.state.transferReady == false)
        await store.send(.interpretTransferTapped)

        await store.send(.transferTextChanged("   \n  ")) { $0.transferText = "   \n  " }
        #expect(store.state.transferReady == false)
        await store.send(.interpretTransferTapped)
    }

    @Test
    func theOwnersCorrectionsAreWhatGetSaved() async {
        let requests = LockIsolated<[TransferSaveRequest]>([])
        let store = Self.transferStore(save: { request in
            requests.withValue { $0.append(request) }
            return TransferSaveResult(
                transfer: request.transfer,
                purchase: MockData.pixPurchase(request.transfer, category: request.category)
            )
        })

        await store.send(.transferTextChanged("Pix de R$ 128,40")) { $0.transferText = "Pix de R$ 128,40" }
        await store.send(.interpretTransferTapped) { $0.phase = .processing }
        await store.receive(\.transferScanResponse) {
            $0.phase = .transfer(MockData.transferScan)
            $0.transferCategory = MockData.transferScan.category
            $0.transferLinked = true
        }

        await store.send(.transferCategoryChanged(.bakery)) { $0.transferCategory = .bakery }
        await store.send(.transferLinkToggled) { $0.transferLinked = false }
        await store.send(.saveTransferTapped) { $0.transferSaving = true }
        await store.receive(\.transferSaveResponse) {
            $0.transferSaving = false
            $0.phase = .transferSaved(TransferSaveResult(
                transfer: MockData.transferScan.transfer,
                purchase: MockData.pixPurchase(MockData.transferScan.transfer, category: .bakery)
            ))
        }

        #expect(requests.value.first?.category == .bakery)
        #expect(requests.value.first?.linkedPurchaseId == nil)
    }

    /// A note the AI could not read is worth another try — the owner should not have to paste it again.
    @Test
    func aFailedReadingKeepsTheDraft() async {
        let store = Self.transferStore(interpret: { _, _ in throw TransferScanFailure.notATransfer })

        await store.send(.transferTextChanged("nada disso")) { $0.transferText = "nada disso" }
        await store.send(.interpretTransferTapped) { $0.phase = .processing }
        await store.receive(\.transferScanResponse) { $0.phase = .transferFailure(.notATransfer) }

        await store.send(.scanAgainTapped) { $0.phase = .idle }
        #expect(store.state.transferText == "nada disso")
    }

    @Test
    func discardingClearsTheDraft() async {
        let store = Self.transferStore()

        await store.send(.transferTextChanged(MockData.transferReceiptText)) {
            $0.transferText = MockData.transferReceiptText
        }
        await store.send(.interpretTransferTapped) { $0.phase = .processing }
        await store.receive(\.transferScanResponse) {
            $0.phase = .transfer(MockData.transferScan)
            $0.transferCategory = MockData.transferScan.category
            $0.transferLinked = true
        }

        await store.send(.discardTransferTapped) {
            $0.phase = .idle
            $0.transferText = ""
            $0.transferCategory = .other
            $0.transferLinked = false
        }
    }

    /// The gallery is shared with the photo mode, but here a pick attaches rather than identifies.
    @Test
    func aGalleryPickInTransferModeAttachesThePrint() async {
        let print = Data("png".utf8)
        let store = Self.transferStore()

        await store.send(.choosePhotoTapped) { $0.photoPickerPresented = true }
        await store.send(.photoPickerPresented(false)) { $0.photoPickerPresented = false }
        await store.send(.photoPicked(print)) { $0.transferImage = print }

        #expect(store.state.transferReady)
        await store.send(.transferImageCleared) { $0.transferImage = nil }
        #expect(store.state.transferReady == false)
    }

    /// Nothing to light up once the camera is off.
    @Test
    func switchingToTransferTurnsTheTorchOff() async {
        let store = TestStore(initialState: ScanFeature.State()) { ScanFeature() }

        await store.send(.flashTapped) { $0.flashOn = true }
        await store.send(.modeChanged(.transfer)) {
            $0.scanMode = .transfer
            $0.flashOn = false
        }
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

struct TransferScanRepositoryTests {
    @Test
    func thePrintAndTheTextTravelInTheSameMultipartBody() async throws {
        let png = try sampleImageData()
        let result = try await withDependencies {
            $0.apiClient.send = { request in
                #expect(request.method == "POST")
                #expect(request.path == "scan/transfer")
                #expect((request.timeout ?? 0) > 60)

                let body = try #require(request.body)
                let text = try #require(String(data: body, encoding: .isoLatin1))
                #expect(text.contains(#"name="text""#))
                #expect(text.contains("Comprovante de Pix"))
                #expect(text.contains(#"name="image""#))
                #expect(text.contains("Content-Type: image/jpeg"))
                #expect(body.range(of: Data([0xFF, 0xD8, 0xFF])) != nil)

                return try envelope(MockData.transferScan)
            }
        } operation: {
            try await TransferScanRepository.liveValue.interpret(
                imageData: png,
                text: MockData.transferReceiptText
            )
        }

        #expect(result == MockData.transferScan)
    }

    /// Banks put the amount in the screenshot, in the text, or both — one of the two is enough.
    @Test
    func textOnItsOwnIsEnoughToInterpret() async throws {
        let result = try await withDependencies {
            $0.apiClient.send = { request in
                let body = try #require(request.body)
                let text = try #require(String(data: body, encoding: .utf8))
                #expect(!text.contains(#"name="image""#))
                return try envelope(MockData.transferScan)
            }
        } operation: {
            try await TransferScanRepository.liveValue.interpret(imageData: nil, text: "Pix de R$ 128,40")
        }

        #expect(result == MockData.transferScan)
    }

    @Test
    func nothingToReadNeverReachesTheServer() async throws {
        await #expect(throws: TransferScanFailure.invalidInput) {
            try await withDependencies {
                $0.apiClient.send = { _ in
                    Issue.record("the client should not upload an empty comprovante")
                    return Data()
                }
            } operation: {
                try await TransferScanRepository.liveValue.interpret(imageData: nil, text: nil)
            }
        }
    }

    @Test
    func serverErrorCodesMapToTransferFailures() async throws {
        for (errorCode, expected) in [
            ("invalid_input", TransferScanFailure.invalidInput),
            ("not_a_transfer", .notATransfer),
            ("ai_invalid_output", .aiInvalidOutput),
            ("ai_unavailable", .aiUnavailable),
        ] {
            await #expect(throws: expected) {
                try await withDependencies {
                    $0.apiClient.send = { _ in
                        throw APIError.server(status: 502, errorCode: errorCode, message: nil)
                    }
                } operation: {
                    try await TransferScanRepository.liveValue.interpret(imageData: nil, text: "Pix")
                }
            }
        }
    }

    @Test
    func aSavedTransferLandsInTheLocalMirror() async throws {
        let database = try inMemoryDatabase()
        let purchase = MockData.pixPurchase(MockData.transfer, category: .grocery)
        let request = TransferSaveRequest(
            transfer: MockData.transfer,
            category: .grocery,
            linkedPurchaseId: nil
        )

        let result = try await withDependencies {
            $0.database = database
            $0.apiClient.send = { apiRequest in
                #expect(apiRequest.method == "POST")
                #expect(apiRequest.path == "transfers")
                return try envelope(TransferSaveResult(transfer: MockData.transfer, purchase: purchase))
            }
        } operation: {
            try await TransferScanRepository.liveValue.save(request: request)
        }

        #expect(result.purchase == purchase)
        let mirrored = try await MirrorStore(writer: database).purchase(id: purchase.id)
        #expect(mirrored == purchase)
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
        await store.receive(\.localLoaded) {
            $0.summaries = MockData.summaries
            $0.sections = HistoryFeature.makeSections(MockData.summaries)
            $0.hero = HistoryFeature.makeHero(summaries: MockData.summaries, categorySpending: [:])
        }
        await store.receive(\.syncFinished) { $0.isSyncing = false }
        await store.receive(\.categorySpendingLoaded) {
            $0.monthCategorySpending = categorySpending(of: [MockData.atacadao, MockData.assai, MockData.paoDeAcucar])
            $0.hero = HistoryFeature.makeHero(
                summaries: MockData.summaries,
                categorySpending: $0.monthCategorySpending
            )
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
            $0.sections = HistoryFeature.makeSections($0.summaries)
            $0.hero = HistoryFeature.makeHero(summaries: $0.summaries, categorySpending: [:])
        }
        await store.receive(\.syncFinished) { $0.isSyncing = false }
        await store.receive(\.categorySpendingLoaded) {
            $0.monthCategorySpending = categorySpending(of: [MockData.atacadao])
            $0.hero = HistoryFeature.makeHero(summaries: $0.summaries, categorySpending: $0.monthCategorySpending)
        }
    }

    @Test
    func syncPrunesPurchasesTheServerNoLongerReturns() async throws {
        let database = try inMemoryDatabase()
        var stale = MockData.atacadao
        stale.id = "2026-03-26_atacadao_legacy"
        try await MirrorStore(writer: database).save([stale, MockData.carrefour])
        var state = HistoryFeature.State()
        state.didStartInitialSync = true
        state.didLoad = true
        let store = TestStore(initialState: state) {
            HistoryFeature()
        } withDependencies: {
            $0.purchasesRepository = .liveValue
            $0.database = database
            $0.apiClient.send = { _ in
                try envelope(PurchasePage(items: [MockData.carrefour], page: 1, pageSize: 1, total: 1, hasMore: false))
            }
        }

        await store.send(.refresh) { $0.isSyncing = true }
        await store.receive(\.localLoaded) {
            $0.summaries = [MockData.carrefour.summary]
            $0.sections = HistoryFeature.makeSections($0.summaries)
            $0.hero = HistoryFeature.makeHero(summaries: $0.summaries, categorySpending: [:])
        }
        await store.receive(\.syncFinished) { $0.isSyncing = false }
        await store.receive(\.categorySpendingLoaded) {
            $0.monthCategorySpending = categorySpending(of: [MockData.carrefour])
            $0.hero = HistoryFeature.makeHero(summaries: $0.summaries, categorySpending: $0.monthCategorySpending)
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
            $0.sections = HistoryFeature.makeSections(MockData.summaries)
            $0.hero = HistoryFeature.makeHero(summaries: MockData.summaries, categorySpending: [:])
        }
        await store.receive(\.syncFinished) { $0.isSyncing = false }
        await store.receive(\.categorySpendingLoaded) {
            $0.monthCategorySpending = categorySpending(of: [MockData.atacadao, MockData.assai, MockData.paoDeAcucar])
            $0.hero = HistoryFeature.makeHero(
                summaries: MockData.summaries,
                categorySpending: $0.monthCategorySpending
            )
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
        await store.receive(\.searchResults) {
            $0.searchResults = [MockData.atacadao.summary]
            $0.sections = HistoryFeature.makeSections([MockData.atacadao.summary])
        }

        await store.send(.searchChanged("")) {
            $0.searchText = ""
            $0.searchResults = nil
            $0.sections = []
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

struct HistoryDerivedStateTests {
    @Test
    func sectionsGroupByMonthNewestFirst() {
        let sections = HistoryFeature.makeSections(MockData.summaries)

        #expect(sections.map(\.id) == ["2026-03", "2026-02"])
        #expect(sections[0].total == 208.75 + 156.40 + 92.15)
        #expect(sections[0].purchases.map(\.id) == [
            MockData.atacadao.id, MockData.assai.id, MockData.paoDeAcucar.id,
        ])
        #expect(sections[1].total == 312.80)
        #expect(sections[1].purchases.map(\.id) == [MockData.carrefour.id])
    }

    @Test
    func heroSummarizesTheLatestMonth() throws {
        let spending: [LedgerKit.Category: Double] = [.meat: 300, .grocery: 200, .produce: 100, .bakery: 50]

        let hero = try #require(HistoryFeature.makeHero(summaries: MockData.summaries, categorySpending: spending))

        #expect(hero.monthName == "março")
        #expect(hero.total == 208.75 + 156.40 + 92.15)
        #expect(hero.purchaseCount == 3)
        #expect(hero.trendPercent == 46)
        #expect(hero.points == [
            .init(date: "2026-03-18", cumulative: 92.15),
            .init(date: "2026-03-22", cumulative: 92.15 + 156.40),
            .init(date: "2026-03-26", cumulative: 92.15 + 156.40 + 208.75),
        ])
        #expect(hero.topCategories.map(\.category) == [.meat, .grocery, .produce])
    }

    @Test
    func heroIsAbsentWithoutPurchases() {
        #expect(HistoryFeature.makeHero(summaries: [], categorySpending: [:]) == nil)
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
