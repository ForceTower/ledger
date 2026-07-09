import SwiftUI

struct CategoryProportionBar: View {
    let segments: [(color: Color, weight: Double)]
    var height: CGFloat = 3
    var spacing: CGFloat = 0

    private var totalWeight: Double { max(segments.reduce(0) { $0 + $1.weight }, 1) }

    var body: some View {
        GeometryReader { geo in
            let gaps = spacing * CGFloat(max(segments.count - 1, 0))
            let usable = max(geo.size.width - gaps, 0)
            HStack(spacing: spacing) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Capsule()
                        .fill(segment.color)
                        .frame(width: usable * (segment.weight / totalWeight))
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

extension PurchaseSummary {
    var dominantCategory: Category? {
        categories.max { $0.value < $1.value }?.key
    }

    var barSegments: [(color: Color, weight: Double)] {
        categorySegments.map { (color: $0.category.color, weight: Double($0.count)) }
    }
}

struct StoreAvatar: View {
    let name: String
    var tint: Color = .appAccent
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(tint.opacity(0.16))
            .frame(width: size, height: size)
            .overlay {
                Text(String(name.first.map(String.init) ?? "?"))
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(tint)
            }
    }
}

struct CardSectionHeader: View {
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(Color.label3)
            }
        }
    }
}

struct InfoChip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) { content }
            .font(.footnote)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color.appFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

extension View {
    func card(cornerRadius: CGFloat = 18) -> some View {
        background(Color.appElevated, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 9, y: 3)
    }

    func insetGroupedListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.automatic)
        #endif
    }
}

struct PrimaryButtonLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color.appAccentForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(AppGradient.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: Color.appAccent.opacity(0.25), radius: 11, y: 4)
    }
}

struct CountUpText: View {
    let value: Double
    var font: Font = .system(size: 36, weight: .bold)

    @State private var current: Double = 0

    var body: some View {
        Text(Format.brl(current))
            .font(font)
            .monospacedDigit()
            .task(id: value) { await animate() }
    }

    private func animate() async {
        let steps = 28
        let total = 0.7
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            current = value * (1 - pow(1 - t, 3))
            try? await Task.sleep(for: .seconds(total / Double(steps)))
        }
        current = value
    }
}

#Preview("CategoryProportionBar") {
    CategoryProportionBar(
        segments: [
            (color: Category.produce.color, weight: 5),
            (color: Category.meat.color, weight: 3),
            (color: Category.grocery.color, weight: 2),
        ],
        height: 8
    )
    .padding()
}

#Preview("StoreAvatar") {
    HStack(spacing: 16) {
        StoreAvatar(name: "Pão de Açúcar")
        StoreAvatar(name: "Extra", tint: Category.meat.color)
        StoreAvatar(name: "Carrefour", tint: Category.beverages.color, size: 56)
    }
    .padding()
}

#Preview("CardSectionHeader") {
    VStack(spacing: 16) {
        CardSectionHeader("Itens")
        CardSectionHeader("Categorias", trailing: "12 itens")
    }
    .padding()
}

#Preview("InfoChip") {
    HStack(spacing: 8) {
        InfoChip {
            Image(systemName: "calendar")
            Text("29 jun")
        }
        InfoChip {
            Image(systemName: "creditcard")
            Text("Crédito")
        }
        InfoChip { Text("8 itens") }
    }
    .padding()
}

#Preview("CountUpText") {
    CountUpText(value: 1234.56)
        .padding()
}
