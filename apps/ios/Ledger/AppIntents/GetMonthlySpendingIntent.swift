import AppIntents
import Foundation
import LedgerKit

/// "Quanto gastei esse mês?" — answered from the local mirror, so it works
/// offline and without opening the app. Returns the total as a value, which is
/// what lets Shortcuts automations chain it (compare, notify, log…).
struct GetMonthlySpendingIntent: AppIntent {
    static let title: LocalizedStringResource = "Gastos do mês"
    static let description = IntentDescription(
        "Soma as notas registradas na Caderneta em um mês.",
        categoryName: "Histórico"
    )

    @Parameter(title: "Mês", description: "Qualquer data dentro do mês desejado; vazio usa o mês atual.")
    var month: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Total gasto no mês de \(\.$month)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let spending = try await PurchaseMirror.monthlySpending(containing: month ?? Date())
        let dialog: IntentDialog =
            if spending.purchaseCount == 0 {
                "Nenhuma nota registrada em \(spending.monthName)."
            } else {
                "Você gastou \(Format.brl(spending.total)) em \(spending.monthName), em \(spending.purchaseCount) \(spending.purchaseCount == 1 ? "nota" : "notas")."
            }
        return .result(value: spending.total, dialog: dialog)
    }
}
