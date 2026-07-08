import AppIntents
import CoreSpotlight
import LedgerKit

struct PurchaseEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Compra")
    static let defaultQuery = PurchaseEntityQuery()

    let id: String

    @Property(title: "Loja")
    var store: String

    @Property(title: "Data")
    var date: Date?

    @Property(title: "Total pago")
    var totalPaid: Double

    @Property(title: "Itens")
    var itemCount: Int

    let subtitle: String

    init(summary: PurchaseSummary) {
        id = summary.id
        subtitle = "\(Format.dayMonthYear(summary.date)) · \(Format.brl(summary.totalPaid))"
        store = summary.store
        date = Format.date(fromISO: summary.date)
        totalPaid = summary.totalPaid
        itemCount = summary.itemCount
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(store)",
            subtitle: "\(subtitle)",
            image: .init(systemName: "receipt")
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.displayName = store
        attributes.contentDescription = subtitle
        attributes.completionDate = date
        return attributes
    }
}

struct PurchaseEntityQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PurchaseEntity] {
        try await PurchaseMirror.summaries()
            .filter { identifiers.contains($0.id) }
            .map(PurchaseEntity.init)
    }

    func entities(matching string: String) async throws -> [PurchaseEntity] {
        try await PurchaseMirror.summaries()
            .filter { $0.store.localizedCaseInsensitiveContains(string) }
            .map(PurchaseEntity.init)
    }

    func suggestedEntities() async throws -> [PurchaseEntity] {
        try await PurchaseMirror.summaries().prefix(6).map(PurchaseEntity.init)
    }
}
