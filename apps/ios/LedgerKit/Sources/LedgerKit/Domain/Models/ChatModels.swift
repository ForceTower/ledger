import ComposableArchitecture
import Foundation

/// One bubble in the conversation. The transcript is display state owned by the app; the server
/// keeps its own conversation memory, keyed by the session id it hands back on the first turn.
struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var text: String
    var date: Date
}

/// What one `POST /chat` turn streams back, mirroring `ChatStreamEvent` in the wire contract.
/// The server's `error` event is surfaced as a thrown `ChatFailure`, not a case here.
enum ChatStreamEvent: Equatable, Sendable {
    case session(id: String)
    case text(String)
    case tool(sql: String)
    case done(sessionId: String)
}

enum ChatFailure: Error, Equatable {
    /// No server address configured, or it does not parse into a URL.
    case notConfigured
    /// Transport or server failure; `message` is the server's presentable pt-BR text when it sent one.
    case unavailable(message: String?)
}

extension SharedKey where Self == FileStorageKey<[ChatMessage]>.Default {
    /// The rendered conversation, kept across launches. Clearing it (plus `chatSessionId`) starts over.
    static var chatTranscript: Self {
        Self[.fileStorage(.documentsDirectory.appending(component: "chat-transcript.json")), default: []]
    }
}
