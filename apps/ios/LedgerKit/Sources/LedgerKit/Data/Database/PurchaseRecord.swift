import GRDB

struct PurchaseRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "purchases"
    var slug: String
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
}

extension PurchaseRecord {
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

    func purchase(items: [PurchaseItem], payments: [Payment]) -> Purchase {
        Purchase(
            id: slug,
            date: date,
            time: time,
            source: Purchase.Source(rawValue: source) ?? .nfce,
            store: StoreInfo(name: storeName, legalName: storeLegalName, cnpj: storeCnpj, address: storeAddress),
            receipt: receiptAccessKey.map { Receipt(number: receiptNumber, series: receiptSeries, accessKey: $0) },
            items: items,
            totals: Totals(itemCount: itemCount, gross: gross, discount: discount, totalPaid: totalPaid),
            payments: payments,
            taxesTotal: taxesTotal
        )
    }
}

struct PurchaseItemRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "purchaseItems"
    var purchaseSlug: String
    var seq: Int
    var itemDescription: String
    var code: String
    var barcode: String?
    var quantity: Double
    var unit: String
    var unitPrice: Double
    var total: Double
    var category: String
}

extension PurchaseItemRecord {
    init(purchaseSlug: String, _ item: PurchaseItem) {
        self.purchaseSlug = purchaseSlug
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

struct PaymentRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "payments"
    var purchaseSlug: String
    var seq: Int
    var code: Int?
    var method: String
    var amount: Double
    var change: Double?
}

extension PaymentRecord {
    init(purchaseSlug: String, seq: Int, _ payment: Payment) {
        self.purchaseSlug = purchaseSlug
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
