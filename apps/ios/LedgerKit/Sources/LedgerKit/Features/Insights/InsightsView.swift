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

    private let months: [MonthBar] = [
        .init(label: "jan", value: 1310, highlighted: false),
        .init(label: "fev", value: 1640, highlighted: false),
        .init(label: "mar", value: 1842, highlighted: true),
        .init(label: "abr", value: 980, highlighted: false),
        .init(label: "mai", value: 560, highlighted: false),
        .init(label: "jun", value: 340, highlighted: false),
    ]

    private let breakdown: [(category: Category, amount: Int, fraction: Double)] = [
        (.grocery, 642, 0.78),
        (.meat, 488, 0.60),
        (.produce, 311, 0.40),
        (.cleaning, 224, 0.28),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Insights")
                    .font(.largeTitle.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                spendingCard
                breakdownCard
            }
            .padding(16)
        }
        .background(Color.appBackground)
    }

    private var spendingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Gasto em março").font(.footnote).foregroundStyle(.secondary)
            Text(Format.brl(1842.30))
                .font(.system(size: 38, weight: .bold))
                .monospacedDigit()
            HStack(spacing: 6) {
                Label("12%", systemImage: "arrowtriangle.up.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(hex: 0xE5484D))
                Text("vs. fevereiro").font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            Chart(months) { month in
                BarMark(
                    x: .value("Mês", month.label),
                    y: .value("Gasto", month.value)
                )
                .foregroundStyle(month.highlighted ? Color.appAccent : Color.appAccentTint)
                .cornerRadius(6)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel(anchor: .top) }
            }
            .frame(height: 120)
            .padding(.top, 16)
        }
        .padding(18)
        .card()
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardSectionHeader("Para onde foi")
            ForEach(breakdown, id: \.category) { row in
                VStack(spacing: 5) {
                    HStack {
                        Text(row.category.label).font(.subheadline)
                        Spacer()
                        Text(Format.brl(Double(row.amount))).font(.subheadline).foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        Capsule().fill(Color.appFill)
                            .overlay(alignment: .leading) {
                                Capsule().fill(row.category.color)
                                    .frame(width: geo.size.width * row.fraction)
                            }
                    }
                    .frame(height: 7)
                }
            }
        }
        .padding(17)
        .card()
    }
}

#Preview {
    InsightsView(store: Store(initialState: InsightsFeature.State()) { InsightsFeature() })
}
