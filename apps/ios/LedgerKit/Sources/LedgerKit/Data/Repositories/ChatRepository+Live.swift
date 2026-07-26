import ComposableArchitecture
import Foundation

/// The server allows a chat turn up to CLAUDE_CHAT_TIMEOUT_MS (180s by default); the client waits a
/// little longer. The request-level timeout resets on every streamed byte, and the server's SSE
/// deltas arrive continuously, so this only trips when the connection genuinely stalls.
private let turnTimeout: TimeInterval = 200

private struct ChatRequestBody: Encodable {
    let message: String
    let sessionId: String?
}

/// The SSE `data:` payload. Every event carries `type`; which other fields are set depends on it.
private struct ChatWireEvent: Decodable {
    let type: String
    let sessionId: String?
    let text: String?
    let sql: String?
    let message: String?
}

extension ChatRepository: DependencyKey {
    static let liveValue = ChatRepository(send: { message, sessionId in
        @Shared(.serverAddress) var serverAddress
        @Shared(.apiToken) var apiToken

        guard let url = APIClient.endpoint(address: serverAddress, path: "chat", query: []) else {
            throw ChatFailure.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = turnTimeout
        request.httpBody = try JSONEncoder().encode(ChatRequestBody(message: message, sessionId: sessionId))

        let (bytes, response) = try await URLSession.chat.bytes(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw ChatFailure.unavailable(message: nil)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // One frame per `data:` line — the JSON repeats the SSE event name as `type`,
                    // so the `event:` lines and blank separators need no bookkeeping.
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let json = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        guard let event = try? JSONDecoder().decode(ChatWireEvent.self, from: Data(json.utf8)) else {
                            continue
                        }
                        switch event.type {
                        case "session":
                            continuation.yield(.session(id: event.sessionId ?? ""))
                        case "text":
                            continuation.yield(.text(event.text ?? ""))
                        case "tool":
                            continuation.yield(.tool(sql: event.sql ?? ""))
                        case "done":
                            continuation.yield(.done(sessionId: event.sessionId ?? ""))
                        case "error":
                            throw ChatFailure.unavailable(message: event.message)
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    })
}

private extension URLSession {
    /// A chat turn outlives the 10s the shared `.api` session allows, so SSE gets its own session.
    static let chat: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = turnTimeout
        return URLSession(configuration: config)
    }()
}
