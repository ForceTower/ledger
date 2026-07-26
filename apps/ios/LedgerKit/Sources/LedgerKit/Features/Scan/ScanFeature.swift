import ComposableArchitecture
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum ScanMode: String, CaseIterable, Equatable, Sendable {
    case receipt, photo, entry

    var label: String {
        switch self {
        case .receipt: "Nota fiscal"
        case .photo: "Foto"
        case .entry: "Lançamento"
        }
    }

    /// Only the QR reader needs a live camera; a lançamento is typed, and its print — when there is
    /// one — arrives from the photo library.
    var usesCamera: Bool { self != .entry }
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

/// One line of the draft the AI put together from the owner's description. Everything about it is
/// the owner's to correct — down to what it is called and which category it belongs to.
struct EntryItemDraft: Equatable, Identifiable, Sendable {
    let id: Int
    var description: String
    var category: Category = .other
    var quantity = 1
    var unitPrice = 0.0
    /// A description can mention things the owner does not want on the ledger; unticking leaves them out.
    var selected = true

    var total: Double { unitPrice * Double(quantity) }

    var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
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

        /// The lançamento being described: the owner's own words, plus a print when they have one.
        var entryText = ""
        var entryImage: Data?
        var entryTextExpanded = false
        var entrySaving = false

        /// The draft under review, editable from the moment the AI's reading lands.
        var entryStore = ""
        var entryDate = ""
        var entryPaymentMethod: String?
        var entryItems: IdentifiedArrayOf<EntryItemDraft> = []

        var trimmedEntryText: String {
            entryText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// The words are the point, but a print alone is enough for the AI to have something to read.
        var entryReady: Bool { !trimmedEntryText.isEmpty || entryImage != nil }

        var selectedEntryItems: [EntryItemDraft] { entryItems.filter(\.selected) }

        var entryTotal: Double {
            selectedEntryItems.reduce(0) { $0 + $1.total }
        }

        /// Every line that goes to the history needs a name, and the purchase needs somewhere to sit.
        var entrySavable: Bool {
            !selectedEntryItems.isEmpty
                && !entryStore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && selectedEntryItems.allSatisfy { !$0.trimmedDescription.isEmpty }
        }

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
            case entry(EntryDraft)
            case entrySaved(Purchase)
            case entryFailure(EntryScanFailure)
        }

        var isSheetPresented: Bool {
            switch phase {
            case .processing, .result, .product, .rejected, .failure, .captcha, .photoFailure,
                 .entry, .entrySaved, .entryFailure:
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
            entrySaving = false
            entryTextExpanded = false
            entryItems = []
            entryStore = ""
            entryDate = ""
            entryPaymentMethod = nil
            scannedAccessKey = nil
            captchaAnswer = ""
            captchaBusy = false
            captchaError = nil
        }

        /// What the owner typed, which outlives a failed reading — only a saved lançamento spends it.
        mutating func clearEntryComposition() {
            entryText = ""
            entryImage = nil
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
        case entryImageCleared
        case entryTextChanged(String)
        case interpretEntryTapped
        case entryScanResponse(Result<EntryDraft, EntryScanFailure>)
        case entryStoreChanged(String)
        case entryDateChanged(String)
        case entryItemDescriptionChanged(id: EntryItemDraft.ID, description: String)
        case entryItemCategoryChanged(id: EntryItemDraft.ID, category: Category)
        case entryItemQuantityChanged(id: EntryItemDraft.ID, quantity: Int)
        case entryItemPriceChanged(id: EntryItemDraft.ID, price: Double)
        case entryItemSelectionToggled(id: EntryItemDraft.ID)
        case addEntryItemTapped
        case toggleEntryText
        case saveEntryTapped
        case entrySaveResponse(Result<Purchase, EntryScanFailure>)
        case discardEntryTapped
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
    @Dependency(\.entryRepository) var entryRepository
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
                if state.scanMode == .entry {
                    guard let data else {
                        state.phase = .entryFailure(.invalidInput)
                        return .none
                    }
                    state.entryImage = data
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

            case .entryImageCleared:
                state.entryImage = nil
                return .none

            case let .entryTextChanged(text):
                state.entryText = text
                return .none

            case .interpretEntryTapped:
                guard state.phase == .idle, state.scanMode == .entry, state.entryReady else { return .none }
                let text = state.trimmedEntryText.isEmpty ? nil : state.trimmedEntryText
                let image = state.entryImage
                state.phase = .processing
                return .run { send in
                    do {
                        let draft = try await entryRepository.interpret(text: text, imageData: image)
                        await send(.entryScanResponse(.success(draft)))
                    } catch let failure as EntryScanFailure {
                        await send(.entryScanResponse(.failure(failure)))
                    } catch {
                    }
                }
                .cancellable(id: CancelID.scan)

            case let .entryScanResponse(.success(draft)):
                state.phase = .entry(draft)
                state.entryDate = draft.date
                // A lançamento often names no place; the thing paid for is the best stand-in for one.
                state.entryStore = draft.store ?? draft.items.first?.description ?? ""
                state.entryPaymentMethod = draft.paymentMethod
                state.entryItems = IdentifiedArray(
                    uniqueElements: draft.items.enumerated().map { index, item in
                        EntryItemDraft(
                            id: index,
                            description: item.description,
                            category: item.category,
                            quantity: max(1, item.quantity ?? 1),
                            unitPrice: max(0, item.unitPrice ?? 0)
                        )
                    }
                )
                state.entryTextExpanded = false
                return .none

            case let .entryScanResponse(.failure(failure)):
                state.phase = .entryFailure(failure)
                return .none

            case let .entryStoreChanged(store):
                state.entryStore = store
                return .none

            case let .entryDateChanged(date):
                state.entryDate = date
                return .none

            case let .entryItemDescriptionChanged(id, description):
                state.entryItems[id: id]?.description = description
                return .none

            case let .entryItemCategoryChanged(id, category):
                state.entryItems[id: id]?.category = category
                return .none

            case let .entryItemQuantityChanged(id, quantity):
                state.entryItems[id: id]?.quantity = max(1, quantity)
                return .none

            case let .entryItemPriceChanged(id, price):
                state.entryItems[id: id]?.unitPrice = max(0, price)
                return .none

            case let .entryItemSelectionToggled(id):
                state.entryItems[id: id]?.selected.toggle()
                return .none

            case .addEntryItemTapped:
                guard case .entry = state.phase else { return .none }
                state.entryItems.append(EntryItemDraft(id: (state.entryItems.ids.max() ?? -1) + 1, description: ""))
                return .none

            case .toggleEntryText:
                state.entryTextExpanded.toggle()
                return .none

            case .saveEntryTapped:
                guard case let .entry(draft) = state.phase, !state.entrySaving, state.entrySavable else { return .none }
                state.entrySaving = true
                let request = PurchaseCreateRequest(
                    date: state.entryDate,
                    time: draft.time,
                    store: state.entryStore.trimmingCharacters(in: .whitespacesAndNewlines),
                    paymentMethod: state.entryPaymentMethod,
                    items: state.selectedEntryItems.map { item in
                        PurchaseCreateItem(
                            description: item.trimmedDescription,
                            category: item.category,
                            quantity: item.quantity,
                            unitPrice: item.unitPrice
                        )
                    }
                )
                return .run { send in
                    do {
                        let purchase = try await entryRepository.save(request: request)
                        await send(.entrySaveResponse(.success(purchase)))
                    } catch let failure as EntryScanFailure {
                        await send(.entrySaveResponse(.failure(failure)))
                    } catch {
                    }
                }
                .cancellable(id: CancelID.scan)

            case let .entrySaveResponse(.success(purchase)):
                state.entrySaving = false
                state.phase = .entrySaved(purchase)
                return .none

            case let .entrySaveResponse(.failure(failure)):
                state.entrySaving = false
                state.phase = .entryFailure(failure)
                return .none

            case .discardEntryTapped:
                state.clearResult()
                state.clearEntryComposition()
                return .cancel(id: CancelID.scan)

            case .flashTapped:
                state.flashOn.toggle()
                return .none

            case .toggleItems:
                state.itemsExpanded.toggle()
                return .none

            // A saved lançamento is spent; anything short of that is worth retrying without retyping.
            case .scanAgainTapped, .sheetDismissed:
                if case .entrySaved = state.phase { state.clearEntryComposition() }
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
                state.clearEntryComposition()
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
