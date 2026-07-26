import ComposableArchitecture
import Foundation

@Reducer
struct AskFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.chatTranscript) var transcript: [ChatMessage] = []
        /// The server-side conversation this transcript continues; nil until the first turn answers.
        @Shared(.appStorage("chatSessionId")) var sessionId: String?
        var composer = ""
        var isStreaming = false
        /// A `tool` event arrived for the in-flight turn and no text has followed yet.
        var isConsulting = false
        /// The assistant bubble the in-flight turn is streaming into.
        var streamingMessageId: UUID?
        var errorMessage: String?
    }

    enum Action: Equatable {
        case composerChanged(String)
        case sendTapped
        case suggestionTapped(String)
        case retryTapped
        case stopTapped
        case newConversationTapped
        case stream(ChatStreamEvent)
        case streamEnded
        case streamFailed(ChatFailure)
    }

    private enum CancelID { case stream }

    @Dependency(\.chatRepository) var chatRepository
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .composerChanged(text):
                state.composer = text
                return .none

            case .sendTapped:
                let text = state.composer.trimmingCharacters(in: .whitespacesAndNewlines)
                state.composer = ""
                return ask(text, state: &state)

            case let .suggestionTapped(text):
                return ask(text, state: &state)

            // The failed turn never reached the server-side session, so resending the same user
            // message continues cleanly — only the assistant placeholder needs recreating.
            case .retryTapped:
                guard let lastQuestion = state.transcript.last(where: { $0.role == .user }) else { return .none }
                return start(lastQuestion.text, state: &state)

            case .stopTapped:
                finish(state: &state, discardEmptyAnswer: true)
                return .cancel(id: CancelID.stream)

            case .newConversationTapped:
                state.$transcript.withLock { $0 = [] }
                state.$sessionId.withLock { $0 = nil }
                state.composer = ""
                finish(state: &state, discardEmptyAnswer: false)
                return .cancel(id: CancelID.stream)

            case let .stream(.session(id)):
                state.$sessionId.withLock { $0 = id }
                return .none

            case let .stream(.text(chunk)):
                state.isConsulting = false
                guard let id = state.streamingMessageId else { return .none }
                state.$transcript.withLock { transcript in
                    guard let index = transcript.lastIndex(where: { $0.id == id }) else { return }
                    transcript[index].text += chunk
                }
                return .none

            case .stream(.tool):
                state.isConsulting = true
                return .none

            case let .stream(.done(sessionId)):
                state.$sessionId.withLock { $0 = sessionId }
                finish(state: &state, discardEmptyAnswer: true)
                return .none

            case .streamEnded:
                // A stream that closes without `done` (or `error`) means the connection dropped.
                guard state.isStreaming else { return .none }
                finish(state: &state, discardEmptyAnswer: true)
                state.errorMessage = Self.fallbackError
                return .none

            case let .streamFailed(failure):
                finish(state: &state, discardEmptyAnswer: true)
                switch failure {
                case .notConfigured:
                    state.errorMessage = "Configure o endereço do servidor nos ajustes antes de perguntar."
                case let .unavailable(message):
                    state.errorMessage = message ?? Self.fallbackError
                }
                return .none
            }
        }
    }

    private static let fallbackError = "O assistente está indisponível no momento. Tente novamente."

    /// Appends the user's bubble and starts the turn. No-op for empty input or while a turn runs.
    private func ask(_ text: String, state: inout State) -> Effect<Action> {
        guard !text.isEmpty, !state.isStreaming else { return .none }
        state.$transcript.withLock { [message = ChatMessage(id: uuid(), role: .user, text: text, date: now)] in
            $0.append(message)
        }
        return start(text, state: &state)
    }

    /// Creates the assistant placeholder and runs the turn against the server.
    private func start(_ text: String, state: inout State) -> Effect<Action> {
        guard !state.isStreaming else { return .none }
        let placeholder = ChatMessage(id: uuid(), role: .assistant, text: "", date: now)
        state.$transcript.withLock { $0.append(placeholder) }
        state.streamingMessageId = placeholder.id
        state.isStreaming = true
        state.isConsulting = false
        state.errorMessage = nil

        return .run { [sessionId = state.sessionId] send in
            for try await event in try await chatRepository.send(message: text, sessionId: sessionId) {
                await send(.stream(event))
            }
            await send(.streamEnded)
        } catch: { error, send in
            if error is CancellationError { return }
            await send(.streamFailed(error as? ChatFailure ?? .unavailable(message: nil)))
        }
        .cancellable(id: CancelID.stream, cancelInFlight: true)
    }

    /// Closes out the in-flight turn; an answer bubble that never got text is dropped, not shown empty.
    private func finish(state: inout State, discardEmptyAnswer: Bool) {
        if discardEmptyAnswer, let id = state.streamingMessageId {
            state.$transcript.withLock { transcript in
                guard let index = transcript.lastIndex(where: { $0.id == id }), transcript[index].text.isEmpty else {
                    return
                }
                transcript.remove(at: index)
            }
        }
        state.isStreaming = false
        state.isConsulting = false
        state.streamingMessageId = nil
    }
}
