import ComposableArchitecture
import SwiftUI

struct AskView: View {
    @Bindable var store: StoreOf<AskFeature>

    private static let suggestions = [
        "Quanto gastei em carnes este mês?",
        "Compare março com fevereiro",
        "Onde o café estava mais barato?",
    ]

    var body: some View {
        NavigationStack {
            conversation
                .background(Color.appBackground)
                .navigationTitle("Perguntar")
                .toolbar {
                    if !store.transcript.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Nova conversa", systemImage: "square.and.pencil") {
                                store.send(.newConversationTapped)
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) { composer }
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if store.transcript.isEmpty {
                        emptyState
                    }
                    ForEach(store.transcript) { message in
                        bubble(for: message)
                    }
                    if store.isConsulting {
                        statusCaption("Consultando seus dados…")
                    }
                    if let error = store.errorMessage {
                        errorBanner(error)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.transcript) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
        }
    }

    private static let bottomAnchor = "conversation-bottom"

    @ViewBuilder
    private var emptyState: some View {
        assistantBubble {
            Text("Oi! Posso responder sobre suas compras — gastos, categorias, comparações entre meses e preços por produto.")
        }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.suggestions, id: \.self) { text in
                Button {
                    store.send(.suggestionTapped(text))
                } label: {
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.appAccentTint, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 39)
    }

    @ViewBuilder
    private func bubble(for message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            userBubble(message.text)
        case .assistant:
            assistantBubble {
                if message.text.isEmpty {
                    TypingIndicator()
                } else {
                    Text(.init(message.text))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var avatar: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
                LinearGradient(colors: [Color.appAccent, Color(hex: 0x0A615A)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Circle()
            )
    }

    private func assistantBubble(@ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 9) {
            avatar
            content()
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(
                    Color.appElevated,
                    in: UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16, style: .continuous)
                )
                .frame(maxWidth: 290, alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .font(.callout)
                .foregroundStyle(Color.appAccentForeground)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(
                    Color.appAccent,
                    in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 5, style: .continuous)
                )
        }
    }

    private func statusCaption(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.leading, 39)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Tentar novamente") {
                store.send(.retryTapped)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.appAccent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 9) {
            TextField("Pergunte sobre seus gastos…", text: $store.composer.sending(\.composerChanged), axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .onSubmit { store.send(.sendTapped) }

            if store.isStreaming {
                Button {
                    store.send(.stopTapped)
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.appAccentForeground)
                        .frame(width: 40, height: 40)
                        .background(Color.appAccent, in: Circle())
                }
            } else {
                Button {
                    store.send(.sendTapped)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.appAccentForeground)
                        .frame(width: 40, height: 40)
                        .background(Color.appAccent, in: Circle())
                }
                .disabled(store.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// Three pulsing dots while the answer has not started streaming yet.
private struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.label3)
                    .frame(width: 6, height: 6)
                    .opacity(animating ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(index) * 0.16),
                        value: animating
                    )
            }
        }
        .padding(.vertical, 4)
        .onAppear { animating = true }
    }
}

#Preview {
    AskView(store: Store(initialState: AskFeature.State()) { AskFeature() })
}
