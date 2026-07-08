import ComposableArchitecture
import SwiftUI

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    private var tabBinding: Binding<AppFeature.Tab> {
        Binding(get: { store.tab }, set: { store.send(.tabChanged($0)) })
    }

    var body: some View {
        TabView(selection: tabBinding) {
            ScanView(store: store.scope(state: \.scan, action: \.scan), isActive: store.tab == .scan)
                .tabItem { Label("Escanear", systemImage: "qrcode.viewfinder") }
                .tag(AppFeature.Tab.scan)

            HistoryView(store: store.scope(state: \.history, action: \.history))
                .tabItem { Label("Histórico", systemImage: "list.bullet") }
                .tag(AppFeature.Tab.history)

            InsightsView(store: store.scope(state: \.insights, action: \.insights))
                .tabItem { Label("Insights", systemImage: "chart.bar.xaxis") }
                .tag(AppFeature.Tab.insights)

            AskView(store: store.scope(state: \.ask, action: \.ask))
                .tabItem { Label("Perguntar", systemImage: "ellipsis.bubble") }
                .tag(AppFeature.Tab.ask)
        }
        .tint(Color.appAccent)
        .preferredColorScheme(store.theme.colorScheme)
        .sheet(item: $store.scope(state: \.settings, action: \.settings)) { settingsStore in
            SettingsView(store: settingsStore)
        }
    }
}

#Preview {
    AppView(store: Store(initialState: AppFeature.State()) { AppFeature() })
}
