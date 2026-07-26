import ComposableArchitecture
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum ScanMode: String, CaseIterable, Equatable, Sendable {
    case receipt, photo, transfer

    var label: String {
        switch self {
        case .receipt: "Nota fiscal"
        case .photo: "Foto"
        case .transfer: "Transferência"
        }
    }

    /// Only the QR reader needs a live camera; the transfer receipt arrives from the photo library.
    var usesCamera: Bool { self != .transfer }
}

/// An open SEFAZ access-key consultation: the anti-robot image the owner must read so the server
/// can fetch a note whose QR the SEFAZ refused.
struct CaptchaChallenge: Equatable, Sendable {
    var challengeId: String
    /// JPEG bytes of the captcha image.
    var image: Data
}

/// One item the AI found in a photo, plus the price and quantity — prefilled when the AI could
/// read them off the photo, the owner's to finish.
struct ProductDraft: Equatable, Identifiable, Sendable {
    /// Position in the AI's list, which is also the row's identity.
    let id: Int
    let item: PhotoScanItem
    var quantity = 1
    var unitPrice = 0.0
    /// A photo can pick up items the owner does not want; unticking leaves them out.
    var selected = true

    var total: Double { unitPrice * Double(quantity) }
}

@Reducer
struct ScanFeature {
    @ObservableState
    struct State: Equatable {
        var phase: Phase = .idle
        var scanMode: ScanMode = .receipt
        var flashOn = false
        var itemsExpanded = false
        /// One editable row per item the AI found in the photo.
        var productDrafts: IdentifiedArrayOf<ProductDraft> = []
        var productSaved = false
        var photoPickerPresented = false
        /// The still we sent to the AI, echoed back next to its guess.
        var capturedPhoto: Data?
        var cameraAvailable = true
        @Shared(.inMemory("cameraAuthorized")) var cameraAuthorized = true

        /// The 44-digit key from the last scanned QR, kept for the access-key fallback.
        var scannedAccessKey: String?
        var captchaAnswer = ""
        /// A challenge request or answer is in flight.
        var captchaBusy = false
        /// Inline complaint after a wrong or lapsed captcha answer, shown next to the fresh image.
        var captchaError: String?

        /// The Pix receipt being put together: the screenshot, the text the bank gave the owner, or both.
        var transferImage: Data?
        var transferText = ""
        /// The owner's call on what the AI guessed, editable from the moment the result lands.
        var transferCategory: Category = .other
        var transferLinked = false
        var transferTextExpanded = false
        var transferSaving = false

        var trimmedTransferText: String {
            transferText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// The AI needs at least one of the two to have anything to read.
        var transferReady: Bool { transferImage != nil || !trimmedTransferText.isEmpty }

        var selectedDrafts: [ProductDraft] { productDrafts.filter(\.selected) }

        var productTotal: Double {
            selectedDrafts.reduce(0) { $0 + $1.total }
        }

        /// How many units go to the history, counting quantities — not how many rows are ticked.
        var productUnitCount: Int {
            selectedDrafts.reduce(0) { $0 + $1.quantity }
        }

        enum Phase: Equatable {
            case idle
            case detecting
            case capturing
            case processing
            case result(ScanResponse)
            case product(PhotoScanIdentified)
            case rejected(PhotoScanRejected)
            case failure(ScanFailure)
            case captcha(CaptchaChallenge)
            case photoFailure(PhotoScanFailure)
            case transfer(TransferScanResult)
            case transferSaved(TransferSaveResult)
            case transferFailure(TransferScanFailure)
        }

        var isSheetPresented: Bool {
            switch phase {
            case .processing, .result, .product, .rejected, .failure, .captcha, .photoFailure,
                 .transfer, .transferSaved, .transferFailure:
                true
            case .idle, .detecting, .capturing:
                false
            }
        }

        /// Everything a finished scan leaves behind, cleared before the next one.
        mutating func clearResult() {
            phase = .idle
            itemsExpanded = false
            productDrafts = []
            productSaved = false
            capturedPhoto = nil
            transferSaving = false
            transferTextExpanded = false
            scannedAccessKey = nil
            captchaAnswer = ""
            captchaBusy = false
            captchaError = nil
        }

        mutating func clearTransferDraft() {
            transferImage = nil
            transferText = ""
            transferLinked = false
            transferCategory = .other
        }
    }

    enum Action: Equatable {
        case onAppear
        case cameraAuthorizationResponse(Bool)
        case codeScanned(String)
        case detected(String)
        case scanResponse(Result<ScanResponse, ScanFailure>)
        case consultByKeyTapped
        case keyChallengeResponse(Result<KeyScanChallenge, ScanFailure>)
        case captchaAnswerChanged(String)
        case newCaptchaTapped
        case submitCaptchaTapped
        case keyScanResponse(Result<ScanResponse, ScanFailure>)
        case modeChanged(ScanMode)
        case shutterTapped
        case photoCaptured(Data?)
        case photoPicked(Data?)
        case photoScanResponse(Result<PhotoScanResult, PhotoScanFailure>)
        case productQuantityChanged(id: ProductDraft.ID, quantity: Int)
        case productPriceChanged(id: ProductDraft.ID, price: Double)
        case productSelectionToggled(id: ProductDraft.ID)
        case addProductTapped
        case transferImageCleared
        case transferTextChanged(String)
        case interpretTransferTapped
        case transferScanResponse(Result<TransferScanResult, TransferScanFailure>)
        case transferCategoryChanged(Category)
        case transferLinkToggled
        case toggleTransferText
        case saveTransferTapped
        case transferSaveResponse(Result<TransferSaveResult, TransferScanFailure>)
        case discardTransferTapped
        case flashTapped
        case toggleItems
        case scanAgainTapped
        case sheetDismissed
        case choosePhotoTapped
        case photoPickerPresented(Bool)
        case settingsTapped
        case openSystemSettings
        case showInHistoryTapped
        case delegate(Delegate)

        enum Delegate: Equatable {
            case openSettings
            case showHistory
        }
    }

    @Dependency(\.scanRepository) var scanRepository
    @Dependency(\.photoScanRepository) var photoScanRepository
    @Dependency(\.transferScanRepository) var transferScanRepository
    @Dependency(\.cameraClient) var cameraClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.openURL) var openURL

    private enum CancelID { case scan }

    private func identify(_ imageData: Data, _ state: inout State) -> Effect<Action> {
        state.capturedPhoto = imageData
        state.phase = .processing
        return .run { send in
            do {
                let result = try await photoScanRepository.identify(imageData: imageData)
                await send(.photoScanResponse(.success(result)))
            } catch let failure as PhotoScanFailure {
                await send(.photoScanResponse(.failure(failure)))
            } catch {
            }
        }
        .cancellable(id: CancelID.scan)
    }

    static func nfceURL(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.firstMatch(of: /[?&]p=[0-9]{44}(?:[^0-9]|$)/) != nil ? trimmed : nil
    }

    static func accessKey(from url: String) -> String? {
        url.firstMatch(of: /[?&]p=([0-9]{44})/).map { String($0.1) }
    }

    private func startChallenge(_ accessKey: String) -> Effect<Action> {
        .run { send in
            do {
                let challenge = try await scanRepository.startKeyChallenge(accessKey: accessKey)
                await send(.keyChallengeResponse(.success(challenge)))
            } catch let failure as ScanFailure {
                await send(.keyChallengeResponse(.failure(failure)))
            } catch {
            }
        }
        .cancellable(id: CancelID.scan)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.cameraAvailable = cameraClient.isAvailable()
                guard state.cameraAvailable else { return .none }
                return .run { send in
                    let granted: Bool
                    switch cameraClient.authorizationStatus() {
                    case .authorized: granted = true
                    case .notDetermined: granted = await cameraClient.requestAccess()
                    case .denied, .restricted: granted = false
                    }
                    await send(.cameraAuthorizationResponse(granted))
                }

            case let .cameraAuthorizationResponse(granted):
                state.$cameraAuthorized.withLock { $0 = granted }
                return .none

            case let .codeScanned(code):
                guard state.phase == .idle, state.scanMode == .receipt else { return .none }
                guard let url = Self.nfceURL(from: code) else {
                    state.phase = .failure(.invalidQR)
                    return .none
                }
                state.phase = .detecting
                return .run { send in
                    try await clock.sleep(for: .seconds(0.6))
                    await send(.detected(url))
                }
                .cancellable(id: CancelID.scan)

            case let .detected(url):
                state.phase = .processing
                state.scannedAccessKey = Self.accessKey(from: url)
                return .run { send in
                    do {
                        let response = try await scanRepository.scan(url: url)
                        await send(.scanResponse(.success(response)))
                    } catch let failure as ScanFailure {
                        await send(.scanResponse(.failure(failure)))
                    } catch {
                    }
                }
                .cancellable(id: CancelID.scan)

            case let .scanResponse(.success(response)):
                state.phase = .result(response)
                return .none

            case let .scanResponse(.failure(failure)):
                state.phase = .failure(failure)
                return .none

            case .consultByKeyTapped:
                guard case .failure(.qrRejected) = state.phase, let key = state.scannedAccessKey else { return .none }
                state.phase = .processing
                state.captchaError = nil
                return startChallenge(key)

            case .newCaptchaTapped:
                guard case .captcha = state.phase, !state.captchaBusy, let key = state.scannedAccessKey else {
                    return .none
                }
                state.captchaBusy = true
                state.captchaError = nil
                return startChallenge(key)

            case let .keyChallengeResponse(.success(challenge)):
                state.captchaBusy = false
                guard let image = challenge.captchaImageData else {
                    state.phase = .failure(.unavailable)
                    return .none
                }
                state.captchaAnswer = ""
                state.phase = .captcha(CaptchaChallenge(challengeId: challenge.challengeId, image: image))
                return .none

            case let .keyChallengeResponse(.failure(failure)):
                state.captchaBusy = false
                state.phase = .failure(failure)
                return .none

            case let .captchaAnswerChanged(answer):
                state.captchaAnswer = answer
                return .none

            case .submitCaptchaTapped:
                guard case let .captcha(challenge) = state.phase, !state.captchaBusy else { return .none }
                let answer = state.captchaAnswer.trimmingCharacters(in: .whitespaces)
                guard !answer.isEmpty else { return .none }
                state.captchaBusy = true
                state.captchaError = nil
                return .run { send in
                    do {
                        let response = try await scanRepository.completeKeyChallenge(
                            challengeId: challenge.challengeId,
                            captcha: answer
                        )
                        await send(.keyScanResponse(.success(response)))
                    } catch let failure as ScanFailure {
                        await send(.keyScanResponse(.failure(failure)))
                    } catch {
                    }
                }
                .cancellable(id: CancelID.scan)

            case let .keyScanResponse(.success(response)):
                state.captchaBusy = false
                state.captchaAnswer = ""
                state.phase = .result(response)
                return .none

            // SEFAZ spends the image on every attempt, so a wrong or lapsed answer means fetching a
            // fresh challenge before the owner can try again — the sheet stays up, only complaining.
            case .keyScanResponse(.failure(.captchaRejected)):
                guard let key = state.scannedAccessKey else { return .none }
                state.captchaError = "Código incorreto. Tente de novo com a nova imagem."
                return startChallenge(key)

            case .keyScanResponse(.failure(.challengeExpired)):
                guard let key = state.scannedAccessKey else { return .none }
                state.captchaError = "A verificação expirou. Digite o código da nova imagem."
                return startChallenge(key)

            case let .keyScanResponse(.failure(failure)):
                state.captchaBusy = false
                state.phase = .failure(failure)
                return .none

            case let .modeChanged(mode):
                guard state.phase == .idle else { return .none }
                state.scanMode = mode
                // The torch belongs to a camera that is about to be shut down.
                if !mode.usesCamera { state.flashOn = false }
                return .none

            case .shutterTapped:
                guard state.phase == .idle, state.scanMode == .photo else { return .none }
                state.phase = .capturing
                return .none

            case let .photoCaptured(data):
                guard state.phase == .capturing else { return .none }
                guard let data else {
                    state.phase = .photoFailure(.captureFailed)
                    return .none
                }
                return identify(data, &state)

            case let .photoPicked(data):
                // The picker dismisses itself before the image finishes loading, so this lands on .idle.
                guard state.phase == .idle else { return .none }
                if state.scanMode == .transfer {
                    guard let data else {
                        state.phase = .transferFailure(.invalidInput)
                        return .none
                    }
                    state.transferImage = data
                    return .none
                }
                guard let data else {
                    state.phase = .photoFailure(.invalidImage)
                    return .none
                }
                return identify(data, &state)

            case let .photoScanResponse(.success(.identified(identified))):
                state.phase = .product(identified)
                state.productDrafts = IdentifiedArray(
                    uniqueElements: identified.items.enumerated().map { index, item in
                        ProductDraft(
                            id: index,
                            item: item,
                            quantity: max(1, item.quantity ?? 1),
                            unitPrice: max(0, item.unitPrice ?? 0)
                        )
                    }
                )
                state.productSaved = false
                return .none

            case let .photoScanResponse(.success(.rejected(rejected))):
                state.phase = .rejected(rejected)
                return .none

            case let .photoScanResponse(.failure(failure)):
                state.phase = .photoFailure(failure)
                return .none

            case let .productQuantityChanged(id, quantity):
                state.productDrafts[id: id]?.quantity = max(1, quantity)
                return .none

            case let .productPriceChanged(id, price):
                state.productDrafts[id: id]?.unitPrice = max(0, price)
                return .none

            case let .productSelectionToggled(id):
                state.productDrafts[id: id]?.selected.toggle()
                return .none

            case .addProductTapped:
                guard !state.selectedDrafts.isEmpty else { return .none }
                state.productSaved = true
                return .none

            case .transferImageCleared:
                state.transferImage = nil
                return .none

            case let .transferTextChanged(text):
                state.transferText = text
                return .none

            case .interpretTransferTapped:
                guard state.phase == .idle, state.scanMode == .transfer, state.transferReady else { return .none }
                let image = state.transferImage
                let text = state.trimmedTransferText.isEmpty ? nil : state.trimmedTransferText
                state.phase = .processing
                return .run { send in
                    do {
                        let result = try await transferScanRepository.interpret(imageData: image, text: text)
                        await send(.transferScanResponse(.success(result)))
                    } catch let failure as TransferScanFailure {
                        await send(.transferScanResponse(.failure(failure)))
                    } catch {
                    }
                }
                .cancellable(id: CancelID.scan)

            case let .transferScanResponse(.success(result)):
                state.phase = .transfer(result)
                state.transferCategory = result.category
                // Linking is only offered when the server found a note it could be paying for.
                state.transferLinked = result.match != nil
                state.transferTextExpanded = false
                return .none

            case let .transferScanResponse(.failure(failure)):
                state.phase = .transferFailure(failure)
                return .none

            case let .transferCategoryChanged(category):
                state.transferCategory = category
                return .none

            case .transferLinkToggled:
                state.transferLinked.toggle()
                return .none

            case .toggleTransferText:
                state.transferTextExpanded.toggle()
                return .none

            case .saveTransferTapped:
                guard case let .transfer(result) = state.phase, !state.transferSaving else { return .none }
                state.transferSaving = true
                let request = TransferSaveRequest(
                    transfer: result.transfer,
                    category: state.transferCategory,
                    linkedPurchaseId: state.transferLinked ? result.match?.purchaseId : nil
                )
                return .run { send in
                    do {
                        let saved = try await transferScanRepository.save(request: request)
                        await send(.transferSaveResponse(.success(saved)))
                    } catch let failure as TransferScanFailure {
                        await send(.transferSaveResponse(.failure(failure)))
                    } catch {
                    }
                }
                .cancellable(id: CancelID.scan)

            case let .transferSaveResponse(.success(saved)):
                state.transferSaving = false
                state.phase = .transferSaved(saved)
                return .none

            case let .transferSaveResponse(.failure(failure)):
                state.transferSaving = false
                state.phase = .transferFailure(failure)
                return .none

            case .discardTransferTapped:
                state.clearResult()
                state.clearTransferDraft()
                return .cancel(id: CancelID.scan)

            case .flashTapped:
                state.flashOn.toggle()
                return .none

            case .toggleItems:
                state.itemsExpanded.toggle()
                return .none

            // A saved transfer is spent; anything short of that is worth retrying without retyping.
            case .scanAgainTapped, .sheetDismissed:
                if case .transferSaved = state.phase { state.clearTransferDraft() }
                state.clearResult()
                return .cancel(id: CancelID.scan)

            case .choosePhotoTapped:
                guard state.phase == .idle else { return .none }
                state.photoPickerPresented = true
                return .none

            case let .photoPickerPresented(presented):
                state.photoPickerPresented = presented
                return .none

            case .settingsTapped:
                return .send(.delegate(.openSettings))

            case .openSystemSettings:
                return .run { _ in
                    #if canImport(UIKit)
                    await openURL(URL(string: UIApplication.openSettingsURLString)!)
                    #endif
                }

            case .showInHistoryTapped:
                state.clearResult()
                state.clearTransferDraft()
                return .concatenate(
                    .cancel(id: CancelID.scan),
                    .send(.delegate(.showHistory))
                )

            case .delegate:
                return .none
            }
        }
    }
}
