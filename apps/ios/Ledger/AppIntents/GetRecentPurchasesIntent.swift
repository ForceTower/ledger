import AppIntents
import LedgerKit

struct GetRecentPurchasesIntent: AppIntent {
    static let title: LocalizedStringResource = "Últimas compras"
    static let description = IntentDescription(
        "Lista as compras mais recentes registradas na Caderneta — em quais lojas e por quanto.",
        categoryName: "Histórico"
    )

    func perform() async throws -> some IntentResult & ReturnsValue<[PurchaseEntity]> & ProvidesDialog {
        let recent = try await PurchaseMirror.summaries().prefix(5)
        guard !recent.isEmpty else {
            return .result(value: [], dialog: "Nenhuma nota registrada ainda. Escaneie o QR code de uma compra para começar.")
        }
        let spoken = recent
            .map { "\($0.store), \(Format.brl($0.totalPaid)) em \(Format.dayMonth(fromISO: $0.date))" }
            .joined(separator: "; ")
        let dialog: IntentDialog = recent.count == 1
            ? "Sua última compra foi: \(spoken)."
            : "Suas últimas \(recent.count) compras foram: \(spoken)."
        return .result(value: recent.map(PurchaseEntity.init), dialog: dialog)
    }
}
