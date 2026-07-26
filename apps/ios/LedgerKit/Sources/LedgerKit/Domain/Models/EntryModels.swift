import Foundation

/// One line the AI pulled out of the owner's description. Quantity and price are missing whenever
/// the description did not say — the owner fills those in on the draft.
public struct EntryDraftItem: Codable, Equatable, Sendable {
    public var description: String
    public var category: Category
    public var quantity: Int?
    public var unitPrice: Double?

    public init(description: String, category: Category, quantity: Int? = nil, unitPrice: Double? = nil) {
        self.description = description
        self.category = category
        self.quantity = quantity
        self.unitPrice = unitPrice
    }
}

/// What `POST /scan/entry` reads out of a typed description. Reading is not saving — the owner
/// corrects the draft, and confirming it is a separate `POST /purchases`.
public struct EntryDraft: Codable, Equatable, Sendable {
    /// Already resolved against today by the server, so "dia 24 de julho" arrives as a real date.
    public var date: String
    public var time: String?
    /// Where the money went, when the description named it.
    public var store: String?
    public var paymentMethod: String?
    public var items: [EntryDraftItem]
    public var comment: String

    public init(
        date: String,
        time: String? = nil,
        store: String? = nil,
        paymentMethod: String? = nil,
        items: [EntryDraftItem],
        comment: String = ""
    ) {
        self.date = date
        self.time = time
        self.store = store
        self.paymentMethod = paymentMethod
        self.items = items
        self.comment = comment
    }
}

public struct PurchaseCreateItem: Codable, Equatable, Sendable {
    public var description: String
    public var category: Category
    public var quantity: Int
    public var unitPrice: Double
}

/// What `POST /purchases` persists once the owner has confirmed the draft.
public struct PurchaseCreateRequest: Codable, Equatable, Sendable {
    public var date: String
    public var time: String?
    public var store: String
    public var paymentMethod: String?
    public var items: [PurchaseCreateItem]
}

public enum EntryScanFailure: Error, Equatable, Sendable {
    case invalidInput
    case notAnEntry
    case aiUnavailable
    case aiInvalidOutput
    case saveFailed

    var title: String {
        switch self {
        case .invalidInput: "Não deu pra ler isso"
        case .notAnEntry: "Isso não parece um gasto"
        case .aiUnavailable: "A IA não respondeu"
        case .aiInvalidOutput: "Resposta inesperada da IA"
        case .saveFailed: "Não deu pra salvar agora"
        }
    }

    var message: String {
        switch self {
        case .invalidInput:
            "Escreva o que você gastou — algo como \"37,00 de transporte no dia 24 de julho\"."
        case .notAnEntry:
            "A IA leu o que você escreveu, mas não encontrou nenhum gasto ali."
        case .aiUnavailable:
            "O servidor não conseguiu falar com a IA agora. Verifique sua conexão e o servidor em Ajustes."
        case .aiInvalidOutput:
            "A IA respondeu em um formato que não reconhecemos. Tente escrever de novo."
        case .saveFailed:
            "O rascunho foi montado, mas houve falha ao salvar. Verifique sua conexão e o servidor em Ajustes."
        }
    }

    var code: String {
        switch self {
        case .invalidInput: "erro · 400 · ENTRADA_INVÁLIDA"
        case .notAnEntry: "erro · 422 · NÃO_É_LANÇAMENTO"
        case .aiUnavailable: "erro · 424 · IA_INDISPONÍVEL"
        case .aiInvalidOutput: "erro · 424 · SAÍDA_INVÁLIDA"
        case .saveFailed: "erro · FALHA_AO_SALVAR"
        }
    }

    var symbol: String {
        switch self {
        case .invalidInput: "text.badge.xmark"
        case .notAnEntry: "questionmark.text.page"
        case .aiUnavailable, .aiInvalidOutput: "sparkles"
        case .saveFailed: "exclamationmark.icloud"
        }
    }

    var retryLabel: String {
        switch self {
        case .invalidInput, .notAnEntry: "Revisar a descrição"
        case .aiUnavailable, .aiInvalidOutput, .saveFailed: "Tentar novamente"
        }
    }
}
