import Foundation

public struct ScanResponse: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable { case saved, duplicate }

    public var status: Status
    public var purchase: Purchase
    public var warnings: [String]
}

public enum ScanFailure: Error, Equatable, Sendable {
    case invalidQR
    case expired
    case unavailable
    case parseFailed

    var title: String {
        switch self {
        case .invalidQR: "Esse QR não é de uma NFC-e"
        case .expired: "Não encontramos essa nota"
        case .unavailable, .parseFailed: "Não deu pra processar agora"
        }
    }

    var message: String {
        switch self {
        case .invalidQR:
            "Aponte para o QR code impresso na nota fiscal do supermercado — geralmente no rodapé do cupom."
        case .expired:
            "O link do QR pode ter expirado ou a nota ainda não foi liberada pela SEFAZ. Tente de novo em alguns minutos."
        case .unavailable, .parseFailed:
            "A nota foi lida, mas houve falha ao salvar. Verifique sua conexão e o servidor em Ajustes."
        }
    }

    var code: String {
        switch self {
        case .invalidQR: "erro · QR_INVÁLIDO"
        case .expired: "erro · LINK_EXPIRADO"
        case .unavailable, .parseFailed: "erro · 502 · timeout"
        }
    }

    var retryLabel: String {
        switch self {
        case .invalidQR: "Escanear de novo"
        case .expired, .unavailable, .parseFailed: "Tentar novamente"
        }
    }
}

/// One item the AI recognized in a photo. Mirrors `PhotoScanItem` from `POST /scan/photo`.
public struct PhotoScanItem: Codable, Equatable, Sendable {
    public var description: String
    public var category: Category
    /// Model self-assessment, 0..1.
    public var confidence: Double

    public var confidencePercent: Int { Int((confidence * 100).rounded()) }
}

public struct PhotoScanIdentified: Codable, Equatable, Sendable {
    /// One entry per distinct product, most prominent first. Never empty.
    public var items: [PhotoScanItem]
    public var comment: String
}

public enum PhotoScanRejectionReason: String, Codable, Equatable, Sendable {
    case noItem = "no_item"
    case unclearImage = "unclear_image"
    case inappropriate

    var title: String {
        switch self {
        case .noItem: "Nenhum item na foto"
        case .unclearImage: "Foto pouco nítida"
        case .inappropriate: "Isso não parece um item de compra"
        }
    }

    var symbol: String {
        switch self {
        case .noItem: "questionmark.circle"
        case .unclearImage: "eye.trianglebadge.exclamationmark"
        case .inappropriate: "hand.raised"
        }
    }
}

public struct PhotoScanRejected: Codable, Equatable, Sendable {
    public var reason: PhotoScanRejectionReason
    /// Why the AI could not identify anything, in pt-BR.
    public var comment: String
}

/// A rejection is a normal 200 result, not an error — the AI declining to guess.
public enum PhotoScanResult: Equatable, Sendable {
    case identified(PhotoScanIdentified)
    case rejected(PhotoScanRejected)
}

extension PhotoScanResult: Codable {
    private enum CodingKeys: String, CodingKey { case status }
    private enum Status: String, Codable { case identified, rejected }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Status.self, forKey: .status) {
        case .identified: self = .identified(try PhotoScanIdentified(from: decoder))
        case .rejected: self = .rejected(try PhotoScanRejected(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .identified(identified):
            try container.encode(Status.identified, forKey: .status)
            try identified.encode(to: encoder)
        case let .rejected(rejected):
            try container.encode(Status.rejected, forKey: .status)
            try rejected.encode(to: encoder)
        }
    }
}

public enum PhotoScanFailure: Error, Equatable, Sendable {
    case captureFailed
    case invalidImage
    case aiUnavailable
    case aiInvalidOutput

    var title: String {
        switch self {
        case .captureFailed: "Não deu pra usar essa foto"
        case .invalidImage: "Essa imagem não serve"
        case .aiUnavailable: "A IA não respondeu"
        case .aiInvalidOutput: "Resposta inesperada da IA"
        }
    }

    var message: String {
        switch self {
        case .captureFailed:
            "A câmera não conseguiu capturar a imagem. Tente novamente."
        case .invalidImage:
            "Use uma foto de até 10 MB. Tente tirar outra ou escolher uma imagem diferente na galeria."
        case .aiUnavailable:
            "O servidor não conseguiu falar com a IA agora. Verifique sua conexão e o servidor em Ajustes."
        case .aiInvalidOutput:
            "A IA respondeu em um formato que não reconhecemos. Tente tirar a foto de novo."
        }
    }

    var code: String {
        switch self {
        case .captureFailed: "erro · CAPTURA_FALHOU"
        case .invalidImage: "erro · 400 · IMAGEM_INVÁLIDA"
        case .aiUnavailable: "erro · 502 · IA_INDISPONÍVEL"
        case .aiInvalidOutput: "erro · 502 · SAÍDA_INVÁLIDA"
        }
    }

    var symbol: String {
        switch self {
        case .captureFailed, .invalidImage: "camera.badge.ellipsis"
        case .aiUnavailable, .aiInvalidOutput: "sparkles"
        }
    }
}

public struct ConnectionInfo: Equatable, Sendable {
    public var serverVersion: String
    public var purchaseCount: Int
}
