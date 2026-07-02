import ComposableArchitecture
import Foundation

/// The seam between features and the backend (`docs/api-contract.md`). Features
/// depend on this; the default value is a mock that drives the whole app before
/// the server is live. The real URLSession client plugs in at `liveValue`,
/// reading the server URL + bearer token configured in Settings.
struct APIClient: Sendable {
    var scan: @Sendable (_ url: String) async throws -> ScanResponse
    var loadPurchases: @Sendable (_ page: Int) async throws -> PurchasePage
    var loadPurchase: @Sendable (_ id: String) async throws -> Purchase
    var testConnection: @Sendable () async throws -> ConnectionInfo
}

extension APIClient: DependencyKey {
    // TODO: a live URLSession client implementing the contract goes here; the app
    // ships against the mock until the backend is reachable.
    static let liveValue = APIClient.mock
    static let previewValue = APIClient.mock
    static let testValue = APIClient.mock
}

extension DependencyValues {
    var apiClient: APIClient {
        get { self[APIClient.self] }
        set { self[APIClient.self] = newValue }
    }
}

extension APIClient {
    /// Cycles scan outcomes (saved → duplicate → warning → error) and toggles
    /// connection success/failure on each call, mirroring the prototype so every
    /// result screen is reachable. Timing is owned by the reducers (via the
    /// clock), so these closures return immediately.
    static var mock: APIClient {
        let state = MockState()
        return APIClient(
            scan: { _ in try await state.nextScan() },
            loadPurchases: { page in
                PurchasePage(
                    items: page == 1 ? MockData.purchases : [],
                    page: page,
                    pageSize: 5,
                    total: MockData.purchases.count,
                    hasMore: false
                )
            },
            loadPurchase: { MockData.purchase(id: $0) },
            testConnection: { try await state.nextConnection() }
        )
    }
}

private struct ConnectionFailure: Error {}

private actor MockState {
    private var scanCount = 0
    private var connectionCount = 0

    func nextScan() throws -> ScanResponse {
        defer { scanCount += 1 }
        switch scanCount % 4 {
        case 0:
            return ScanResponse(status: .saved, purchase: MockData.atacadao, warnings: [])
        case 1:
            return ScanResponse(status: .duplicate, purchase: MockData.atacadao, warnings: [])
        case 2:
            return ScanResponse(
                status: .saved,
                purchase: MockData.atacadao,
                warnings: ["A soma dos itens não bate com o total"]
            )
        default:
            let kinds: [ScanFailure] = [.expired, .invalidQR, .unavailable]
            throw kinds[(scanCount / 4) % kinds.count]
        }
    }

    func nextConnection() throws -> ConnectionInfo {
        defer { connectionCount += 1 }
        guard connectionCount.isMultiple(of: 2) else { throw ConnectionFailure() }
        return ConnectionInfo(serverVersion: "v2.4", purchaseCount: 23)
    }
}
