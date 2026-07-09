import Foundation

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
            PurchaseItem(seq: 4, description: "Coxa de Frango Congelada", code: "7890", barcode: nil, quantity: 2.48, unit: "kg", unitPrice: 9.90, total: 24.55, category: .meat),
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

    static let assai = Purchase(
        id: "2026-03-22_assai_01",
        date: "2026-03-22",
        time: "10:12:33",
        source: .nfce,
        store: StoreInfo(
            name: "Assaí Atacadista",
            legalName: "Sendas Distribuidora S.A.",
            cnpj: "06.057.223/0001-71",
            address: "Av. Perimetral Norte, 2500 — Goiânia/GO"
        ),
        receipt: Receipt(number: 51877, series: 2, accessKey: "52260306057223000171650020000518771230984415"),
        items: [
            PurchaseItem(seq: 1, description: "Refrigerante Coca-Cola 2L", code: "7894", barcode: "7894900011609", quantity: 2, unit: "un", unitPrice: 8.99, total: 17.98, category: .beverages),
            PurchaseItem(seq: 2, description: "Cerveja Heineken 350ml c/12", code: "7896", barcode: "7896045506873", quantity: 1, unit: "un", unitPrice: 54.90, total: 54.90, category: .beverages),
            PurchaseItem(seq: 3, description: "Detergente Ypê Neutro 500ml", code: "7896", barcode: "7896098900017", quantity: 3, unit: "un", unitPrice: 2.79, total: 8.37, category: .cleaning),
            PurchaseItem(seq: 4, description: "Sabão em Pó Omo 1,6kg", code: "7891", barcode: "7891150063869", quantity: 1, unit: "un", unitPrice: 21.90, total: 21.90, category: .cleaning),
            PurchaseItem(seq: 5, description: "Arroz Camil 5kg", code: "7896", barcode: "7896006751014", quantity: 1, unit: "un", unitPrice: 24.90, total: 24.90, category: .grocery),
            PurchaseItem(seq: 6, description: "Farinha de Trigo Dona Benta 1kg", code: "7896", barcode: "7896023000126", quantity: 2, unit: "un", unitPrice: 5.49, total: 10.98, category: .grocery),
            PurchaseItem(seq: 7, description: "Molho de Tomate Heinz 300g", code: "7896", barcode: "7896102513714", quantity: 3, unit: "un", unitPrice: 3.99, total: 11.97, category: .grocery),
            PurchaseItem(seq: 8, description: "Achocolatado Nescau 550g", code: "7891", barcode: "7891000053508", quantity: 1, unit: "un", unitPrice: 8.40, total: 8.40, category: .grocery),
        ],
        totals: Totals(itemCount: 8, gross: 159.40, discount: 3.00, totalPaid: 156.40),
        payments: [Payment(code: 4, method: "Débito", amount: 156.40, change: nil)],
        taxesTotal: 24.15
    )

    static let paoDeAcucar = Purchase(
        id: "2026-03-18_pao-de-acucar_01",
        date: "2026-03-18",
        time: "19:05:41",
        source: .nfce,
        store: StoreInfo(
            name: "Pão de Açúcar",
            legalName: "Companhia Brasileira de Distribuição",
            cnpj: "47.508.411/0001-56",
            address: "Av. T-9, 1855 — Jardim América, Goiânia/GO"
        ),
        receipt: Receipt(number: 30542, series: 1, accessKey: "52260347508411000156650010000305421770261083"),
        items: [
            PurchaseItem(seq: 1, description: "Banana Prata", code: "2001", barcode: nil, quantity: 1.242, unit: "kg", unitPrice: 5.99, total: 7.44, category: .produce),
            PurchaseItem(seq: 2, description: "Tomate Italiano", code: "2014", barcode: nil, quantity: 0.855, unit: "kg", unitPrice: 8.99, total: 7.69, category: .produce),
            PurchaseItem(seq: 3, description: "Queijo Mussarela Fatiado", code: "2450", barcode: nil, quantity: 0.480, unit: "kg", unitPrice: 54.90, total: 26.35, category: .dairyDeli),
            PurchaseItem(seq: 4, description: "Leite Integral Italac 1L", code: "7898", barcode: "7898080640611", quantity: 6, unit: "un", unitPrice: 5.49, total: 32.94, category: .dairyDeli),
            PurchaseItem(seq: 5, description: "Pão Francês", code: "2300", barcode: nil, quantity: 1.158, unit: "kg", unitPrice: 17.90, total: 20.73, category: .bakery),
        ],
        totals: Totals(itemCount: 5, gross: 95.15, discount: 3.00, totalPaid: 92.15),
        payments: [Payment(code: 3, method: "Crédito", amount: 92.15, change: nil)],
        taxesTotal: 11.40
    )

    static let carrefour = Purchase(
        id: "2026-02-27_carrefour_01",
        date: "2026-02-27",
        time: "16:38:09",
        source: .nfce,
        store: StoreInfo(
            name: "Carrefour",
            legalName: "Carrefour Comércio e Indústria Ltda.",
            cnpj: "45.543.915/0001-81",
            address: "Av. Castelo Branco, 359 — Setor Coimbra, Goiânia/GO"
        ),
        receipt: Receipt(number: 77120, series: 3, accessKey: "52260245543915000181650030000771205502147736"),
        items: [
            PurchaseItem(seq: 1, description: "Picanha Bovina", code: "3105", barcode: nil, quantity: 1.152, unit: "kg", unitPrice: 69.90, total: 80.52, category: .meat),
            PurchaseItem(seq: 2, description: "Frango Inteiro Congelado", code: "3110", barcode: nil, quantity: 2.482, unit: "kg", unitPrice: 8.99, total: 22.31, category: .meat),
            PurchaseItem(seq: 3, description: "Linguiça Calabresa Perdigão", code: "7891", barcode: "7891515901219", quantity: 1, unit: "un", unitPrice: 15.90, total: 15.90, category: .meat),
            PurchaseItem(seq: 4, description: "Carne Moída Patinho", code: "3122", barcode: nil, quantity: 0.854, unit: "kg", unitPrice: 32.90, total: 28.10, category: .meat),
            PurchaseItem(seq: 5, description: "Papel Higiênico Neve 12 rolos", code: "7891", barcode: "7891172422543", quantity: 1, unit: "un", unitPrice: 24.90, total: 24.90, category: .hygiene),
            PurchaseItem(seq: 6, description: "Creme Dental Colgate 90g", code: "7891", barcode: "7891024132609", quantity: 3, unit: "un", unitPrice: 4.99, total: 14.97, category: .hygiene),
            PurchaseItem(seq: 7, description: "Shampoo Seda 325ml", code: "7891", barcode: "7891150056442", quantity: 2, unit: "un", unitPrice: 9.90, total: 19.80, category: .hygiene),
            PurchaseItem(seq: 8, description: "Arroz Tio João 5kg", code: "7896", barcode: "7896006711018", quantity: 1, unit: "un", unitPrice: 27.90, total: 27.90, category: .grocery),
            PurchaseItem(seq: 9, description: "Feijão Preto Camil 1kg", code: "7896", barcode: "7896006744115", quantity: 2, unit: "un", unitPrice: 7.99, total: 15.98, category: .grocery),
            PurchaseItem(seq: 10, description: "Óleo de Soja Soya 900ml", code: "7891", barcode: "7891107101614", quantity: 3, unit: "un", unitPrice: 6.99, total: 20.97, category: .grocery),
            PurchaseItem(seq: 11, description: "Açúcar Cristal União 1kg", code: "7891", barcode: "7891910000121", quantity: 2, unit: "un", unitPrice: 4.29, total: 8.58, category: .grocery),
            PurchaseItem(seq: 12, description: "Café Melitta 500g", code: "7891", barcode: "7891021006125", quantity: 1, unit: "un", unitPrice: 16.90, total: 16.90, category: .grocery),
            PurchaseItem(seq: 13, description: "Macarrão Barilla 500g", code: "8076", barcode: "8076802085738", quantity: 2, unit: "un", unitPrice: 6.49, total: 12.98, category: .grocery),
            PurchaseItem(seq: 14, description: "Farofa Pronta Yoki 400g", code: "7891", barcode: "7891095005537", quantity: 1, unit: "un", unitPrice: 5.99, total: 5.99, category: .grocery),
        ],
        totals: Totals(itemCount: 14, gross: 315.80, discount: 3.00, totalPaid: 312.80),
        payments: [Payment(code: 3, method: "Crédito", amount: 312.80, change: nil)],
        taxesTotal: 47.35
    )

    static let productGuess = ProductGuess(
        name: "Mamão Formosa",
        detail: "Fruta fresca · por unidade",
        category: .produce,
        unitPrice: 8.90,
        confidencePercent: 96,
        alternatives: [
            ProductGuess.Alternative(name: "Mamão Papaya", unitPrice: 5.90),
            ProductGuess.Alternative(name: "Melão Amarelo", unitPrice: 9.90),
        ]
    )

    static let purchases = [atacadao, assai, paoDeAcucar, carrefour]

    static let summaries = purchases.map(\.summary)

    static func purchase(id: String) -> Purchase {
        purchases.first { $0.id == id } ?? atacadao
    }
}
