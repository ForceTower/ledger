import ComposableArchitecture

// Root feature. Currently a minimal scaffold that proves the TCA wiring end to end;
// child features (scan, purchases, settings) will be composed in here.
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var count = 0
    }

    enum Action {
        case decrementButtonTapped
        case incrementButtonTapped
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .decrementButtonTapped:
                state.count -= 1
                return .none
            case .incrementButtonTapped:
                state.count += 1
                return .none
            }
        }
    }
}
