import Charts
import ComposableArchitecture
import SwiftUI

struct InsightsView: View {
    let store: StoreOf<InsightsFeature>

    private struct MonthBar: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let highlighted: Bool
    }

    private struct Slice: Identifiable {
        let category: Category?
        let label: String
        let percent: Double

        var id: String { label }
        var color: Color { category?.color ?? .label3 }
    }

    private let months: [MonthBar] = [
        .init(label: "jan", value: 1310, highlighted: false),
        .init(label: "fev", value: 1640, highlighted: false),
        .init(label: "mar", value: 1842, highlighted: true),
        .init(label: "abr", value: 980, highlighted: false),
        .init(label: "mai", value: 560, highlighted: false),
        .init(label: "jun", value: 340, highlighted: false),
    ]

    private let slices: [Slice] = [
        .init(category: .grocery, label: "Mercearia", percent: 35),
        .init(category: .meat, label: "Carnes", percent: 26),
        .init(category: .produce, label: "Hortifrúti", percent: 17),
        .init(category: .cleaning, label: "Limpeza", percent: 12),
        .init(category: nil, label: "Outros", percent: 10),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Insights")
                    .font(.largeTitle.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                donutCard
                monthsCard
                highlightCard
            }
            .padding(16)
        }
        .background(Color.appBackground)
    }

    private var donutCard: some View {
        HStack(spacing: 20) {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Fatia", slice.percent),
                    innerRadius: .ratio(0.72),
                    angularInset: 1.5
                )
                .cornerRadius(2)
                .foregroundStyle(slice.color)
            }
            .chartLegend(.hidden)
            .frame(width: 132, height: 132)
            .overlay {
                VStack(spacing: 1) {
                    Text("Total")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("R$ 1.842")
                        .font(.headline.weight(.heavy))
                }
            }

            VStack(spacing: 9) {
                ForEach(slices) { slice in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(slice.color)
                            .frame(width: 9, height: 9)
                        Text(slice.label)
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(Int(slice.percent))%")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .card(cornerRadius: 22)
    }

    private var monthsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("ÚLTIMOS 6 MESES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
                Spacer()
                Label("12% vs. fev", systemImage: "arrowtriangle.up.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(hex: 0xE5484D))
            }

            Chart(months) { month in
                BarMark(
                    x: .value("Mês", month.label),
                    y: .value("Gasto", month.value)
                )
                .foregroundStyle(
                    month.highlighted
                        ? AnyShapeStyle(AppGradient.accent)
                        : AnyShapeStyle(Color.appAccentTint)
                )
                .cornerRadius(7)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel(anchor: .top) }
            }
            .frame(height: 130)
            .padding(.top, 18)
        }
        .padding(18)
        .card(cornerRadius: 22)
    }

    private var highlightCard: some View {
        HStack(spacing: 14) {
            Text("💡")
                .font(.system(size: 22))
                .frame(width: 44, height: 44)
                .background(Color.appAccentTint, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Carnes subiram 34%")
                    .font(.subheadline.weight(.bold))
                Text("Você gastou R$ 124 a mais que em fevereiro nessa categoria.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .card(cornerRadius: 22)
    }
}

#Preview {
    InsightsView(store: Store(initialState: InsightsFeature.State()) { InsightsFeature() })
}
