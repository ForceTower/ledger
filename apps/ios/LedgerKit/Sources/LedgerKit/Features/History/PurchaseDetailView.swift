import ComposableArchitecture
import SwiftUI

struct PurchaseDetailView: View {
    let store: StoreOf<PurchaseDetailFeature>

    private var shareText: String {
        let summary = store.summary
        return "\(summary.store) — \(Format.dayMonthYear(summary.date)) — \(Format.brl(summary.totalPaid))"
    }

    var body: some View {
        ScrollView {
            if let purchase = store.purchase {
                VStack(spacing: 14) {
                    storeCard(purchase)
                    totalsCard(purchase)
                    ForEach(purchase.itemsByCategory, id: \.category) { group in
                        categorySection(group.category, items: group.items)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            } else if store.loadFailed {
                ContentUnavailableView(
                    "Detalhes indisponíveis",
                    systemImage: "wifi.slash",
                    description: Text("Conecte-se ao servidor para carregar esta compra.")
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 320)
            }
        }
        .background(Color.appBackground)
        .navigationTitle(store.summary.store)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .task { store.send(.onAppear) }
    }

    private func storeCard(_ purchase: Purchase) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let legal = purchase.store.legalName {
                Text("\(purchase.store.name) · \(legal)").font(.footnote).foregroundStyle(.secondary)
            }
            if let address = purchase.store.address {
                Text(address).font(.subheadline).padding(.top, 6)
            }
            Divider().padding(.vertical, 13)
            detailRow("Data", Format.longDateTime(date: purchase.date, time: purchase.time))
            if let payment = purchase.payments.first {
                detailRow("Pagamento", payment.method).padding(.top, 8)
            }
        }
        .padding(16)
        .card(cornerRadius: 16)
    }

    private func totalsCard(_ purchase: Purchase) -> some View {
        VStack(spacing: 9) {
            HStack {
                Text("Subtotal").foregroundStyle(.secondary)
                Spacer()
                Text(Format.brl(purchase.totals.gross))
            }
            if purchase.totals.discount > 0 {
                HStack {
                    Text("Desconto").foregroundStyle(.secondary)
                    Spacer()
                    Text("−\(Format.brl(purchase.totals.discount))").foregroundStyle(Color(hex: 0x28A745))
                }
            }
            Divider().padding(.vertical, 4)
            HStack {
                Text("Total pago").font(.body.weight(.semibold))
                Spacer()
                Text(Format.brl(purchase.totals.totalPaid)).font(.title3.weight(.bold))
            }
        }
        .font(.subheadline)
        .padding(16)
        .card(cornerRadius: 16)
    }

    private func categorySection(_ category: Category, items: [PurchaseItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(category.color).frame(width: 9, height: 9)
                Text("\(category.label.uppercased()) · \(items.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            VStack(spacing: 0) {
                ForEach(items) { item in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.description).font(.subheadline)
                            Text(itemSubtitle(item)).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Format.brl(item.total)).font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    if item.id != items.last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .card(cornerRadius: 16)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

#Preview {
    NavigationStack {
        PurchaseDetailView(
            store: Store(initialState: PurchaseDetailFeature.State(summary: MockData.summaries[0])) {
                PurchaseDetailFeature()
            }
        )
    }
}
