import ComposableArchitecture
import SwiftUI

struct AppView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "creditcard")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            VStack(spacing: 4) {
                Text("Ledger")
                    .font(.largeTitle.bold())
                Text("Seu controle de gastos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("\(store.count)")
                .font(.system(.title, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())

            HStack(spacing: 16) {
                Button {
                    store.send(.decrementButtonTapped)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 44, height: 44)
                }
                Button {
                    store.send(.incrementButtonTapped)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    AppView(store: Store(initialState: AppFeature.State()) { AppFeature() })
}
