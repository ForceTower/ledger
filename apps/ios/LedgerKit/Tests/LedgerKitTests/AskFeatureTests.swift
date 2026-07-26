import ComposableArchitecture
import Foundation
import Testing

@testable import LedgerKit

private func stream(of events: [ChatStreamEvent]) -> AsyncThrowingStream<ChatStreamEvent, Error> {
    AsyncThrowingStream { continuation in
        for event in events {
            continuation.yield(event)
        }
        continuation.finish()
    }
}

// The streaming tests assert the final state rather than stepping through each delta: `@Shared`
// state is not snapshotted per action, so a burst of stream events collapses into one observed
// transcript value and per-step exhaustive assertions cannot line up with it.
@MainActor
struct AskFeatureTests {
    nonisolated static let date = Date(timeIntervalSince1970: 1_772_000_000)

    @Test
    func aTurnStreamsIntoTheTranscriptAndKeepsTheSession() async {
        let store = TestStore(initialState: AskFeature.State()) {
            AskFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Self.date)
            $0.chatRepository.send = { message, sessionId in
                #expect(message == "Quanto gastei este mês?")
                #expect(sessionId == nil)
                return stream(of: [
                    .session(id: "sess-1"),
                    .tool(sql: "SELECT sum(paid_total) FROM purchases"),
                    .text("Você gastou "),
                    .text("**R$ 100,00**."),
                    .done(sessionId: "sess-1"),
                ])
            }
        }
        store.exhaustivity = .off

        await store.send(.composerChanged("Quanto gastei este mês?"))
        await store.send(.sendTapped)
        await store.receive(\.streamEnded)

        #expect(store.state.transcript == [
            ChatMessage(id: UUID(0), role: .user, text: "Quanto gastei este mês?", date: Self.date),
            ChatMessage(id: UUID(1), role: .assistant, text: "Você gastou **R$ 100,00**.", date: Self.date),
        ])
        #expect(store.state.sessionId == "sess-1")
        #expect(store.state.composer == "")
        #expect(store.state.isStreaming == false)
        #expect(store.state.streamingMessageId == nil)
        await store.finish()
    }

    @Test
    func aFailedTurnDropsTheEmptyBubbleAndRetrySucceeds() async {
        let store = TestStore(initialState: AskFeature.State()) {
            AskFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Self.date)
            $0.chatRepository.send = { _, _ in throw ChatFailure.unavailable(message: nil) }
        }
        store.exhaustivity = .off
        let question = ChatMessage(id: UUID(0), role: .user, text: "Compare março com fevereiro", date: Self.date)

        await store.send(.suggestionTapped("Compare março com fevereiro"))
        await store.receive(\.streamFailed)

        #expect(store.state.transcript == [question])
        #expect(store.state.isStreaming == false)
        #expect(store.state.errorMessage == "O assistente está indisponível no momento. Tente novamente.")

        // The failed turn never reached the server; retrying resends the same question.
        store.dependencies.chatRepository.send = { message, _ in
            #expect(message == "Compare março com fevereiro")
            return stream(of: [
                .session(id: "sess-2"),
                .text("Fevereiro foi mais barato."),
                .done(sessionId: "sess-2"),
            ])
        }

        await store.send(.retryTapped)
        await store.receive(\.streamEnded)

        #expect(store.state.transcript == [
            question,
            ChatMessage(id: UUID(2), role: .assistant, text: "Fevereiro foi mais barato.", date: Self.date),
        ])
        #expect(store.state.sessionId == "sess-2")
        #expect(store.state.errorMessage == nil)
        #expect(store.state.isStreaming == false)
        await store.finish()
    }

    @Test
    func aNewConversationClearsTranscriptAndSession() async {
        let state = AskFeature.State()
        state.$transcript.withLock {
            $0 = [ChatMessage(id: UUID(0), role: .user, text: "Oi", date: Self.date)]
        }
        state.$sessionId.withLock { $0 = "sess-1" }

        let store = TestStore(initialState: state) { AskFeature() }

        await store.send(.newConversationTapped) {
            $0.$transcript.withLock { $0 = [] }
            $0.$sessionId.withLock { $0 = nil }
        }
    }
}
