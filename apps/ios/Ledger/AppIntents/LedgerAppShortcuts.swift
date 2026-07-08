import AppIntents

struct LedgerAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetMonthlySpendingIntent(),
            phrases: [
                "Quanto gastei esse mês no \(.applicationName)",
                "Quanto eu gastei no \(.applicationName) esse mês",
                "Gastos do mês no \(.applicationName)",
                "Total do mês no \(.applicationName)",
            ],
            shortTitle: "Gastos do mês",
            systemImageName: "chart.bar.xaxis"
        )
        AppShortcut(
            intent: GetRecentPurchasesIntent(),
            phrases: [
                "Quais foram minhas compras no \(.applicationName)",
                "Minhas compras no \(.applicationName)",
                "Minhas últimas compras no \(.applicationName)",
                "Onde eu comprei no \(.applicationName)",
                "Onde comprei minhas coisas no \(.applicationName)",
            ],
            shortTitle: "Últimas compras",
            systemImageName: "bag"
        )
    }
}
