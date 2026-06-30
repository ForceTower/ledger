import ComposableArchitecture

/// Ask is a "Em breve" (coming soon) preview of the natural-language Q&A over
/// the dataset (`POST /ask`). Static transcript for now.
@Reducer
struct AskFeature {
    @ObservableState
    struct State: Equatable {}

    enum Action: Equatable {}

    var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}
