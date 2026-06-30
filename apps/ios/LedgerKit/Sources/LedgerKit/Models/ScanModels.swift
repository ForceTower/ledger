import Foundation

/// Outcome of `POST /scan` — saved or duplicate, both carrying the purchase and
/// any non-fatal validation warnings.
public struct ScanResponse: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case saved, duplicate }

    public var status: Status
    public var purchase: Purchase
    public var warnings: [String]
}

/// Genuine `/scan` failures (the `errorCode` table in the API contract), with
/// the Brazilian-Portuguese copy the result sheet renders.
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

/// Result of a Settings "Testar conexão" probe (`GET /health`).
public struct ConnectionInfo: Equatable, Sendable {
    public var serverVersion: String
    public var purchaseCount: Int
}
