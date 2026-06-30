import Foundation

/// Anonymized sample data driving the mock client and SwiftUI previews — the
/// same shapes the real API returns, so the whole app runs before the backend
/// is live. No real purchase data ever lives here.
enum MockData {
    static let atacadao = Purchase(
        id: "2026-03-26_atacadao_01",
        date: "2026-03-26",
        time: "14:44:08",
        source: .nfce,
        store: StoreInfo(
            name: "Atacadão",
            legalName: "WMS Supermercados S.A.",
            cnpj: "75.315.333/0001-09",
            address: "Av. das Nações Unidas, 1200 — Setor Norte Ferroviário, Goiânia/GO"
        ),
        receipt: Receipt(number: 84213, series: 1, accessKey: "52260375315333000109650010000842131998472610"),
        items: [
            PurchaseItem(seq: 1, description: "Bov. Acém s/ Osso", code: "7891", barcode: nil, quantity: 1.252, unit: "kg", unitPrice: 34.90, total: 43.69, category: .meat),
            PurchaseItem(seq: 2, description: "Bacon Fatiado Seara", code: "7894", barcode: "7894900011517", quantity: 1, unit: "un", unitPrice: 23.90, total: 23.90, category: .meat),
            PurchaseItem(seq: 3, description: "Linguiça Toscana Seara", code: "7891", barcode: "7894904271993", quantity: 1, unit: "un", unitPrice: 18.90, total: 18.90, category: .meat),
            PurchaseItem(seq: 4, description: "Coxa de Frango Congelada", code: "7890", barcode: nil, quantity: 1.8, unit: "kg", unitPrice: 9.90, total: 17.82, category: .meat),
            PurchaseItem(seq: 5, description: "Arroz Tio João 5kg", code: "7896", barcode: "7896006711018", quantity: 1, unit: "un", unitPrice: 27.90, total: 27.90, category: .grocery),
            PurchaseItem(seq: 6, description: "Feijão Carioca 1kg", code: "7896", barcode: "7896005800010", quantity: 2, unit: "un", unitPrice: 8.49, total: 16.98, category: .grocery),
            PurchaseItem(seq: 7, description: "Açúcar União 1kg", code: "7891", barcode: "7891910000197", quantity: 2, unit: "un", unitPrice: 4.49, total: 8.98, category: .grocery),
            PurchaseItem(seq: 8, description: "Café Pilão 500g", code: "7896", barcode: "7896089012019", quantity: 1, unit: "un", unitPrice: 19.90, total: 19.90, category: .grocery),
            PurchaseItem(seq: 9, description: "Macarrão Renata 500g", code: "7896", barcode: "7896022200107", quantity: 3, unit: "un", unitPrice: 3.99, total: 11.97, category: .grocery),
            PurchaseItem(seq: 10, description: "Óleo de Soja Liza 900ml", code: "7891", barcode: "7891107101621", quantity: 2, unit: "un", unitPrice: 7.49, total: 14.98, category: .grocery),
        ],
        totals: Totals(itemCount: 10, gross: 211.75, discount: 3.00, totalPaid: 208.75),
        payments: [Payment(code: 3, method: "Vale Alimentação", amount: 208.75, change: nil)],
        taxesTotal: 31.20
    )

    static let summaries: [PurchaseSummary] = [
        PurchaseSummary(
            id: atacadao.id, store: "Atacadão", date: "2026-03-26", time: "14:44:08",
            totalPaid: 208.75, itemCount: 10, categories: [.grocery: 6, .meat: 4]
        ),
        PurchaseSummary(
            id: "2026-03-22_assai_01", store: "Assaí Atacadista", date: "2026-03-22", time: "10:12:33",
            totalPaid: 156.40, itemCount: 8, categories: [.grocery: 4, .cleaning: 2, .beverages: 2]
        ),
        PurchaseSummary(
            id: "2026-03-18_pao-de-acucar_01", store: "Pão de Açúcar", date: "2026-03-18", time: "19:05:41",
            totalPaid: 92.15, itemCount: 5, categories: [.produce: 2, .dairyDeli: 2, .bakery: 1]
        ),
        PurchaseSummary(
            id: "2026-02-27_carrefour_01", store: "Carrefour", date: "2026-02-27", time: "16:38:09",
            totalPaid: 312.80, itemCount: 14, categories: [.grocery: 7, .meat: 4, .hygiene: 3]
        ),
    ]

    static func purchase(id: String) -> Purchase {
        guard id != atacadao.id else { return atacadao }
        guard let summary = summaries.first(where: { $0.id == id }) else { return atacadao }
        // Reuse the Atacadão item set but re-skin the header from the summary, so
        // every history row opens to a believable detail in the mock.
        var purchase = atacadao
        purchase.id = summary.id
        purchase.date = summary.date
        purchase.time = summary.time
        purchase.store = StoreInfo(name: summary.store, legalName: nil, cnpj: nil, address: nil)
        purchase.totals = Totals(
            itemCount: summary.itemCount,
            gross: summary.totalPaid + 3,
            discount: 3,
            totalPaid: summary.totalPaid
        )
        return purchase
    }
}
