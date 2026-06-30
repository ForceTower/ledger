import ComposableArchitecture
import Foundation

/// The capture flow: a viewfinder that, on tap, runs detecting → processing →
/// result. The result is a bottom sheet with four outcomes (saved, duplicate,
/// warning, error). Camera authorization is shared with Settings.
@Reducer
struct ScanFeature {
    @ObservableState
    struct State: Equatable {
        var phase: Phase = .idle
        var flashOn = false
        var itemsExpanded = false
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
        case scanTapped
        case detected
        case scanResponse(Result<ScanResponse, ScanFailure>)
        case flashTapped
        case toggleItems
        case scanAgainTapped
        case sheetDismissed
        case choosePhotoTapped
        case settingsTapped
        case showDuplicateInHistory
        case delegate(Delegate)

        enum Delegate: Equatable {
            case openSettings
            case showHistory
        }
    }

    @Dependency(\.apiClient) var apiClient
    @Dependency(\.continuousClock) var clock

    private enum CancelID { case scan }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .scanTapped:
                guard state.cameraAuthorized, state.phase == .idle else { return .none }
                state.phase = .detecting
                return .run { send in
                    try await clock.sleep(for: .seconds(0.85))
                    await send(.detected)
                }
                .cancellable(id: CancelID.scan)

            case .detected:
                state.phase = .processing
                return .run { send in
                    do {
                        try await clock.sleep(for: .seconds(1.7))
                        let response = try await apiClient.scan("mock://nfce")
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
                return .none

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

            case .showDuplicateInHistory:
                return .send(.delegate(.showHistory))

            case .delegate:
                return .none
            }
        }
    }
}
