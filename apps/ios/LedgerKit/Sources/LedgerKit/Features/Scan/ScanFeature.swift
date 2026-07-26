import ComposableArchitecture
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum ScanMode: Equatable, Sendable {
    case receipt, photo
}

@Reducer
struct ScanFeature {
    @ObservableState
    struct State: Equatable {
        var phase: Phase = .idle
        var scanMode: ScanMode = .receipt
        var flashOn = false
        var itemsExpanded = false
        var productQuantity = 1
        var productUnitPrice = 0.0
        var productSaved = false
        var photoPickerPresented = false
        /// The still we sent to the AI, echoed back next to its guess.
        var capturedPhoto: Data?
        var cameraAvailable = true
        @Shared(.inMemory("cameraAuthorized")) var cameraAuthorized = true

        enum Phase: Equatable {
            case idle
            case detecting
            case capturing
            case processing
            case result(ScanResponse)
            case product(PhotoScanIdentified)
            case rejected(PhotoScanRejected)
            case failure(ScanFailure)
            case photoFailure(PhotoScanFailure)
        }

        var isSheetPresented: Bool {
            switch phase {
            case .processing, .result, .product, .rejected, .failure, .photoFailure: true
            case .idle, .detecting, .capturing: false
            }
        }
    }

    enum Action: Equatable {
        case onAppear
        case cameraAuthorizationResponse(Bool)
        case codeScanned(String)
        case detected(String)
        case scanResponse(Result<ScanResponse, ScanFailure>)
        case modeChanged(ScanMode)
        case shutterTapped
        case photoCaptured(Data?)
        case photoPicked(Data?)
        case photoScanResponse(Result<PhotoScanResult, PhotoScanFailure>)
        case productQuantityChanged(Int)
        case productPriceChanged(Double)
        case addProductTapped
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

            case let .modeChanged(mode):
                guard state.phase == .idle else { return .none }
                state.scanMode = mode
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
                guard let data else {
                    state.phase = .photoFailure(.invalidImage)
                    return .none
                }
                return identify(data, &state)

            case let .photoScanResponse(.success(.identified(identified))):
                state.phase = .product(identified)
                state.productQuantity = 1
                state.productUnitPrice = 0
                state.productSaved = false
                return .none

            case let .photoScanResponse(.success(.rejected(rejected))):
                state.phase = .rejected(rejected)
                return .none

            case let .photoScanResponse(.failure(failure)):
                state.phase = .photoFailure(failure)
                return .none

            case let .productQuantityChanged(quantity):
                state.productQuantity = max(1, quantity)
                return .none

            case let .productPriceChanged(price):
                state.productUnitPrice = max(0, price)
                return .none

            case .addProductTapped:
                state.productSaved = true
                return .none

            case .flashTapped:
                state.flashOn.toggle()
                return .none

            case .toggleItems:
                state.itemsExpanded.toggle()
                return .none

            case .scanAgainTapped, .sheetDismissed:
                state.phase = .idle
                state.itemsExpanded = false
                state.productQuantity = 1
                state.productUnitPrice = 0
                state.productSaved = false
                state.capturedPhoto = nil
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
                state.phase = .idle
                state.productSaved = false
                state.capturedPhoto = nil
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
