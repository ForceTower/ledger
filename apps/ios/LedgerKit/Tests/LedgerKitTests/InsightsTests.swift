import ComposableArchitecture
import Foundation
import Testing

@testable import LedgerKit

/// A minimal single-item purchase for shaping specific aggregation scenarios.
private func purchase(
    id: String,
    date: String,
    store: String = "Atacadão",
    total: Double,
    source: Purchase.Source = .nfce,
    items: [PurchaseItem] = []
) -> Purchase {
    let items = items.isEmpty
        ? [
            PurchaseItem(
                seq: 1, description: "Item", code: "1", barcode: nil,
                quantity: 1, unit: "un", unitPrice: total, total: total, category: .grocery
            ),
        ]
        : items
    return Purchase(
        id: id,
        date: date,
        time: "12:00:00",
        source: source,
        store: StoreInfo(name: store, legalName: nil, cnpj: nil, address: nil),
        receipt: nil,
        items: items,
        totals: Totals(itemCount: items.count, gross: total, discount: 0, totalPaid: total),
        payments: [Payment(code: 1, method: "Débito", amount: total, change: nil)],
        taxesTotal: nil
    )
}

private func rice(seq: Int = 1, price: Double) -> PurchaseItem {
    PurchaseItem(
        seq: seq, description: "Arroz Tio João 5kg", code: "7896", barcode: "7896006711018",
        quantity: 1, unit: "un", unitPrice: price, total: price, category: .grocery
    )
}

struct InsightsSnapshotTests {
    private let now = Format.date(fromISO: "2026-07-26")!

    @Test
    func theReferenceMonthIsTheLatestWithData() throws {
        let snapshot = try #require(InsightsSnapshot(purchases: MockData.purchases, now: now))

        #expect(snapshot.monthKey == "2026-03")
        #expect(snapshot.monthName == "março")
        #expect(abs(snapshot.total - 457.30) < 0.001)
        #expect(snapshot.purchaseCount == 3)
        #expect(abs(snapshot.averagePerPurchase - 457.30 / 3) < 0.001)
        #expect(abs(snapshot.savings - 9.00) < 0.001)
    }

    @Test
    func noPurchasesMeansNoSnapshot() {
        #expect(InsightsSnapshot(purchases: [], now: now) == nil)
    }

    @Test
    func theDonutRanksFourCategoriesAndGroupsTheRest() throws {
        let snapshot = try #require(InsightsSnapshot(purchases: MockData.purchases, now: now))

        #expect(snapshot.slices.map(\.category) == [.grocery, .meat, .beverages, .dairyDeli, nil])
        #expect(snapshot.slices.map(\.percent) == [34, 24, 16, 13, 14])
        #expect(snapshot.slices.last?.label == "Outros")
        // The March window: cleaning 30.27 + produce 15.13 + bakery 20.73.
        #expect(abs((snapshot.slices.last?.amount ?? 0) - 66.13) < 0.001)
    }

    @Test
    func theWindowSpansSixMonthsEndingAtTheReference() throws {
        let snapshot = try #require(InsightsSnapshot(purchases: MockData.purchases, now: now))

        #expect(snapshot.months.map(\.key) == [
            "2025-10", "2025-11", "2025-12", "2026-01", "2026-02", "2026-03",
        ])
        #expect(snapshot.months.last?.isReference == true)
        #expect(abs((snapshot.months.last?.total ?? 0) - 457.30) < 0.001)
        #expect(abs(snapshot.months[4].total - 312.80) < 0.001)
        #expect(snapshot.months[0].total == 0)
    }

    @Test
    func theTrendComparesAgainstThePreviousMonth() throws {
        let snapshot = try #require(InsightsSnapshot(purchases: MockData.purchases, now: now))

        // (457.30 - 312.80) / 312.80 = 46.2%.
        #expect(snapshot.trendPercent == 46)
        #expect(snapshot.previousMonthLabel == "fev")
    }

    @Test
    func theHighlightPrefersTheBiggestRise() throws {
        let snapshot = try #require(InsightsSnapshot(purchases: MockData.purchases, now: now))
        let highlight = try #require(snapshot.highlight)

        // Grocery rose 109.30 → 156.96 (+44%); hygiene's larger fall loses to the rise.
        #expect(highlight.category == .grocery)
        #expect(highlight.percent == 44)
        #expect(abs(highlight.delta - 47.66) < 0.001)
        #expect(highlight.previousMonthName == "fevereiro")
        #expect(highlight.rose)
    }

    @Test
    func withoutAnyRiseTheHighlightShowsTheBiggestFall() throws {
        let purchases = [
            purchase(id: "1", date: "2026-02-10", total: 200, items: [
                PurchaseItem(
                    seq: 1, description: "Picanha", code: "1", barcode: nil,
                    quantity: 1, unit: "un", unitPrice: 200, total: 200, category: .meat
                ),
            ]),
            purchase(id: "2", date: "2026-03-10", total: 80, items: [
                PurchaseItem(
                    seq: 1, description: "Frango", code: "2", barcode: nil,
                    quantity: 1, unit: "un", unitPrice: 80, total: 80, category: .meat
                ),
            ]),
        ]
        let highlight = try #require(InsightsSnapshot(purchases: purchases, now: now)?.highlight)

        #expect(highlight.category == .meat)
        #expect(highlight.percent == -60)
        #expect(!highlight.rose)
    }

    @Test
    func theBiggestPurchaseAndDailyPaceComeFromTheReferenceMonth() throws {
        let snapshot = try #require(InsightsSnapshot(purchases: MockData.purchases, now: now))

        #expect(snapshot.biggest == InsightsSnapshot.BiggestPurchase(
            store: "Atacadão", date: "2026-03-26", amount: 208.75
        ))
        // March 2026 is over, so the pace divides by its 31 days.
        #expect(abs(snapshot.dailyPace - 457.30 / 31) < 0.001)
    }

    @Test
    func aRunningMonthPacesByTheDaysElapsed() throws {
        let snapshot = try #require(
            InsightsSnapshot(purchases: MockData.purchases, now: Format.date(fromISO: "2026-03-20")!)
        )

        #expect(abs(snapshot.dailyPace - 457.30 / 20) < 0.001)
    }

    @Test
    func storesRankByMonthSpendWithFractionsOfTheLeader() throws {
        let snapshot = try #require(InsightsSnapshot(purchases: MockData.purchases, now: now))

        #expect(snapshot.topStores.map(\.name) == ["Atacadão", "Assaí Atacadista", "Pão de Açúcar"])
        #expect(snapshot.topStores.first?.fraction == 1)
        #expect(abs((snapshot.topStores.last?.fraction ?? 0) - 92.15 / 208.75) < 0.001)
    }

    @Test
    func weekdaysRankTheReferenceMonthSpending() throws {
        let snapshot = try #require(InsightsSnapshot(purchases: MockData.purchases, now: now))

        // 26 mar 2026 was a Thursday, 22 mar a Sunday, 18 mar a Wednesday.
        #expect(snapshot.weekdays.count == 7)
        #expect(snapshot.weekdays[4].rank == 0)
        #expect(abs(snapshot.weekdays[4].total - 208.75) < 0.001)
        #expect(snapshot.weekdays[1].total == 0)
        #expect(snapshot.topWeekdayName == "Qui")
    }

    @Test
    func theRadarTracksTheProductWithTheLongestPriceHistory() throws {
        let purchases = [
            purchase(id: "1", date: "2026-01-10", total: 25.90, items: [rice(price: 25.90)]),
            purchase(id: "2", date: "2026-02-14", total: 26.90, items: [rice(price: 26.90)]),
            purchase(id: "3", date: "2026-03-21", total: 27.90, items: [rice(price: 27.90)]),
        ]
        let radar = try #require(InsightsSnapshot(purchases: purchases, now: now)?.priceRadar)

        #expect(radar.productName == "Arroz Tio João 5kg")
        #expect(abs(radar.currentPrice - 27.90) < 0.001)
        // (27.90 - 25.90) / 25.90 = 7.7%.
        #expect(radar.changePercent == 8)
        #expect(radar.sinceLabel == "jan")
        #expect(radar.points.map(\.monthKey) == ["2026-01", "2026-02", "2026-03"])
    }

    @Test
    func productsSeenInFewerThanThreeMonthsHaveNoRadar() throws {
        // Arroz Tio João shows up in only two months of the mock data.
        let snapshot = try #require(InsightsSnapshot(purchases: MockData.purchases, now: now))
        #expect(snapshot.priceRadar == nil)
    }

    @Test
    func pixTransfersNeverBecomeARadarProduct() {
        let purchases = (1...4).map { month in
            purchase(
                id: "\(month)",
                date: String(format: "2026-%02d-10", month),
                total: 120,
                source: .pix
            )
        }
        #expect(InsightsSnapshot(purchases: purchases, now: now)?.priceRadar == nil)
    }
}

struct MirrorStoreWindowTests {
    @Test
    func monthStartWalksBackAcrossYears() {
        #expect(MirrorStore.monthStart(monthsBefore: 5, of: "2026-03-26") == "2025-10-01")
        #expect(MirrorStore.monthStart(monthsBefore: 0, of: "2026-01-15") == "2026-01-01")
        #expect(MirrorStore.monthStart(monthsBefore: 12, of: "2026-02-01") == "2025-02-01")
    }

    @Test
    func recentPurchasesKeepTheWindowAndDropTheRest() async throws {
        let database = try inMemoryDatabase()
        let old = purchase(id: "old", date: "2025-08-30", total: 50)
        try await MirrorStore(writer: database).save(MockData.purchases + [old])

        let recent = try await MirrorStore(writer: database).recentPurchases(monthCount: 6)

        #expect(recent.map(\.id).sorted() == MockData.purchases.map(\.id).sorted())
        // The window read hydrates full purchases, items included.
        #expect(recent.first { $0.id == MockData.atacadao.id } == MockData.atacadao)
    }

    @Test
    func anEmptyMirrorYieldsAnEmptyWindow() async throws {
        let database = try inMemoryDatabase()
        let recent = try await MirrorStore(writer: database).recentPurchases(monthCount: 6)
        #expect(recent.isEmpty)
    }
}

@MainActor
struct InsightsFeatureTests {
    @Test
    func insightsComeFromTheMirrorWithoutTouchingTheAPI() async throws {
        let database = try inMemoryDatabase()
        try await MirrorStore(writer: database).save(MockData.purchases)
        let now = Format.date(fromISO: "2026-07-26")!
        let store = TestStore(initialState: InsightsFeature.State()) {
            InsightsFeature()
        } withDependencies: {
            $0.purchasesRepository = .liveValue
            $0.database = database
            $0.date = .constant(now)
        }

        await store.send(.onAppear)
        await store.receive(\.snapshotLoaded) {
            $0.snapshot = InsightsSnapshot(purchases: MockData.purchases, now: now)
            $0.didLoad = true
        }
        #expect(store.state.snapshot?.monthKey == "2026-03")
    }

    @Test
    func anEmptyMirrorShowsTheEmptyState() async throws {
        let database = try inMemoryDatabase()
        let store = TestStore(initialState: InsightsFeature.State()) {
            InsightsFeature()
        } withDependencies: {
            $0.purchasesRepository = .liveValue
            $0.database = database
            $0.date = .constant(Format.date(fromISO: "2026-07-26")!)
        }

        await store.send(.onAppear)
        await store.receive(\.snapshotLoaded) { $0.didLoad = true }
        #expect(store.state.isEmpty)
    }

    @Test
    func scanFirstBubblesUpAsADelegate() async {
        let store = TestStore(initialState: InsightsFeature.State()) { InsightsFeature() }

        await store.send(.scanFirstTapped)
        await store.receive(\.delegate)
    }
}
