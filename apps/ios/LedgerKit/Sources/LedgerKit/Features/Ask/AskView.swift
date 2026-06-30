import ComposableArchitecture
import SwiftUI

/// Ask — a "Em breve" preview of natural-language Q&A over the dataset. Static
/// transcript with a (disabled) composer pinned above the tab bar.
struct AskView: View {
    let store: StoreOf<AskFeature>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Perguntar")
                    .font(.largeTitle.weight(.bold))
                    .padding(.bottom, 4)

                assistantBubble(
                    "Oi! Posso responder sobre suas compras — gastos, categorias, comparações entre meses."
                )

                HStack(spacing: 8) {
                    suggestion("Quanto gastei em carnes?")
                    suggestion("Março vs. fevereiro")
                }

                userBubble("Quanto gastei em carnes esse mês?")

                answerBubble
            }
            .padding(16)
        }
        .background(Color.appBackground)
        .safeAreaInset(edge: .bottom) { composer }
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

    private func assistantBubble(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            avatar
            Text(text)
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(
                    Color.appElevated,
                    in: UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16, style: .continuous)
                )
                .frame(maxWidth: 260, alignment: .leading)
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

    private var answerBubble: some View {
        HStack(alignment: .top, spacing: 9) {
            avatar
            VStack(alignment: .leading, spacing: 0) {
                Text("Em março você gastou ") + Text("R$ 488,30").bold() + Text(" em carnes — 26% do total, em 4 compras.")
                Capsule().fill(Color.appFill)
                    .frame(height: 7)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Category.meat.color).frame(width: 150)
                    }
                    .padding(.top, 10)
                Text("Atacadão foi a maior fatia (R$ 208,75).")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                Color.appElevated,
                in: UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16, style: .continuous)
            )
            .frame(maxWidth: 270, alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    private func suggestion(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.appAccent)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.appAccentTint, in: Capsule())
    }

    private var composer: some View {
        HStack(spacing: 9) {
            Text("Pergunte sobre seus gastos…")
                .foregroundStyle(Color.label3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Color.appFill, in: Capsule())
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.appAccentForeground)
                .frame(width: 40, height: 40)
                .background(Color.appAccent, in: Circle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

#Preview {
    AskView(store: Store(initialState: AskFeature.State()) { AskFeature() })
}
