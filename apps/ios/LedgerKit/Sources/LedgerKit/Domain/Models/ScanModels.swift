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

/// AI product identification from a photo. UI-only stub for now — see
/// "Future (stub in UI only)" in docs/api-contract.md.
public struct ProductGuess: Equatable, Sendable {
    public struct Alternative: Equatable, Sendable, Identifiable {
        public var name: String
        public var unitPrice: Double

        public var id: String { name }
    }

    public var name: String
    public var detail: String
    public var category: Category
    public var unitPrice: Double
    public var confidencePercent: Int
    public var alternatives: [Alternative]
}

public struct ConnectionInfo: Equatable, Sendable {
    public var serverVersion: String
    public var purchaseCount: Int
}
