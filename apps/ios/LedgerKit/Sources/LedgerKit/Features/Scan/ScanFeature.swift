import ComposableArchitecture
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The capture flow: the live camera auto-detects an NFC-e QR, then runs
/// detecting → processing → result. The result is a bottom sheet with four
/// outcomes (saved, duplicate, warning, error). Camera authorization is shared
/// with Settings.
@Reducer
struct ScanFeature {
    @ObservableState
    struct State: Equatable {
        var phase: Phase = .idle
        var flashOn = false
        var itemsExpanded = false
        var cameraAvailable = true
        @Shared(.inMemory("cameraAuthorized")) var cameraAuthorized = true

        enum Phase: Equatable {
            case idle
            case detecting
            case processing
            case result(ScanResponse)
            case failure(ScanFailure)
        }

        /// The result sheet is up for everything past detection.
        var isSheetPresented: Bool {
            switch phase {
            case .processing, .result, .failure: true
            case .idle, .detecting: false
            }
        }
    }

    enum Action: Equatable {
        case onAppear
        case cameraAuthorizationResponse(Bool)
        case codeScanned(String)
        case detected(String)
        case scanResponse(Result<ScanResponse, ScanFailure>)
        case flashTapped
        case toggleItems
        case scanAgainTapped
        case sheetDismissed
        case choosePhotoTapped
        case settingsTapped
        case openSystemSettings
        case showDuplicateInHistory
        case delegate(Delegate)

        enum Delegate: Equatable {
            case openSettings
            case showHistory
        }
    }

    @Dependency(\.apiClient) var apiClient
    @Dependency(\.cameraClient) var cameraClient
    @Dependency(\.databaseClient) var databaseClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.openURL) var openURL

    private enum CancelID { case scan }

    /// A valid NFC-e QR carries `?p=` or `&p=` followed by exactly the 44-digit
    /// access key (the backend bar). We hand the full URL through unchanged.
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
                guard state.phase == .idle else { return .none }
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
                        let response = try await apiClient.scan(url)
                        await send(.scanResponse(.success(response)))
                    } catch let failure as ScanFailure {
                        await send(.scanResponse(.failure(failure)))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.scanResponse(.failure(.parseFailed)))
                    }
                }
                .cancellable(id: CancelID.scan)

            case let .scanResponse(.success(response)):
                state.phase = .result(response)
                // Mirror the purchase locally right away so History shows it
                // even offline. Best effort: History re-syncs from the server.
                return .run { _ in try? await databaseClient.save([response.purchase]) }

            case let .scanResponse(.failure(failure)):
                state.phase = .failure(failure)
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
                return .cancel(id: CancelID.scan)

            case .choosePhotoTapped:
                // Future: photo fallback → POST /scan-image. No-op for now.
                return .none

            case .settingsTapped:
                return .send(.delegate(.openSettings))

            case .openSystemSettings:
                return .run { _ in
                    #if canImport(UIKit)
                    await openURL(URL(string: UIApplication.openSettingsURLString)!)
                    #endif
                }

            case .showDuplicateInHistory:
                return .send(.delegate(.showHistory))

            case .delegate:
                return .none
            }
        }
    }
}
