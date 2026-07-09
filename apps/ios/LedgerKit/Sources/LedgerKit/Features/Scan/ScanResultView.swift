import ComposableArchitecture
import SwiftUI

private let resultGreen = Color(hex: 0x28A745)
private let resultBlue = Color(hex: 0x2F7BE5)
private let resultOrange = Color(hex: 0xF08C00)

struct ScanResultView: View {
    let store: StoreOf<ScanFeature>

    var body: some View {
        Group {
            switch store.phase {
            case .processing:
                ProcessingView(photoMode: store.scanMode == .photo)
            case let .result(response):
                if response.status == .duplicate {
                    DuplicateResultView(store: store, purchase: response.purchase)
                } else if response.warnings.isEmpty {
                    SuccessResultView(store: store, purchase: response.purchase)
                } else {
                    WarningResultView(store: store, purchase: response.purchase, warnings: response.warnings)
                }
            case let .product(guess):
                if store.productSaved {
                    ProductSavedView(store: store, guess: guess)
                } else {
                    ProductResultView(store: store, guess: guess)
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
    let photoMode: Bool

    @State private var pulse = false
    @State private var spinning = false

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .stroke(Color.appFill, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                Image(systemName: photoMode ? "sparkles" : "doc.text.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 46, height: 46)
                    .background(Color.appAccentTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .frame(width: 78, height: 78)
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spinning = true }
            }

            VStack(spacing: 6) {
                Text(photoMode ? "Identificando a imagem" : "Lendo sua nota")
                    .font(.title2.weight(.bold))
                Text(photoMode ? "Reconhecendo o que está na foto…" : "Buscando os itens junto à SEFAZ…")
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
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.white.opacity(0.18))
                    .frame(width: 46, height: 46)
                    .overlay {
                        Text(String(purchase.store.name.first.map(String.init) ?? "?"))
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(purchase.store.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.heroInk)
                    if let legal = purchase.store.legalName {
                        Text(legal).font(.footnote).foregroundStyle(Color.heroInkSecondary)
                    }
                }
                Spacer()
            }

            Text("Valor pago")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.heroInkSecondary)
                .padding(.top, 16)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                CountUpText(value: purchase.totals.totalPaid)
                    .foregroundStyle(Color.heroInk)
                if purchase.totals.discount > 0 {
                    Text("−\(Format.brl(purchase.totals.discount))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.heroInk)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
            .padding(.top, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    heroChip(Format.longDateTime(date: purchase.date, time: purchase.time))
                    if let payment = purchase.payments.first {
                        heroChip(payment.method)
                    }
                    heroChip("\(purchase.totals.itemCount) itens")
                }
            }
            .padding(.top, 14)
        }
        .padding(18)
        .background(AppGradient.hero, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(hex: 0x0A6E66, alpha: 0.34), radius: 16, y: 6)
    }

    private func heroChip(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.heroInk)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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

            Button { store.send(.showInHistoryTapped) } label: {
                HStack(spacing: 13) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(AppGradient.accent)
                        .frame(width: 42, height: 42)
                        .overlay {
                            Text(String(purchase.store.name.first.map(String.init) ?? "?"))
                                .font(.system(size: 17, weight: .heavy))
                                .foregroundStyle(.white)
                        }
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
                    PrimaryButtonLabel("Escanear outra")
                }
                Button("Revisar itens") { store.send(.showInHistoryTapped) }
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
                PrimaryButtonLabel(failure.retryLabel)
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

// MARK: - Product (photo mode)

private struct ProductResultView: View {
    let store: StoreOf<ScanFeature>
    let guess: ProductGuess

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Label("Identificado com IA · \(guess.confidencePercent)%", systemImage: "sparkles")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.appAccent)
                    .padding(.top, 24)

                productCard
                detailsCard
                alternativesCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button { store.send(.addProductTapped) } label: {
                PrimaryButtonLabel("Adicionar ao histórico")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Color.appElevated)
        }
    }

    private var productCard: some View {
        HStack(spacing: 14) {
            PhotoPlaceholder(size: 82, cornerRadius: 16, caption: "sua foto")

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(guess.category.color)
                        .frame(width: 8, height: 8)
                    Text(guess.category.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.4)
                }
                Text(guess.name)
                    .font(.title3.weight(.heavy))
                    .padding(.top, 7)
                Text(guess.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .card(cornerRadius: 22)
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DETALHES").font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(0.4)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            HStack {
                Text("Preço estimado").font(.subheadline)
                Spacer()
                Text(Format.brl(guess.unitPrice)).font(.subheadline.weight(.bold))
                Text("/un").font(.caption).foregroundStyle(Color.label3)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)

            Divider().padding(.leading, 16)

            HStack {
                Text("Quantidade").font(.subheadline)
                Spacer()
                HStack(spacing: 15) {
                    quantityButton(systemImage: "minus", background: Color.appFill, tint: .primary) {
                        store.send(.productQuantityChanged(store.productQuantity - 1))
                    }
                    Text("\(store.productQuantity)")
                        .font(.body.weight(.heavy))
                        .monospacedDigit()
                        .frame(minWidth: 22)
                    quantityButton(systemImage: "plus", background: Color.appAccentTint, tint: Color.appAccent) {
                        store.send(.productQuantityChanged(store.productQuantity + 1))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 9)

            Divider().padding(.leading, 16)

            HStack {
                Text("Total").font(.subheadline.weight(.bold))
                Spacer()
                Text(Format.brl(guess.unitPrice * Double(store.productQuantity)))
                    .font(.body.weight(.heavy))
                    .monospacedDigit()
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(Color.appFillSubtle)
        }
        .card(cornerRadius: 20)
    }

    private func quantityButton(
        systemImage: String,
        background: Color,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 31, height: 31)
                .background(background, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var alternativesCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("NÃO É ISSO?").font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(0.4)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)

            ForEach(guess.alternatives) { alternative in
                HStack(spacing: 12) {
                    PhotoPlaceholder(size: 38, cornerRadius: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(alternative.name).font(.subheadline.weight(.semibold))
                        Text("unidade · \(Format.brl(alternative.unitPrice))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.appAccent)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(Color.appAccent, lineWidth: 1.6))
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                if alternative.id != guess.alternatives.last?.id {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .card(cornerRadius: 20)
    }
}

private struct ProductSavedView: View {
    let store: StoreOf<ScanFeature>
    let guess: ProductGuess

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(resultGreen, in: Circle())
                .shadow(color: resultGreen.opacity(0.4), radius: 13, y: 5)
                .padding(.top, 44).padding(.bottom, 20)

            Text("Adicionado ao histórico")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text("Registramos **\(store.productQuantity)× \(guess.name)** na sua compra de hoje.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .frame(maxWidth: 300)

            HStack(spacing: 13) {
                PhotoPlaceholder(size: 44, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(guess.name).font(.callout.weight(.bold))
                    Text("\(guess.category.label) · hoje").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Format.brl(guess.unitPrice * Double(store.productQuantity)))
                    .font(.callout.weight(.heavy))
            }
            .padding(14)
            .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 24)

            Spacer()

            Button { store.send(.showInHistoryTapped) } label: {
                PrimaryButtonLabel("Ver no histórico")
            }

            Button("Identificar outro") { store.send(.scanAgainTapped) }
                .font(.callout.weight(.medium))
                .tint(Color.appAccent)
                .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 26)
    }
}

private struct PhotoPlaceholder: View {
    var size: CGFloat
    var cornerRadius: CGFloat
    var caption: String?

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.appFill)
            .frame(width: size, height: size)
            .overlay {
                if let caption {
                    Text(caption)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.label3)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: size * 0.32))
                        .foregroundStyle(Color.label3)
                }
            }
    }
}

// MARK: - Shared

private struct ScanAgainButton: View {
    let store: StoreOf<ScanFeature>

    var body: some View {
        Button { store.send(.scanAgainTapped) } label: {
            PrimaryButtonLabel("Escanear outra")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color.appElevated)
    }
}

// MARK: - Previews

@MainActor
private func scanResultStore(phase: ScanFeature.State.Phase, productSaved: Bool = false) -> StoreOf<ScanFeature> {
    var state = ScanFeature.State()
    state.phase = phase
    state.productSaved = productSaved
    return Store(initialState: state) { ScanFeature() }
}

#Preview("Salva") {
    ScanResultView(
        store: scanResultStore(
            phase: .result(ScanResponse(status: .saved, purchase: MockData.atacadao, warnings: []))
        )
    )
}

#Preview("Duplicada") {
    ScanResultView(
        store: scanResultStore(
            phase: .result(ScanResponse(status: .duplicate, purchase: MockData.atacadao, warnings: []))
        )
    )
}

#Preview("Aviso") {
    ScanResultView(
        store: scanResultStore(
            phase: .result(ScanResponse(
                status: .saved,
                purchase: MockData.atacadao,
                warnings: ["A soma dos itens não bate com o total"]
            ))
        )
    )
}

#Preview("Erro") {
    ScanResultView(store: scanResultStore(phase: .failure(.expired)))
}

#Preview("Processando") {
    ScanResultView(store: scanResultStore(phase: .processing))
}

#Preview("Produto identificado") {
    ScanResultView(store: scanResultStore(phase: .product(MockData.productGuess)))
}

#Preview("Produto adicionado") {
    ScanResultView(store: scanResultStore(phase: .product(MockData.productGuess), productSaved: true))
}
