import ComposableArchitecture
import Foundation

extension PurchasesRepository: DependencyKey {
    static let liveValue = PurchasesRepository(
        summaries: {
            @Dependency(\.database) var database
            return try await MirrorStore(writer: database).summaries()
        },
        search: { query in
            @Dependency(\.database) var database
            return try await MirrorStore(writer: database).search(query)
        },
        purchase: { id in
            @Dependency(\.database) var database
            @Dependency(\.apiClient) var apiClient
            let mirror = MirrorStore(writer: database)
            if let local = try await mirror.purchase(id: id) { return local }
            let fetched: Purchase = try await apiClient.get(from: "purchases/\(id)")
            try await mirror.save([fetched])
            return fetched
        },
        refresh: {
            @Dependency(\.database) var database
            @Dependency(\.apiClient) var apiClient
            let mirror = MirrorStore(writer: database)
            var page = 1
            while true {
                let feed: PurchasePage = try await apiClient.get(
                    from: "purchases",
                    query: [URLQueryItem(name: "page", value: "\(page)")]
                )
                try await mirror.save(feed.items)
                guard feed.hasMore else { break }
                page += 1
            }
        }
    )
}
