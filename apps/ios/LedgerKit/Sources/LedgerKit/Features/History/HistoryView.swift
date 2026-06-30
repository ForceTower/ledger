import ComposableArchitecture
import SwiftUI

/// The purchases tab. A native grouped list, searchable and pull-to-refresh,
/// pushing a detail through the navigation stack.
struct HistoryView: View {
    @Bindable var store: StoreOf<HistoryFeature>

    private var searchBinding: Binding<String> {
        Binding(get: { store.searchText }, set: { store.send(.searchChanged($0)) })
    }

    var body: some View {
        NavigationStack {
            List {
                if let line = store.summaryLine {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(line).font(.subheadline).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                filterChip("Todas as lojas", active: true)
                                filterChip("Período", active: false)
                                Spacer()
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

                ForEach(store.sections) { section in
                    Section {
                        ForEach(section.purchases) { purchase in
                            Button { store.send(.purchaseTapped(purchase)) } label: {
                                PurchaseRow(summary: purchase)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text(section.title).textCase(nil)
                            Spacer()
                            Text(Format.brl(section.total)).foregroundStyle(Color.label3)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .insetGroupedListStyle()
            .navigationTitle("Histórico")
            .searchable(text: searchBinding, prompt: "Buscar loja ou item")
            .refreshable { await store.send(.refresh).finish() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { store.send(.refresh) } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .overlay {
                if store.isEmpty {
                    EmptyHistoryView { store.send(.scanFirstTapped) }
                }
            }
            .navigationDestination(item: $store.scope(state: \.detail, action: \.detail)) { detailStore in
                PurchaseDetailView(store: detailStore)
            }
        }
        .task { store.send(.onAppear) }
    }

    private func filterChip(_ title: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.subheadline.weight(active ? .semibold : .medium))
            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
        }
        .foregroundStyle(active ? Color.appAccent : Color.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(active ? Color.appAccentTint : Color.appFill, in: Capsule())
    }
}

#Preview {
    HistoryView(store: Store(initialState: HistoryFeature.State()) { HistoryFeature() })
}

private struct PurchaseRow: View {
    let summary: PurchaseSummary

    var body: some View {
        HStack(spacing: 12) {
            StoreAvatar(name: summary.store, tint: summary.dominantCategory?.color ?? .appAccent)
            VStack(alignment: .leading, spacing: 5) {
                Text(summary.store).font(.body.weight(.semibold))
                CategoryProportionBar(segments: summary.barSegments, height: 3).frame(width: 58)
                Text("\(Format.dayMonth(fromISO: summary.date)) · \(summary.itemCount) itens")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.brl(summary.totalPaid)).font(.body.weight(.semibold))
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct EmptyHistoryView: View {
    let scanFirst: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .frame(width: 96, height: 96)
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(.bottom, 22)

            Text("Nenhuma nota por aqui ainda")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            Text("Escaneie o QR code da sua primeira compra e ela aparece organizada aqui.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .frame(maxWidth: 280)

            Button(action: scanFirst) {
                Text("Escanear primeira nota")
                    .font(.headline)
                    .foregroundStyle(Color.appAccentForeground)
                    .padding(.horizontal, 22)
                    .frame(height: 50)
                    .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.top, 24)
        }
        .padding(.horizontal, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
}
