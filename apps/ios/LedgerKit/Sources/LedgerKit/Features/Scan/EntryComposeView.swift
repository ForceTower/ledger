import ComposableArchitecture
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// What the owner puts together before the AI reads it: their own account of what they spent, and —
/// when they have one — a print backing it up. The words alone are enough.
struct EntryComposeView: View {
    @Bindable var store: StoreOf<ScanFeature>

    @FocusState private var textFocused: Bool

    private var textBinding: Binding<String> {
        Binding(
            get: { store.entryText },
            set: { store.send(.entryTextChanged($0)) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Novo lançamento")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(.white)

                Text("Descreva o gasto do seu jeito. A IA monta um rascunho com valor, categoria e data — você confere os itens antes de salvar.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.top, 7)

                HStack {
                    Text("O QUE VOCÊ GASTOU")
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.46))
                    Spacer()
                    pasteButton
                }
                .padding(.top, 20)

                textBox
                    .padding(.top, 9)

                attachBox
                    .padding(.top, 14)

                Button { store.send(.interpretEntryTapped) } label: {
                    Text("Criar rascunho com IA")
                        .font(.headline)
                        .foregroundStyle(store.entryReady ? Color.appAccentForeground : .white.opacity(0.38))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(
                                    store.entryReady
                                        ? AnyShapeStyle(AppGradient.accent)
                                        : AnyShapeStyle(Color.white.opacity(0.1))
                                )
                        }
                }
                .buttonStyle(.plain)
                .disabled(!store.entryReady)
                .padding(.top, 20)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .animation(.easeInOut(duration: 0.2), value: store.entryImage == nil)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Pronto") { textFocused = false }
            }
        }
    }

    // MARK: - Description

    private var pasteButton: some View {
        Button {
            if store.trimmedEntryText.isEmpty {
                store.send(.entryTextChanged(Self.pasteboardText() ?? ""))
            } else {
                store.send(.entryTextChanged(""))
            }
        } label: {
            Label(
                store.trimmedEntryText.isEmpty ? "Colar" : "Limpar",
                systemImage: store.trimmedEntryText.isEmpty ? "doc.on.clipboard" : "xmark.circle"
            )
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.appAccent)
        }
        .buttonStyle(.plain)
    }

    private var textBox: some View {
        TextField(
            "",
            text: textBinding,
            prompt: Text("Ex.: 37,00 de transporte no dia 24 de julho")
                .foregroundColor(.white.opacity(0.42)),
            axis: .vertical
        )
        .lineLimit(3...8)
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.88))
        .tint(Color.appAccent)
        .textFieldStyle(.plain)
        .focused($textFocused)
        .padding(14)
        .frame(minHeight: 108, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(store.trimmedEntryText.isEmpty ? 0.04 : 0.09))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    .white.opacity(store.trimmedEntryText.isEmpty ? 0.26 : 0.18),
                    style: StrokeStyle(
                        lineWidth: store.trimmedEntryText.isEmpty ? 1.5 : 1,
                        dash: store.trimmedEntryText.isEmpty ? [6, 5] : []
                    )
                )
        }
    }

    // MARK: - Print

    private var attachBox: some View {
        Button { store.send(.choosePhotoTapped) } label: {
            Group {
                if let image = store.entryImage {
                    attachedPrint(image)
                } else {
                    emptyPrint
                }
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(store.entryImage == nil ? 0.04 : 0.09))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        .white.opacity(store.entryImage == nil ? 0.2 : 0.18),
                        style: StrokeStyle(
                            lineWidth: 1,
                            dash: store.entryImage == nil ? [6, 5] : []
                        )
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyPrint: some View {
        HStack(spacing: 10) {
            Image(systemName: "paperclip")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text("Anexar print (opcional)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Comprovante, nota ou etiqueta de preço")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 0)
        }
    }

    private func attachedPrint(_ data: Data) -> some View {
        HStack(spacing: 13) {
            printThumbnail(data)

            VStack(alignment: .leading, spacing: 3) {
                Text("Print anexado")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(Self.printDetails(data))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer(minLength: 8)

            Text("Trocar")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private func printThumbnail(_ data: Data) -> some View {
        Group {
            #if canImport(UIKit)
            if let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.white.opacity(0.12)
            }
            #else
            Color.white.opacity(0.12)
            #endif
        }
        .frame(width: 40, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button { store.send(.entryImageCleared) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.black.opacity(0.8))
                    .frame(width: 18, height: 18)
                    .background(.white.opacity(0.9), in: Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 7, y: -7)
        }
    }

    /// "1,2 MB · 1179 × 2556" — enough for the owner to tell one screenshot from another.
    private static func printDetails(_ data: Data) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        #if canImport(UIKit)
        if let image = UIImage(data: data) {
            let width = Int(image.size.width * image.scale)
            let height = Int(image.size.height * image.scale)
            return "\(size) · \(width) × \(height)"
        }
        #endif
        return size
    }

    private static func pasteboardText() -> String? {
        #if canImport(UIKit)
        return UIPasteboard.general.string
        #else
        return nil
        #endif
    }
}

@MainActor
private func composeStore(text: String = "") -> StoreOf<ScanFeature> {
    var state = ScanFeature.State()
    state.scanMode = .entry
    state.entryText = text
    return Store(initialState: state) { ScanFeature() }
}

#Preview("Vazio") {
    ZStack {
        Color(hex: 0x080C0D).ignoresSafeArea()
        EntryComposeView(store: composeStore()).padding(.horizontal, 20)
    }
}

#Preview("Com descrição") {
    ZStack {
        Color(hex: 0x080C0D).ignoresSafeArea()
        EntryComposeView(store: composeStore(text: MockData.entryDescription)).padding(.horizontal, 20)
    }
}
