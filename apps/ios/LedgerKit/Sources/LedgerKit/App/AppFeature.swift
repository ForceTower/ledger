import ComposableArchitecture

/// Root feature. Owns the selected tab and the app-wide Settings sheet, and
/// composes the four tab features. Cross-feature navigation (open Settings, jump
/// to a tab) arrives as child `delegate` actions and is resolved here.
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var tab: Tab = .scan
        var scan = ScanFeature.State()
        var history = HistoryFeature.State()
        var insights = InsightsFeature.State()
        var ask = AskFeature.State()
        @Presents var settings: SettingsFeature.State?
        @Shared(.appStorage("theme")) var theme: AppTheme = .system
    }

    enum Tab: String, CaseIterable, Hashable, Sendable {
        case scan, history, insights, ask
    }

    enum Action {
        case tabChanged(Tab)
        case scan(ScanFeature.Action)
        case history(HistoryFeature.Action)
        case insights(InsightsFeature.Action)
        case ask(AskFeature.Action)
        case settings(PresentationAction<SettingsFeature.Action>)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.scan, action: \.scan) { ScanFeature() }
        Scope(state: \.history, action: \.history) { HistoryFeature() }
        Scope(state: \.insights, action: \.insights) { InsightsFeature() }
        Scope(state: \.ask, action: \.ask) { AskFeature() }

        Reduce { state, action in
            switch action {
            case let .tabChanged(tab):
                state.tab = tab
                return .none

            case .scan(.delegate(.openSettings)):
                state.settings = SettingsFeature.State()
                return .none

            case .scan(.delegate(.showHistory)):
                state.tab = .history
                return .none

            case .history(.delegate(.switchToScan)):
                state.tab = .scan
                return .none

            case .scan, .history, .insights, .ask, .settings:
                return .none
            }
        }
        .ifLet(\.$settings, action: \.settings) { SettingsFeature() }
    }
}
