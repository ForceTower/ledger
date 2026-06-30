import ComposableArchitecture
import SwiftUI

/// The public entry point the app embeds. The root `Store` lives inside the
/// package, so the app target never imports TCA directly — keeping
/// ComposableArchitecture linked exactly once (here, in this package).
public struct RootView: View {
    @State private var store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    public init() {}

    public var body: some View {
        AppView(store: store)
    }
}
