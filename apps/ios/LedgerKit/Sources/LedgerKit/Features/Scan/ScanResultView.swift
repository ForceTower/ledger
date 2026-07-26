import ComposableArchitecture
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private let resultGreen = Color(hex: 0x28A745)
private let resultBlue = Color(hex: 0x2F7BE5)
private let resultOrange = Color(hex: 0xF08C00)

struct ScanResultView: View {
    let store: StoreOf<ScanFeature>

    var body: some View {
        Group {
            switch store.phase {
            case .processing:
                ProcessingView(mode: store.scanMode)
            case let .result(response):
                if response.status == .duplicate {
                    DuplicateResultView(store: store, purchase: response.purchase)
                } else if response.warnings.isEmpty {
                    SuccessResultView(store: store, purchase: response.purchase)
                } else {
                    WarningResultView(store: store, purchase: response.purchase, warnings: response.warnings)
                }
            case let .product(identified):
                if store.productSaved {
                    ProductSavedView(store: store)
                } else {
                    ProductResultView(store: store, identified: identified)
                }
            case let .rejected(rejected):
                RejectedResultView(store: store, rejected: rejected)
            case let .failure(failure):
                ErrorResultView(store: store, failure: failure)
            case let .captcha(challenge):
                CaptchaResultView(store: store, challenge: challenge)
            case let .photoFailure(failure):
                PhotoErrorResultView(store: store, failure: failure)
            case let .entry(draft):
                EntryDraftView(store: store, draft: draft)
            case let .entrySaved(purchase):
                EntrySavedView(store: store, purchase: purchase)
            case let .entryFailure(failure):
                EntryErrorResultView(store: store, failure: failure)
            case .idle, .detecting, .capturing:
                Color.clear
            }
        }
        .background(Color.appElevated)
    }
}

// MARK: - Processing

private struct ProcessingView: View {
    let mode: ScanMode

    @State private var pulse = false
    @State private var spinning = false

    private var symbol: String {
        switch mode {
        case .receipt: "doc.text.fill"
        case .photo: "sparkles"
        case .entry: "square.and.pencil"
        }
    }

    private var title: String {
        switch mode {
        case .receipt: "Lendo sua nota"
        case .photo: "Identificando a imagem"
        case .entry: "Montando o rascunho"
        }
    }

    private var subtitle: String {
        switch mode {
        case .receipt: "Buscando os itens junto à SEFAZ…"
        case .photo: "Reconhecendo o que está na foto…"
        case .entry: "Entendendo valor, categoria e data…"
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .stroke(Color.appFill, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                Image(systemName: symbol)
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
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
        case .qrRejected: "qrcode.viewfinder"
        case .captchaRejected, .challengeExpired: "textformat.abc"
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

            if failure == .qrRejected {
                Button { store.send(.consultByKeyTapped) } label: {
                    PrimaryButtonLabel("Buscar pela chave de acesso")
                }

                Button(failure.retryLabel) { store.send(.scanAgainTapped) }
                    .font(.callout.weight(.medium))
                    .tint(Color.appAccent)
                    .padding(.top, 14)
            } else {
                Button { store.send(.scanAgainTapped) } label: {
                    PrimaryButtonLabel(failure.retryLabel)
                }

                Button("Abrir Ajustes") { store.send(.settingsTapped) }
                    .font(.callout.weight(.medium))
                    .tint(Color.appAccent)
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 26)
    }
}

// MARK: - Captcha (access-key consultation)

/// The SEFAZ anti-robot gate: show the relayed image, let the owner type its characters.
private struct CaptchaResultView: View {
    let store: StoreOf<ScanFeature>
    let challenge: CaptchaChallenge

    private var trimmedAnswer: String {
        store.captchaAnswer.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "textformat.abc")
                .font(.system(size: 30))
                .foregroundStyle(Color.appAccent)
                .frame(width: 74, height: 74)
                .background(Color.appAccentTint, in: Circle())
                .padding(.top, 44).padding(.bottom, 20)

            Text("Digite o código da imagem")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text("A SEFAZ pede esta verificação para buscar a nota pela chave de acesso.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .frame(maxWidth: 300)

            captchaImage
                .padding(.top, 24)

            if let error = store.captchaError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(resultOrange)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }

            TextField("Código", text: Binding(
                get: { store.captchaAnswer },
                set: { store.send(.captchaAnswerChanged($0)) }
            ))
            .font(.system(.title3, design: .monospaced).weight(.bold))
            .multilineTextAlignment(.center)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.characters)
            .keyboardType(.asciiCapable)
            #endif
            .onSubmit { store.send(.submitCaptchaTapped) }
            .padding(.vertical, 13)
            .background(Color.appFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(maxWidth: 220)
            .padding(.top, 14)

            Button("Não consigo ler · nova imagem") { store.send(.newCaptchaTapped) }
                .font(.footnote.weight(.medium))
                .tint(Color.appAccent)
                .disabled(store.captchaBusy)
                .padding(.top, 12)

            Spacer()

            Button { store.send(.submitCaptchaTapped) } label: {
                if store.captchaBusy {
                    ProgressView()
                        .tint(Color.appAccentForeground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppGradient.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                } else {
                    PrimaryButtonLabel("Buscar nota")
                }
            }
            .disabled(store.captchaBusy || trimmedAnswer.isEmpty)
            .opacity(!store.captchaBusy && trimmedAnswer.isEmpty ? 0.5 : 1)

            Button("Cancelar") { store.send(.scanAgainTapped) }
                .font(.callout.weight(.medium))
                .tint(.secondary)
                .padding(.top, 14)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 26)
    }

    private var captchaImage: some View {
        Group {
            #if canImport(UIKit)
            if let image = UIImage(data: challenge.image) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: 64)
            } else {
                captchaPlaceholder
            }
            #else
            captchaPlaceholder
            #endif
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appSeparator, lineWidth: 0.5))
    }

    private var captchaPlaceholder: some View {
        Text("? ? ? ?")
            .font(.system(.title3, design: .monospaced).weight(.bold))
            .foregroundStyle(Color.label3)
            .frame(height: 64)
    }
}

// MARK: - Product (photo mode)

private struct ProductResultView: View {
    let store: StoreOf<ScanFeature>
    let identified: PhotoScanIdentified

    @FocusState private var priceFocus: ProductDraft.ID?

    private var itemCount: Int { identified.items.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Label(headline, systemImage: "sparkles")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.appAccent)
                    .padding(.top, 24)

                photoCard
                ForEach(store.productDrafts) { draft in
                    ProductDraftCard(store: store, draft: draft, priceFocus: $priceFocus)
                }
                if store.selectedDrafts.count > 1 {
                    grandTotalCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Pronto") { priceFocus = nil }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { store.send(.addProductTapped) } label: {
                PrimaryButtonLabel(addTitle)
            }
            .disabled(store.selectedDrafts.isEmpty)
            .opacity(store.selectedDrafts.isEmpty ? 0.5 : 1)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Color.appElevated)
        }
    }

    private var headline: String {
        itemCount == 1
            ? "Identificado com IA · \(identified.items[0].confidencePercent)%"
            : "Identificados com IA · \(itemCount) itens"
    }

    private var addTitle: String {
        let selected = store.selectedDrafts.count
        return selected > 1 ? "Adicionar \(selected) itens ao histórico" : "Adicionar ao histórico"
    }

    private var photoCard: some View {
        HStack(spacing: 14) {
            CapturedPhotoView(data: store.capturedPhoto, size: 82, cornerRadius: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(itemCount == 1 ? "1 item na foto" : "\(itemCount) itens na foto")
                    .font(.headline.weight(.heavy))
                if !identified.comment.isEmpty {
                    Text(identified.comment)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(
                    itemCount == 1
                        ? "Informe o preço para adicionar ao histórico."
                        : "Marque os itens que entram e informe o preço de cada um."
                )
                .font(.caption)
                .foregroundStyle(Color.label3)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .card(cornerRadius: 22)
    }

    private var grandTotalCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Total geral").font(.subheadline.weight(.bold))
                Text("\(store.productUnitCount) unidades").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.brl(store.productTotal))
                .font(.title3.weight(.heavy))
                .monospacedDigit()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .card(cornerRadius: 20)
    }
}

/// One identified item: the AI's guess, plus the price and quantity the owner fills in.
private struct ProductDraftCard: View {
    let store: StoreOf<ScanFeature>
    let draft: ProductDraft
    let priceFocus: FocusState<ProductDraft.ID?>.Binding

    var body: some View {
        VStack(spacing: 0) {
            itemHeader
            if draft.selected {
                Divider().padding(.leading, 16)
                priceRow
                Divider().padding(.leading, 16)
                quantityRow
                totalRow
            }
        }
        .card(cornerRadius: 20)
    }

    private var itemHeader: some View {
        Button { store.send(.productSelectionToggled(id: draft.id)) } label: {
            HStack(spacing: 12) {
                Image(systemName: draft.selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(draft.selected ? Color.appAccent : Color.label3)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(draft.item.category.color)
                            .frame(width: 8, height: 8)
                        Text(draft.item.category.label.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.4)
                        Text("· \(draft.item.confidencePercent)%")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.label3)
                    }
                    Text(draft.item.description)
                        .font(.callout.weight(.heavy))
                        .foregroundStyle(draft.selected ? .primary : .secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .buttonStyle(.plain)
    }

    // Prefilled when the AI could read a price off the photo; the owner has the last word.
    private var priceRow: some View {
        HStack {
            Text("Preço").font(.subheadline)
            Spacer()
            TextField(
                "R$ 0,00",
                value: Binding(
                    get: { draft.unitPrice },
                    set: { store.send(.productPriceChanged(id: draft.id, price: $0)) }
                ),
                format: .currency(code: "BRL").locale(Locale(identifier: "pt_BR"))
            )
            .multilineTextAlignment(.trailing)
            .font(.subheadline.weight(.bold))
            .focused(priceFocus, equals: draft.id)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
            .frame(maxWidth: 120)
            Text("/un").font(.caption).foregroundStyle(Color.label3)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private var quantityRow: some View {
        HStack {
            Text("Quantidade").font(.subheadline)
            Spacer()
            HStack(spacing: 15) {
                quantityButton(systemImage: "minus", background: Color.appFill, tint: .primary) {
                    store.send(.productQuantityChanged(id: draft.id, quantity: draft.quantity - 1))
                }
                Text("\(draft.quantity)")
                    .font(.body.weight(.heavy))
                    .monospacedDigit()
                    .frame(minWidth: 22)
                quantityButton(systemImage: "plus", background: Color.appAccentTint, tint: Color.appAccent) {
                    store.send(.productQuantityChanged(id: draft.id, quantity: draft.quantity + 1))
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }

    private var totalRow: some View {
        HStack {
            Text("Total").font(.subheadline.weight(.bold))
            Spacer()
            Text(Format.brl(draft.total))
                .font(.body.weight(.heavy))
                .monospacedDigit()
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(Color.appFillSubtle)
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
}

private struct ProductSavedView: View {
    let store: StoreOf<ScanFeature>

    private var saved: [ProductDraft] { store.selectedDrafts }

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

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .frame(maxWidth: 300)

            savedCard
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

    private var summary: String {
        guard let only = saved.first, saved.count == 1 else {
            return "Registramos **\(store.productUnitCount) itens** na sua compra de hoje."
        }
        return "Registramos **\(only.quantity)× \(only.item.description)** na sua compra de hoje."
    }

    private var savedCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                CapturedPhotoView(data: store.capturedPhoto, size: 44, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(saved.count == 1 ? (saved.first?.item.description ?? "") : "\(saved.count) produtos")
                        .font(.callout.weight(.bold))
                        .lineLimit(1)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(Format.brl(store.productTotal))
                    .font(.callout.weight(.heavy))
                    .monospacedDigit()
            }

            if saved.count > 1 {
                Divider().padding(.vertical, 11)
                VStack(spacing: 7) {
                    ForEach(saved) { draft in
                        HStack {
                            Text("\(draft.quantity)× \(draft.item.description)")
                                .font(.footnote)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Format.brl(draft.total))
                                .font(.footnote.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var subtitle: String {
        guard let only = saved.first, saved.count == 1 else { return "hoje" }
        return "\(only.item.category.label) · hoje"
    }
}

// MARK: - Photo rejected / failed

/// The AI declining to guess is a normal 200 result, so it reads as an outcome rather than an error.
private struct RejectedResultView: View {
    let store: StoreOf<ScanFeature>
    let rejected: PhotoScanRejected

    var body: some View {
        VStack(spacing: 0) {
            CapturedPhotoView(data: store.capturedPhoto, size: 96, cornerRadius: 22)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: rejected.reason.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(resultOrange, in: Circle())
                        .overlay(Circle().strokeBorder(Color.appElevated, lineWidth: 3))
                        .offset(x: 7, y: 7)
                }
                .padding(.top, 54).padding(.bottom, 22)

            Text(rejected.reason.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text(rejected.comment)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .frame(maxWidth: 300)

            Spacer()

            Button { store.send(.scanAgainTapped) } label: {
                PrimaryButtonLabel("Tentar outra foto")
            }

            Button("Escolher da galeria") { store.send(.choosePhotoTapped) }
                .font(.callout.weight(.medium))
                .tint(Color.appAccent)
                .padding(.top, 14)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 26)
    }
}

private struct PhotoErrorResultView: View {
    let store: StoreOf<ScanFeature>
    let failure: PhotoScanFailure

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: failure.symbol)
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
                PrimaryButtonLabel("Tentar novamente")
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

/// The photo the owner just sent to the AI, falling back to the placeholder when it cannot be decoded.
private struct CapturedPhotoView: View {
    var data: Data?
    var size: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                PhotoPlaceholder(size: size, cornerRadius: cornerRadius)
            }
            #else
            PhotoPlaceholder(size: size, cornerRadius: cornerRadius)
            #endif
        }
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

// MARK: - Entry (typed lançamento)

/// Everything the owner can type into a draft, so the keyboard's "Pronto" can let go of any of it.
private enum EntryField: Hashable {
    case store
    case description(EntryItemDraft.ID)
    case price(EntryItemDraft.ID)
}

/// The AI's reading of what the owner typed, as a draft they finish: the items it found, the date
/// it resolved, and where the money went. Nothing is saved until they say so.
private struct EntryDraftView: View {
    let store: StoreOf<ScanFeature>
    let draft: EntryDraft

    @FocusState private var focusedField: EntryField?

    private var dateBinding: Binding<Date> {
        Binding(
            get: { Format.date(fromISO: store.entryDate) ?? Date() },
            set: { store.send(.entryDateChanged(Format.iso(from: $0))) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Label("Rascunho da IA", systemImage: "sparkles")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.appAccent)
                    .padding(.top, 24)

                headerCard
                ForEach(store.entryItems) { item in
                    EntryItemCard(store: store, item: item, focusedField: $focusedField)
                }
                addItemButton
                if store.selectedEntryItems.count > 1 {
                    totalCard
                }
                if !draft.comment.isEmpty {
                    commentCard
                }
                if !store.trimmedEntryText.isEmpty {
                    typedTextCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Pronto") { focusedField = nil }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 9) {
                Button { store.send(.saveEntryTapped) } label: {
                    if store.entrySaving {
                        ProgressView()
                            .tint(Color.appAccentForeground)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AppGradient.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    } else {
                        PrimaryButtonLabel(saveTitle)
                    }
                }
                .disabled(store.entrySaving || !store.entrySavable)
                .opacity(!store.entrySaving && !store.entrySavable ? 0.5 : 1)

                Button("Descartar") { store.send(.discardEntryTapped) }
                    .font(.callout.weight(.medium))
                    .tint(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Color.appElevated)
        }
    }

    private var saveTitle: String {
        let selected = store.selectedEntryItems.count
        return selected > 1 ? "Salvar \(selected) itens no histórico" : "Salvar no histórico"
    }

    /// Where and when — the two things a purchase needs that are not an item.
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Format.brl(store.entryTotal))
                .font(.system(size: 34, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Color.heroInk)

            HStack(spacing: 8) {
                Image(systemName: "storefront")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.heroInkSecondary)
                TextField(
                    "",
                    text: Binding(
                        get: { store.entryStore },
                        set: { store.send(.entryStoreChanged($0)) }
                    ),
                    prompt: Text("Onde foi?").foregroundColor(Color.heroInkSecondary)
                )
                .font(.headline)
                .foregroundStyle(Color.heroInk)
                .tint(Color.heroInk)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .store)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 16)

            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.heroInkSecondary)
                DatePicker("Data", selection: dateBinding, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Color.heroInk)
                Spacer(minLength: 0)
                if let method = store.entryPaymentMethod {
                    Text(method)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.heroInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.16), in: Capsule())
                }
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppGradient.hero, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(hex: 0x0A6E66, alpha: 0.34), radius: 16, y: 6)
    }

    private var addItemButton: some View {
        Button { store.send(.addEntryItemTapped) } label: {
            Label("Adicionar item", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.appAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .card(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    private var totalCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Total do lançamento").font(.subheadline.weight(.bold))
                Text("\(store.selectedEntryItems.count) itens").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.brl(store.entryTotal))
                .font(.title3.weight(.heavy))
                .monospacedDigit()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .card(cornerRadius: 20)
    }

    private var commentCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.footnote)
                .foregroundStyle(Color.appAccent)
            Text(draft.comment)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .card(cornerRadius: 18)
    }

    private var typedTextCard: some View {
        Button { store.send(.toggleEntryText) } label: {
            VStack(spacing: 0) {
                HStack {
                    Text("O QUE VOCÊ ESCREVEU")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.4)
                    Spacer()
                    Image(systemName: store.entryTextExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.label3)
                }
                if store.entryTextExpanded {
                    Text(store.trimmedEntryText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                }
            }
            .padding(16)
            .card(cornerRadius: 20)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: store.entryTextExpanded)
    }
}

/// One line of the draft: what it is, which category it belongs to, and what it cost.
private struct EntryItemCard: View {
    let store: StoreOf<ScanFeature>
    let item: EntryItemDraft
    let focusedField: FocusState<EntryField?>.Binding

    var body: some View {
        VStack(spacing: 0) {
            itemHeader
            if item.selected {
                Divider().padding(.leading, 16)
                categoryRow
                Divider().padding(.leading, 16)
                priceRow
                Divider().padding(.leading, 16)
                quantityRow
                totalRow
            }
        }
        .card(cornerRadius: 20)
    }

    private var itemHeader: some View {
        HStack(spacing: 12) {
            Button { store.send(.entryItemSelectionToggled(id: item.id)) } label: {
                Image(systemName: item.selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(item.selected ? Color.appAccent : Color.label3)
            }
            .buttonStyle(.plain)

            TextField(
                "",
                text: Binding(
                    get: { item.description },
                    set: { store.send(.entryItemDescriptionChanged(id: item.id, description: $0)) }
                ),
                prompt: Text("O que foi?").foregroundColor(Color.label3)
            )
            .font(.callout.weight(.heavy))
            .foregroundStyle(item.selected ? .primary : .secondary)
            .tint(Color.appAccent)
            .textFieldStyle(.plain)
            .focused(focusedField, equals: .description(item.id))
        }
        .padding(16)
    }

    private var categoryRow: some View {
        HStack {
            Text("Categoria").font(.subheadline)
            Spacer()
            Picker(
                "Categoria",
                selection: Binding(
                    get: { item.category },
                    set: { store.send(.entryItemCategoryChanged(id: item.id, category: $0)) }
                )
            ) {
                ForEach(Category.allCases) { category in
                    Text(category.label).tag(category)
                }
            }
            .pickerStyle(.menu)
            .tint(Color.appAccent)
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 5)
    }

    private var priceRow: some View {
        HStack {
            Text("Preço").font(.subheadline)
            Spacer()
            TextField(
                "R$ 0,00",
                value: Binding(
                    get: { item.unitPrice },
                    set: { store.send(.entryItemPriceChanged(id: item.id, price: $0)) }
                ),
                format: .currency(code: "BRL").locale(Locale(identifier: "pt_BR"))
            )
            .multilineTextAlignment(.trailing)
            .font(.subheadline.weight(.bold))
            .focused(focusedField, equals: .price(item.id))
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
            .frame(maxWidth: 120)
            Text("/un").font(.caption).foregroundStyle(Color.label3)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private var quantityRow: some View {
        HStack {
            Text("Quantidade").font(.subheadline)
            Spacer()
            HStack(spacing: 15) {
                quantityButton(systemImage: "minus", background: Color.appFill, tint: .primary) {
                    store.send(.entryItemQuantityChanged(id: item.id, quantity: item.quantity - 1))
                }
                Text("\(item.quantity)")
                    .font(.body.weight(.heavy))
                    .monospacedDigit()
                    .frame(minWidth: 22)
                quantityButton(systemImage: "plus", background: Color.appAccentTint, tint: Color.appAccent) {
                    store.send(.entryItemQuantityChanged(id: item.id, quantity: item.quantity + 1))
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }

    private var totalRow: some View {
        HStack {
            Text("Total").font(.subheadline.weight(.bold))
            Spacer()
            Text(Format.brl(item.total))
                .font(.body.weight(.heavy))
                .monospacedDigit()
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(Color.appFillSubtle)
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
}

private struct EntrySavedView: View {
    let store: StoreOf<ScanFeature>
    let purchase: Purchase

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(resultGreen, in: Circle())
                .shadow(color: resultGreen.opacity(0.4), radius: 13, y: 5)
                .padding(.top, 44).padding(.bottom, 20)

            Text("Lançamento salvo")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .frame(maxWidth: 300)

            Button { store.send(.showInHistoryTapped) } label: {
                HStack(spacing: 13) {
                    StoreAvatar(name: purchase.store.name, size: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(purchase.store.name)
                            .font(.callout.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(Format.dayMonth(fromISO: purchase.date)) · \(purchase.totals.itemCount) itens")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(Format.brl(purchase.totals.totalPaid))
                        .font(.callout.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                .padding(14)
                .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 24)

            Spacer()

            Button { store.send(.showInHistoryTapped) } label: {
                PrimaryButtonLabel("Ver no histórico")
            }

            Button("Lançar outro") { store.send(.discardEntryTapped) }
                .font(.callout.weight(.medium))
                .tint(Color.appAccent)
                .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 26)
    }

    private var summary: String {
        guard let only = purchase.items.first, purchase.items.count == 1 else {
            return "Registramos **\(purchase.totals.itemCount) itens** em \(Format.dayMonthYear(purchase.date))."
        }
        return "Registramos **\(only.description)** em \(only.category.label), no dia \(Format.dayMonthYear(purchase.date))."
    }
}

private struct EntryErrorResultView: View {
    let store: StoreOf<ScanFeature>
    let failure: EntryScanFailure

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: failure.symbol)
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

            // The description survives a failed reading, so this lands back on what the owner wrote.
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
    if case let .product(identified) = phase {
        state.productDrafts = IdentifiedArray(
            uniqueElements: identified.items.enumerated().map { index, item in
                ProductDraft(
                    id: index,
                    item: item,
                    quantity: item.quantity ?? 1,
                    unitPrice: item.unitPrice ?? 8.90
                )
            }
        )
    }
    return Store(initialState: state) { ScanFeature() }
}

@MainActor
private func entryResultStore(phase: ScanFeature.State.Phase) -> StoreOf<ScanFeature> {
    var state = ScanFeature.State()
    state.scanMode = .entry
    state.phase = phase
    state.entryText = MockData.entryDescription
    if case let .entry(draft) = phase {
        state.entryDate = draft.date
        state.entryStore = draft.store ?? draft.items.first?.description ?? ""
        state.entryPaymentMethod = draft.paymentMethod
        state.entryItems = IdentifiedArray(
            uniqueElements: draft.items.enumerated().map { index, item in
                EntryItemDraft(
                    id: index,
                    description: item.description,
                    category: item.category,
                    quantity: item.quantity ?? 1,
                    unitPrice: item.unitPrice ?? 0
                )
            }
        )
    }
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

#Preview("QR recusado") {
    ScanResultView(store: scanResultStore(phase: .failure(.qrRejected)))
}

#Preview("Captcha") {
    ScanResultView(
        store: scanResultStore(phase: .captcha(CaptchaChallenge(challengeId: "preview", image: Data())))
    )
}

#Preview("Processando") {
    ScanResultView(store: scanResultStore(phase: .processing))
}

#Preview("Itens identificados") {
    ScanResultView(store: scanResultStore(phase: .product(MockData.photoScanIdentified)))
}

#Preview("Item identificado") {
    ScanResultView(store: scanResultStore(phase: .product(MockData.photoScanSingleItem)))
}

#Preview("Itens adicionados") {
    ScanResultView(store: scanResultStore(phase: .product(MockData.photoScanIdentified), productSaved: true))
}

#Preview("Foto recusada") {
    ScanResultView(
        store: scanResultStore(
            phase: .rejected(PhotoScanRejected(
                reason: .unclearImage,
                comment: "A foto está desfocada demais para identificar o produto."
            ))
        )
    )
}

#Preview("Erro da IA") {
    ScanResultView(store: scanResultStore(phase: .photoFailure(.aiUnavailable)))
}

#Preview("Rascunho") {
    ScanResultView(store: entryResultStore(phase: .entry(MockData.entryDraft)))
}

#Preview("Rascunho com vários itens") {
    ScanResultView(store: entryResultStore(phase: .entry(MockData.entryDraftMultiple)))
}

#Preview("Lançamento salvo") {
    ScanResultView(
        store: entryResultStore(phase: .entrySaved(MockData.manualPurchase(MockData.entrySaveRequest)))
    )
}

#Preview("Erro do lançamento") {
    ScanResultView(store: entryResultStore(phase: .entryFailure(.notAnEntry)))
}
