import Foundation

/// One side of a transfer — who sent it or who received it.
public struct TransferParty: Codable, Equatable, Sendable {
    public var name: String
    public var institution: String?
    public var agency: String?
    public var account: String?

    public init(name: String, institution: String? = nil, agency: String? = nil, account: String? = nil) {
        self.name = name
        self.institution = institution
        self.agency = agency
        self.account = account
    }
}

/// A bank-transfer receipt the AI read out of a screenshot. Mirrors `Transfer` from the contract.
public struct Transfer: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case pix

        var label: String {
            switch self {
            case .pix: "Pix enviado"
            }
        }

        var shortLabel: String {
            switch self {
            case .pix: "Pix"
            }
        }
    }

    /// The bank's end-to-end ID. Dedup key, the way the access key is for a nota.
    public var transactionId: String
    public var type: Kind
    public var amount: Double
    public var date: String
    public var time: String?
    public var destination: TransferParty
    public var origin: TransferParty?
    /// Slug of the purchase this transfer materialized into; nil until it is saved.
    public var purchaseId: String?

    public init(
        transactionId: String,
        type: Kind = .pix,
        amount: Double,
        date: String,
        time: String? = nil,
        destination: TransferParty,
        origin: TransferParty? = nil,
        purchaseId: String? = nil
    ) {
        self.transactionId = transactionId
        self.type = type
        self.amount = amount
        self.date = date
        self.time = time
        self.destination = destination
        self.origin = origin
        self.purchaseId = purchaseId
    }
}

/// A purchase the transfer probably paid for: same day, same total.
public struct TransferMatch: Codable, Equatable, Sendable {
    public var purchaseId: String
    public var store: String
    public var date: String
    public var time: String
    public var totalPaid: Double
    public var itemCount: Int
}

/// What `POST /scan/transfer` reads out of a receipt. Reading is not saving — nothing is persisted yet.
public struct TransferScanResult: Codable, Equatable, Sendable {
    public var transfer: Transfer
    /// The AI's category guess for the transfer as a whole, from the destination's name.
    public var category: Category
    /// A purchase on the same day whose total matches — the transfer probably paid for it.
    public var match: TransferMatch?
    public var comment: String

    public init(transfer: Transfer, category: Category, match: TransferMatch? = nil, comment: String = "") {
        self.transfer = transfer
        self.category = category
        self.match = match
        self.comment = comment
    }
}

/// What `POST /transfers` persists, once the owner has confirmed the category and the match.
public struct TransferSaveRequest: Codable, Equatable, Sendable {
    public var transfer: Transfer
    public var category: Category
    /// The purchase this transfer paid for; keeps the two from being counted twice.
    public var linkedPurchaseId: String?
}

public struct TransferSaveResult: Codable, Equatable, Sendable {
    public var transfer: Transfer
    /// The purchase the transfer materialized into, ready to mirror into the local store.
    public var purchase: Purchase
}

public enum TransferScanFailure: Error, Equatable, Sendable {
    case invalidInput
    case notATransfer
    case aiUnavailable
    case aiInvalidOutput
    case saveFailed

    var title: String {
        switch self {
        case .invalidInput: "Não deu pra usar esse comprovante"
        case .notATransfer: "Isso não parece um comprovante"
        case .aiUnavailable: "A IA não respondeu"
        case .aiInvalidOutput: "Resposta inesperada da IA"
        case .saveFailed: "Não deu pra salvar agora"
        }
    }

    var message: String {
        switch self {
        case .invalidInput:
            "Anexe o print da transferência (até 10 MB) ou cole o texto do comprovante."
        case .notATransfer:
            "A IA leu o que você mandou, mas não encontrou valor, destinatário nem data de uma transferência."
        case .aiUnavailable:
            "O servidor não conseguiu falar com a IA agora. Verifique sua conexão e o servidor em Ajustes."
        case .aiInvalidOutput:
            "A IA respondeu em um formato que não reconhecemos. Tente mandar o print de novo."
        case .saveFailed:
            "A transferência foi lida, mas houve falha ao salvar. Verifique sua conexão e o servidor em Ajustes."
        }
    }

    var code: String {
        switch self {
        case .invalidInput: "erro · 400 · ENTRADA_INVÁLIDA"
        case .notATransfer: "erro · 422 · NÃO_É_COMPROVANTE"
        case .aiUnavailable: "erro · 424 · IA_INDISPONÍVEL"
        case .aiInvalidOutput: "erro · 424 · SAÍDA_INVÁLIDA"
        case .saveFailed: "erro · FALHA_AO_SALVAR"
        }
    }

    var symbol: String {
        switch self {
        case .invalidInput: "doc.badge.ellipsis"
        case .notATransfer: "questionmark.text.page"
        case .aiUnavailable, .aiInvalidOutput: "sparkles"
        case .saveFailed: "exclamationmark.icloud"
        }
    }

    var retryLabel: String {
        switch self {
        case .invalidInput, .notATransfer: "Revisar o comprovante"
        case .aiUnavailable, .aiInvalidOutput, .saveFailed: "Tentar novamente"
        }
    }
}
