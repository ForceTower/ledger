import GRDB
import Testing

@testable import LedgerKit

struct MirrorStoreTests {
    @Test
    func summariesProjectionMatchesFullHydration() async throws {
        let database = try inMemoryDatabase()
        try await MirrorStore(writer: database).save(MockData.purchases)

        let summaries = try await MirrorStore(writer: database).summaries()

        #expect(summaries == MockData.summaries)
    }

    @Test
    func summariesOrderSameDayPurchasesByTimeDescending() async throws {
        let database = try inMemoryDatabase()
        var morning = MockData.atacadao
        morning.id = "2026-03-26_atacadao_morning"
        morning.time = "09:15:00"
        try await MirrorStore(writer: database).save([morning, MockData.atacadao])

        let summaries = try await MirrorStore(writer: database).summaries()

        #expect(summaries.map(\.id) == [MockData.atacadao.id, morning.id])
    }

    @Test
    func searchMatchesAccentedTextCaseInsensitively() async throws {
        let database = try inMemoryDatabase()
        try await MirrorStore(writer: database).save(MockData.purchases)

        // Matches the Pão de Açúcar store name plus açúcar items elsewhere,
        // despite the query's all-lowercase accents.
        let results = try await MirrorStore(writer: database).search("açúcar")

        #expect(results == [MockData.atacadao.summary, MockData.paoDeAcucar.summary, MockData.carrefour.summary])
    }

    @Test
    func searchMatchesItemDescriptions() async throws {
        let database = try inMemoryDatabase()
        try await MirrorStore(writer: database).save(MockData.purchases)

        let results = try await MirrorStore(writer: database).search("bacon")

        #expect(results == [MockData.atacadao.summary])
    }

    @Test
    func dateTimeIndexExists() async throws {
        let database = try inMemoryDatabase()

        let indexes = try await database.read { try $0.indexes(on: "purchases") }

        #expect(indexes.contains { $0.columns == ["date", "time"] })
    }
}
