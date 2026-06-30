import ComposableArchitecture

/// Insights is a "Em breve" (coming soon) preview — a static spending snapshot.
/// No state or behavior yet; kept as a feature so the tab composes uniformly.
@Reducer
struct InsightsFeature {
    @ObservableState
    struct State: Equatable {}

    enum Action: Equatable {}

    var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}
