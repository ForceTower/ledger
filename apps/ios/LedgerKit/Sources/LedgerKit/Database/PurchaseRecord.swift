import Foundation
import SwiftData

/// SwiftData mirror of the backend's purchase tables (`purchases`,
/// `purchase_items`, `payments`) flattened to the wire shape, so History and
/// its detail render fully offline. The backend's `slug` is the sync key:
/// re-saving a purchase replaces the records carrying the same slug.
@Model
final class PurchaseRecord {
    @Attribute(.unique) var slug: String
    var date: String
    var time: String
    var source: String
    var storeName: String
    var storeLegalName: String?
    var storeCnpj: String?
    var storeAddress: String?
    var receiptNumber: Int?
    var receiptSeries: Int?
    var receiptAccessKey: String?
    var itemCount: Int
    var gross: Double
    var discount: Double
    var totalPaid: Double
    var taxesTotal: Double?

    @Relationship(deleteRule: .cascade, inverse: \PurchaseItemRecord.purchase)
    var items: [PurchaseItemRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \PaymentRecord.purchase)
    var payments: [PaymentRecord] = []

    init(_ purchase: Purchase) {
        slug = purchase.id
        date = purchase.date
        time = purchase.time
        source = purchase.source.rawValue
        storeName = purchase.store.name
        storeLegalName = purchase.store.legalName
        storeCnpj = purchase.store.cnpj
        storeAddress = purchase.store.address
        receiptNumber = purchase.receipt?.number
        receiptSeries = purchase.receipt?.series
        receiptAccessKey = purchase.receipt?.accessKey
        itemCount = purchase.totals.itemCount
        gross = purchase.totals.gross
        discount = purchase.totals.discount
        totalPaid = purchase.totals.totalPaid
        taxesTotal = purchase.taxesTotal
    }
}

extension PurchaseRecord {
    /// Children are attached only after the root is in the context — SwiftData
    /// wants both ends of a relationship inserted.
    @discardableResult
    static func insert(_ purchase: Purchase, into context: ModelContext) -> PurchaseRecord {
        let record = PurchaseRecord(purchase)
        context.insert(record)
        record.items = purchase.items.map(PurchaseItemRecord.init)
        record.payments = purchase.payments.enumerated().map { PaymentRecord(seq: $0.offset, $0.element) }
        return record
    }

    var purchase: Purchase {
        Purchase(
            id: slug,
            date: date,
            time: time,
            source: Purchase.Source(rawValue: source) ?? .nfce,
            store: StoreInfo(name: storeName, legalName: storeLegalName, cnpj: storeCnpj, address: storeAddress),
            receipt: receiptAccessKey.map { Receipt(number: receiptNumber, series: receiptSeries, accessKey: $0) },
            items: items.sorted { $0.seq < $1.seq }.map(\.item),
            totals: Totals(itemCount: itemCount, gross: gross, discount: discount, totalPaid: totalPaid),
            payments: payments.sorted { $0.seq < $1.seq }.map(\.payment),
            taxesTotal: taxesTotal
        )
    }
}

@Model
final class PurchaseItemRecord {
    var purchase: PurchaseRecord?
    var seq: Int
    /// `description` is reserved by SwiftData's Core Data underpinnings.
    var itemDescription: String
    var code: String
    var barcode: String?
    var quantity: Double
    var unit: String
    var unitPrice: Double
    var total: Double
    /// Stored as the raw slug so records written by a newer server (with
    /// categories this build doesn't know) still load — they read as `.other`.
    var category: String

    init(_ item: PurchaseItem) {
        seq = item.seq
        itemDescription = item.description
        code = item.code
        barcode = item.barcode
        quantity = item.quantity
        unit = item.unit
        unitPrice = item.unitPrice
        total = item.total
        category = item.category.rawValue
    }

    var item: PurchaseItem {
        PurchaseItem(
            seq: seq,
            description: itemDescription,
            code: code,
            barcode: barcode,
            quantity: quantity,
            unit: unit,
            unitPrice: unitPrice,
            total: total,
            category: Category(rawValue: category) ?? .other
        )
    }
}

@Model
final class PaymentRecord {
    var purchase: PurchaseRecord?
    /// Position in the wire array — SwiftData to-many collections are unordered.
    var seq: Int
    var code: Int?
    var method: String
    var amount: Double
    var change: Double?

    init(seq: Int, _ payment: Payment) {
        self.seq = seq
        code = payment.code
        method = payment.method
        amount = payment.amount
        change = payment.change
    }

    var payment: Payment {
        Payment(code: code, method: method, amount: amount, change: change)
    }
}
