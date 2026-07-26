import ComposableArchitecture
import Foundation

@DependencyClient
struct ChatRepository: Sendable {
    /// Runs one `POST /chat` turn. The stream yields events in wire order, ends after `done`, and
    /// throws `ChatFailure` when the turn fails.
    var send: @Sendable (_ message: String, _ sessionId: String?) async throws
        -> AsyncThrowingStream<ChatStreamEvent, Error>
}

extension ChatRepository: TestDependencyKey {
    static let testValue = ChatRepository()

    static let previewValue = ChatRepository(send: { _, _ in
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.session(id: "preview-session"))
                continuation.yield(.tool(sql: "SELECT sum(paid_total) FROM purchases"))
                try await Task.sleep(for: .milliseconds(700))
                let chunks = ["Em março você gastou ", "**R$ 488,30**", " em carnes — ", "26% do total, em 4 compras."]
                for chunk in chunks {
                    continuation.yield(.text(chunk))
                    try await Task.sleep(for: .milliseconds(180))
                }
                continuation.yield(.done(sessionId: "preview-session"))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    })
}

extension DependencyValues {
    var chatRepository: ChatRepository {
        get { self[ChatRepository.self] }
        set { self[ChatRepository.self] = newValue }
    }
}
