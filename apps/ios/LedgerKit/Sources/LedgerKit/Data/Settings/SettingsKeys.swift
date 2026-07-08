import ComposableArchitecture
import Foundation
import Security

extension SharedKey where Self == AppStorageKey<String>.Default {
    static var serverAddress: Self {
        Self[.appStorage("serverAddress"), default: "nfce.meucasa.app"]
    }
}

extension SharedKey where Self == KeychainKey.Default {
    static var apiToken: Self {
        Self[.keychain("apiToken"), default: ""]
    }
}

extension SharedReaderKey where Self == KeychainKey {
    static func keychain(_ key: String) -> KeychainKey {
        KeychainKey(key: key)
    }
}

struct KeychainKey: SharedKey, Hashable {
    private static let service = "dev.forcetower.ledger"
    private static let memory = LockIsolated<[String: String]>([:])

    let key: String
    private let isLive: Bool

    init(key: String) {
        self.key = key
        @Dependency(\.context) var context
        self.isLive = context == .live
    }

    func load(context: LoadContext<String>, continuation: LoadContinuation<String>) {
        let stored = isLive ? read() : Self.memory.withValue { $0[key] }
        if let stored {
            continuation.resume(returning: stored)
        } else {
            continuation.resumeReturningInitialValue()
        }
    }

    func subscribe(context: LoadContext<String>, subscriber: SharedSubscriber<String>) -> SharedSubscription {
        SharedSubscription {}
    }

    func save(_ value: String, context: SaveContext, continuation: SaveContinuation) {
        if isLive {
            value.isEmpty ? delete() : write(value)
        } else {
            Self.memory.withValue { $0[key] = value }
        }
        continuation.resume()
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key,
        ]
    }

    private func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ value: String) {
        let data = Data(value.utf8)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    private func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
