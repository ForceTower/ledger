import ComposableArchitecture
import SwiftUI

private let resultGreen = Color(hex: 0x28A745)
private let resultBlue = Color(hex: 0x2F7BE5)
private let resultOrange = Color(hex: 0xF08C00)

/// The scan result sheet. Switches on the scan phase: a processing placeholder,
/// then one of saved / duplicate / warning / error.
struct ScanResultView: View {
    let store: StoreOf<ScanFeature>

    var body: some View {
        Group {
            switch store.phase {
            case .processing:
                ProcessingView()
            case let .result(response):
                if response.status == .duplicate {
                    DuplicateResultView(store: store, purchase: response.purchase)
                } else if response.warnings.isEmpty {
                    SuccessResultView(store: store, purchase: response.purchase)
                } else {
                    WarningResultView(store: store, purchase: response.purchase, warnings: response.warnings)
                }
            case let .failure(failure):
                ErrorResultView(store: store, failure: failure)
            case .idle, .detecting:
                Color.clear
            }
        }
        .background(Color.appElevated)
    }
}

// MARK: - Processing

private struct ProcessingView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 22) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.appAccent)
            VStack(spacing: 6) {
                Text("Processando nota").font(.title2.weight(.bold))
                Text("Lendo os itens junto à SEFAZ…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                shimmerBar(width: .infinity)
                shimmerBar(width: 190)
                shimmerBar(width: 130)
            }
            .frame(maxWidth: 250)
            .opacity(pulse ? 0.85 : 0.4)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func shimmerBar(width: CGFloat) -> some View {
        Capsule().fill(Color.appFill).frame(height: 12).frame(maxWidth: width)
    }
}

// MARK: - Success

private struct SuccessResultView: View {
    let store: StoreOf<ScanFeature>
    let purchase: Purchase

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Label("Salva · há instantes", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(resultGreen)
                    .padding(.top, 24)

                storeCard
                CategoryBreakdownCard(purchase: purchase)
                ItemsCard(store: store, purchase: purchase)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            ScanAgainButton(store: store)
        }
    }

    private var storeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 46, height: 46)
                    .background(Color.appAccentTint, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(purchase.store.name).font(.title3.weight(.bold))
                    if let legal = purchase.store.legalName {
                        Text(legal).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Divider().padding(.vertical, 16)

            Text("Valor pago").font(.footnote).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                CountUpText(value: purchase.totals.totalPaid)
                if purchase.totals.discount > 0 {
                    Text("−\(Format.brl(purchase.totals.discount)) desc.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(resultGreen)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(resultGreen.opacity(0.14), in: Capsule())
                }
            }
            .padding(.top, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    InfoChip { Text(Format.longDateTime(date: purchase.date, time: purchase.time)).foregroundStyle(.secondary) }
                    if let payment = purchase.payments.first {
                        InfoChip {
                            Circle().fill(Color.appAccent).frame(width: 7, height: 7)
                            Text(payment.method).fontWeight(.medium)
                        }
                    }
                    InfoChip {
                        Text("\(purchase.totals.itemCount)").fontWeight(.semibold)
                        Text("itens").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 14)
        }
        .padding(18)
        .card()
    }
}

private struct CategoryBreakdownCard: View {
    let purchase: Purchase

    private var segments: [(category: Category, count: Int)] {
        let grouped = Dictionary(grouping: purchase.items, by: { $0.category }).mapValues(\.count)
        return grouped
            .map { (category: $0.key, count: $0.value) }
            .sorted { $0.category.sortIndex < $1.category.sortIndex }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardSectionHeader("Por categoria", trailing: "\(purchase.totals.itemCount) itens")

            CategoryProportionBar(
                segments: segments.map { (color: $0.category.color, weight: Double($0.count)) },
                height: 13,
                spacing: 2
            )
            .padding(.top, 13)

            FlowChips(segments: segments).padding(.top, 14)
        }
        .padding(17)
        .card()
    }
}

/// Category legend that wraps to new lines as needed (native Layout).
private struct FlowChips: View {
    let segments: [(category: Category, count: Int)]

    var body: some View {
        WrapLayout(spacing: 18, lineSpacing: 8) {
            ForEach(segments, id: \.category) { segment in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(segment.category.color).frame(width: 10, height: 10)
                    Text(segment.category.label).font(.subheadline.weight(.medium))
                    Text("\(segment.count)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ItemsCard: View {
    let store: StoreOf<ScanFeature>
    let purchase: Purchase

    private var visibleItems: [PurchaseItem] {
        store.itemsExpanded ? purchase.items : Array(purchase.items.prefix(3))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ITENS").font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(0.4)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            ForEach(visibleItems) { item in
                itemRow(item)
                Divider().padding(.leading, 37)
            }

            Button { store.send(.toggleItems) } label: {
                HStack(spacing: 5) {
                    Text(store.itemsExpanded ? "Ver menos" : "Ver todos os \(purchase.items.count) itens")
                    Image(systemName: store.itemsExpanded ? "chevron.up" : "chevron.down").font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.appAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
        }
        .card()
    }

    private func itemRow(_ item: PurchaseItem) -> some View {
        HStack(spacing: 12) {
            Circle().fill(item.category.color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.description).font(.subheadline.weight(.medium))
                Text(itemSubtitle(item)).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.brl(item.total)).font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }
}

func itemSubtitle(_ item: PurchaseItem) -> String {
    if item.unit != "un" {
        return "\(Format.quantity(item.quantity, unit: item.unit)) · \(Format.unitPrice(item.unitPrice, unit: item.unit))"
    }
    if item.quantity > 1 {
        return "\(Format.quantity(item.quantity, unit: item.unit)) · \(Format.brl(item.unitPrice))"
    }
    return Format.quantity(item.quantity, unit: item.unit)
}

// MARK: - Duplicate

private struct DuplicateResultView: View {
    let store: StoreOf<ScanFeature>
    let purchase: Purchase

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 30))
                .foregroundStyle(resultBlue)
                .frame(width: 74, height: 74)
                .background(resultBlue.opacity(0.14), in: Circle())
                .padding(.top, 40).padding(.bottom, 20)

            Text("Essa nota já foi cadastrada")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text("Você salvou esta compra em **\(Format.dayMonthYear(purchase.date))**. Nada novo foi adicionado.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .frame(maxWidth: 300)

            Button { store.send(.showDuplicateInHistory) } label: {
                HStack(spacing: 13) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(Color.appAccent)
                        .frame(width: 42, height: 42)
                        .background(Color.appAccentTint, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(purchase.store.name).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                        Text("\(Format.dayMonth(fromISO: purchase.date)) · \(Format.brl(purchase.totals.totalPaid)) · \(purchase.totals.itemCount) itens")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.label3)
                }
                .padding(14)
                .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 26)

            Spacer()

            Button { store.send(.scanAgainTapped) } label: {
                Text("Escanear outra")
                    .font(.headline)
                    .foregroundStyle(Color.appAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.appAccentTint, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 26)
    }
}

// MARK: - Warning

private struct WarningResultView: View {
    let store: StoreOf<ScanFeature>
    let purchase: Purchase
    let warnings: [String]

    private var itemsSum: Double { purchase.items.reduce(0) { $0 + $1.total } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(resultOrange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(warnings.first ?? "Atenção").font(.subheadline.weight(.semibold))
                        Text("Itens somam **\(Format.brl(itemsSum))** · total da nota **\(Format.brl(purchase.totals.totalPaid))**. Salvamos mesmo assim.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(resultOrange.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(resultOrange.opacity(0.36)))

                VStack(spacing: 0) {
                    HStack(spacing: 13) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(Color.appAccent)
                            .frame(width: 46, height: 46)
                            .background(Color.appAccentTint, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(purchase.store.name).font(.title3.weight(.bold))
                            Text(Format.longDateTime(date: purchase.date, time: purchase.time))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Divider().padding(.vertical, 16)
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Valor pago").font(.footnote).foregroundStyle(.secondary)
                            Text(Format.brl(purchase.totals.totalPaid)).font(.system(size: 30, weight: .bold)).monospacedDigit()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("Itens").font(.footnote).foregroundStyle(.secondary)
                            Text("\(purchase.totals.itemCount)").font(.title3.weight(.semibold))
                        }
                    }
                }
                .padding(18)
                .card()
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.appSeparator, lineWidth: 0.5))
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 9) {
                Button { store.send(.scanAgainTapped) } label: {
                    Text("Escanear outra")
                        .font(.headline)
                        .foregroundStyle(Color.appAccentForeground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                Button("Revisar itens") { store.send(.showDuplicateInHistory) }
                    .font(.callout.weight(.medium))
                    .tint(Color.appAccent)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Color.appElevated)
        }
    }
}

// MARK: - Error

private struct ErrorResultView: View {
    let store: StoreOf<ScanFeature>
    let failure: ScanFailure

    private var symbol: String {
        switch failure {
        case .invalidQR: "qrcode"
        case .expired: "clock.badge.exclamationmark"
        case .unavailable, .parseFailed: "exclamationmark.icloud"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(resultOrange)
                .frame(width: 74, height: 74)
                .background(resultOrange.opacity(0.14), in: Circle())
                .padding(.top, 54).padding(.bottom, 20)

            Text(failure.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text(failure.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .frame(maxWidth: 300)

            Text(failure.code)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.label3)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.appFill, in: Capsule())
                .padding(.top, 16)

            Spacer()

            Button { store.send(.scanAgainTapped) } label: {
                Text(failure.retryLabel)
                    .font(.headline)
                    .foregroundStyle(Color.appAccentForeground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }

            Button("Abrir Ajustes") { store.send(.settingsTapped) }
                .font(.callout.weight(.medium))
                .tint(Color.appAccent)
                .padding(.top, 14)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 26)
    }
}

// MARK: - Shared

private struct ScanAgainButton: View {
    let store: StoreOf<ScanFeature>

    var body: some View {
        Button { store.send(.scanAgainTapped) } label: {
            Text("Escanear outra")
                .font(.headline)
                .foregroundStyle(Color.appAccentForeground)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color.appElevated)
    }
}
