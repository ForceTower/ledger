import SwiftUI

/// A horizontal proportion bar split by category color — the recurring "where
/// the money went" glyph on history rows and the result sheet.
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

/// Circular store badge with the store's initial, tinted by its top category.
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

/// The "Em breve" badge used on not-yet-built tabs.
struct ComingSoonBadge: View {
    var body: some View {
        Text("Em breve")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.appAccent)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Color.appAccentTint, in: Capsule())
    }
}

/// Uppercase caption header used inside custom cards.
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

/// Small rounded chip used for metadata (date, payment method, item count).
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
    /// Wraps content in an elevated rounded card matching the design surfaces.
    func card(cornerRadius: CGFloat = 18) -> some View {
        background(Color.appElevated, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Inset-grouped list on iOS; the closest available style elsewhere.
    func insetGroupedListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.automatic)
        #endif
    }
}

/// A flow layout that wraps its subviews onto new lines — used for category
/// legends and chip rows.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// Counts up to `value` on appear, like the prototype's animated total.
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
