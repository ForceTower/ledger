import ComposableArchitecture
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// What the owner puts together before the AI reads it: the screenshot the bank produced, the text
/// they copied out of it, or both. Either one on its own is enough to interpret.
struct TransferComposeView: View {
    @Bindable var store: StoreOf<ScanFeature>

    @FocusState private var textFocused: Bool

    private var textBinding: Binding<String> {
        Binding(
            get: { store.transferText },
            set: { store.send(.transferTextChanged($0)) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Comprovante de transferência")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(.white)

                Text("Anexe o print e cole o texto. A IA entende o valor, para quem foi e a data — e registra no histórico.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.top, 7)

                attachBox
                    .padding(.top, 20)

                HStack {
                    Text("TEXTO DO COMPROVANTE")
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.46))
                    Spacer()
                    pasteButton
                }
                .padding(.top, 18)

                textBox
                    .padding(.top, 9)

                Button { store.send(.interpretTransferTapped) } label: {
                    Text("Interpretar com IA")
                        .font(.headline)
                        .foregroundStyle(store.transferReady ? Color.appAccentForeground : .white.opacity(0.38))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(
                                    store.transferReady
                                        ? AnyShapeStyle(AppGradient.accent)
                                        : AnyShapeStyle(Color.white.opacity(0.1))
                                )
                        }
                }
                .buttonStyle(.plain)
                .disabled(!store.transferReady)
                .padding(.top, 20)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .animation(.easeInOut(duration: 0.2), value: store.transferImage == nil)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Pronto") { textFocused = false }
            }
        }
    }

    // MARK: - Print

    private var attachBox: some View {
        Button { store.send(.choosePhotoTapped) } label: {
            Group {
                if let image = store.transferImage {
                    attachedPrint(image)
                } else {
                    emptyPrint
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(store.transferImage == nil ? 0.04 : 0.09))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        .white.opacity(store.transferImage == nil ? 0.26 : 0.18),
                        style: StrokeStyle(
                            lineWidth: store.transferImage == nil ? 1.5 : 1,
                            dash: store.transferImage == nil ? [6, 5] : []
                        )
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyPrint: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text("Anexar print da transferência")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
            Text("PNG · JPG · captura de tela")
                .font(.system(.caption2, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.vertical, 10)
    }

    private func attachedPrint(_ data: Data) -> some View {
        HStack(spacing: 13) {
            printThumbnail(data)

            VStack(alignment: .leading, spacing: 3) {
                Text("Print da transferência")
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
        .frame(width: 46, height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button { store.send(.transferImageCleared) } label: {
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

    // MARK: - Text

    private var pasteButton: some View {
        Button {
            if store.trimmedTransferText.isEmpty {
                store.send(.transferTextChanged(Self.pasteboardText() ?? ""))
            } else {
                store.send(.transferTextChanged(""))
            }
        } label: {
            Label(
                store.trimmedTransferText.isEmpty ? "Colar" : "Limpar",
                systemImage: store.trimmedTransferText.isEmpty ? "doc.on.clipboard" : "xmark.circle"
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
            prompt: Text("Cole aqui o texto do comprovante — valor, destinatário, data. Também vale a mensagem que você recebeu do banco.")
                .foregroundColor(.white.opacity(0.42)),
            axis: .vertical
        )
        .lineLimit(4...10)
        // Prose while it is a hint, monospaced once it holds what the bank wrote.
        .font(store.transferText.isEmpty ? .subheadline : .system(.footnote, design: .monospaced))
        .foregroundStyle(.white.opacity(0.88))
        .tint(Color.appAccent)
        .textFieldStyle(.plain)
        .focused($textFocused)
        .padding(14)
        .frame(minHeight: 120, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(store.trimmedTransferText.isEmpty ? 0.04 : 0.09))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    .white.opacity(store.trimmedTransferText.isEmpty ? 0.26 : 0.18),
                    style: StrokeStyle(
                        lineWidth: store.trimmedTransferText.isEmpty ? 1.5 : 1,
                        dash: store.trimmedTransferText.isEmpty ? [6, 5] : []
                    )
                )
        }
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
    state.scanMode = .transfer
    state.transferText = text
    return Store(initialState: state) { ScanFeature() }
}

#Preview("Vazio") {
    ZStack {
        Color(hex: 0x080C0D).ignoresSafeArea()
        TransferComposeView(store: composeStore()).padding(.horizontal, 20)
    }
}

#Preview("Com texto") {
    ZStack {
        Color(hex: 0x080C0D).ignoresSafeArea()
        TransferComposeView(store: composeStore(text: MockData.transferReceiptText)).padding(.horizontal, 20)
    }
}
