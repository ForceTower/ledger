import Charts
import ComposableArchitecture
import SwiftUI

struct InsightsView: View {
    let store: StoreOf<InsightsFeature>

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Insights")
                    .font(.largeTitle.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                if let snapshot = store.snapshot {
                    DonutCard(snapshot: snapshot)
                    MonthsCard(snapshot: snapshot)
                    if let highlight = snapshot.highlight {
                        HighlightCard(highlight: highlight)
                    }
                    statsGrid(snapshot)
                    if let radar = snapshot.priceRadar {
                        PriceRadarCard(radar: radar, window: snapshot.months)
                    }
                    if !snapshot.topStores.isEmpty {
                        TopStoresCard(stores: snapshot.topStores)
                    }
                    WeekdayCard(weekdays: snapshot.weekdays, topWeekdayName: snapshot.topWeekdayName)
                }
            }
            .padding(16)
        }
        .background(Color.appBackground)
        .overlay {
            if !store.didLoad {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground)
            } else if store.isEmpty {
                EmptyInsightsView { store.send(.scanFirstTapped) }
            }
        }
        .task { store.send(.onAppear) }
    }

    private func statsGrid(_ snapshot: InsightsSnapshot) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible())], spacing: 11) {
            StatTile(
                title: "Média por compra",
                value: Format.brl(snapshot.averagePerPurchase),
                caption: "\(snapshot.purchaseCount) compras no mês"
            )
            StatTile(
                title: "Economia",
                value: Format.brl(snapshot.savings),
                caption: "em descontos e ofertas",
                valueColor: .insightsGreen
            )
            StatTile(
                title: "Maior compra",
                value: snapshot.biggest.map { Format.brl($0.amount) } ?? "—",
                caption: snapshot.biggest.map { "\($0.store) · \(Format.dayMonth(fromISO: $0.date))" } ?? ""
            )
            StatTile(
                title: "Ritmo diário",
                value: Format.brl(snapshot.dailyPace),
                caption: "≈ por dia em \(snapshot.monthName)"
            )
        }
    }
}

extension Color {
    fileprivate static let insightsGreen = Color.adaptive(light: Color(hex: 0x28A745), dark: Color(hex: 0x4CC764))
    fileprivate static let insightsRed = Color.adaptive(light: Color(hex: 0xE5484D), dark: Color(hex: 0xF26B63))
}

/// Red when spending moved up, green when it moved down.
private struct TrendLabel: View {
    let percent: Int
    let suffix: String

    var body: some View {
        Label("\(abs(percent))% \(suffix)", systemImage: percent > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(percent > 0 ? Color.insightsRed : Color.insightsGreen)
    }
}

// MARK: - Donut

private struct DonutCard: View {
    let snapshot: InsightsSnapshot

    var body: some View {
        HStack(spacing: 20) {
            Chart(snapshot.slices) { slice in
                SectorMark(
                    angle: .value("Fatia", slice.amount),
                    innerRadius: .ratio(0.72),
                    angularInset: 1.5
                )
                .cornerRadius(2)
                .foregroundStyle(slice.category?.color ?? .label3)
            }
            .chartLegend(.hidden)
            .frame(width: 132, height: 132)
            .overlay {
                VStack(spacing: 1) {
                    Text("Total")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(Format.brlWhole(snapshot.total))
                        .font(.headline.weight(.heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: 80)
                }
            }

            VStack(spacing: 9) {
                ForEach(snapshot.slices) { slice in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(slice.category?.color ?? .label3)
                            .frame(width: 9, height: 9)
                        Text(slice.label)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(slice.percent)%")
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
}

// MARK: - Last 6 months

private struct MonthsCard: View {
    let snapshot: InsightsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                CardSectionHeader("Últimos 6 meses")
                if let trend = snapshot.trendPercent, trend != 0, let previous = snapshot.previousMonthLabel {
                    TrendLabel(percent: trend, suffix: "vs. \(previous)")
                }
            }

            Chart(snapshot.months) { month in
                BarMark(
                    x: .value("Mês", month.label),
                    y: .value("Gasto", month.total)
                )
                .foregroundStyle(
                    month.isReference
                        ? AnyShapeStyle(AppGradient.accent)
                        : AnyShapeStyle(Color.appAccentTint)
                )
                .cornerRadius(7)
            }
            .chartXScale(domain: snapshot.months.map(\.label))
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
}

// MARK: - Highlight

private struct HighlightCard: View {
    let highlight: InsightsSnapshot.Highlight

    private var title: String {
        let verb = switch (highlight.category.pluralLabel, highlight.rose) {
        case (true, true): "subiram"
        case (true, false): "caíram"
        case (false, true): "subiu"
        case (false, false): "caiu"
        }
        return "\(highlight.category.label) \(verb) \(abs(highlight.percent))%"
    }

    private var detail: String {
        let direction = highlight.rose ? "a mais" : "a menos"
        return "Você gastou \(Format.brlWhole(abs(highlight.delta))) \(direction) que em "
            + "\(highlight.previousMonthName) nessa categoria."
    }

    var body: some View {
        HStack(spacing: 14) {
            Text("💡")
                .font(.system(size: 22))
                .frame(width: 44, height: 44)
                .background(Color.appAccentTint, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(detail)
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

extension Category {
    /// Whether the Portuguese label conjugates as plural ("Carnes subiram" vs. "Mercearia subiu").
    fileprivate var pluralLabel: Bool {
        switch self {
        case .meat, .dairyDeli, .beverages, .snacksSweets, .frozen, .household, .other: true
        case .produce, .bakery, .grocery, .cleaning, .hygiene, .pet: false
        }
    }
}

// MARK: - Quick stats

private struct StatTile: View {
    let title: String
    let value: String
    let caption: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 2)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(Color.label3)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .card(cornerRadius: 18)
    }
}

// MARK: - Price radar

private struct PriceRadarCard: View {
    let radar: InsightsSnapshot.PriceRadar
    let window: [InsightsSnapshot.MonthSpend]

    private var priceLabel: String {
        radar.unit == "un" ? Format.brl(radar.currentPrice) : "\(Format.brl(radar.currentPrice))/\(radar.unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    CardSectionHeader("Radar de preços")
                    Text(radar.productName)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(priceLabel)
                        .font(.title3.weight(.heavy))
                        .monospacedDigit()
                    if radar.changePercent != 0 {
                        TrendLabel(percent: radar.changePercent, suffix: "desde \(radar.sinceLabel)")
                    }
                }
            }

            Chart(radar.points) { point in
                AreaMark(
                    x: .value("Mês", point.label),
                    y: .value("Preço", point.price)
                )
                .foregroundStyle(Color.appAccentTint)

                LineMark(
                    x: .value("Mês", point.label),
                    y: .value("Preço", point.price)
                )
                .foregroundStyle(Color.appAccent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                if point == radar.points.last {
                    PointMark(
                        x: .value("Mês", point.label),
                        y: .value("Preço", point.price)
                    )
                    .foregroundStyle(Color.appAccent)
                    .symbolSize(60)
                }
            }
            .chartXScale(domain: window.map(\.label))
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel(anchor: .top) }
            }
            .frame(height: 90)
            .padding(.top, 14)
        }
        .padding(18)
        .card(cornerRadius: 22)
    }
}

// MARK: - Top stores

private struct TopStoresCard: View {
    let stores: [InsightsSnapshot.StoreRank]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardSectionHeader("Onde você compra")

            ForEach(stores) { store in
                VStack(spacing: 7) {
                    HStack(spacing: 10) {
                        Text("\(store.rank)")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(store.rank == 1 ? Color.appAccentForeground : .secondary)
                            .frame(width: 20, height: 20)
                            .background(
                                store.rank == 1 ? Color.appAccent : Color.appFill,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                        Text(store.name)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Format.brl(store.amount))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }

                    GeometryReader { geo in
                        Capsule()
                            .fill(
                                store.rank == 1
                                    ? AnyShapeStyle(AppGradient.accent)
                                    : AnyShapeStyle(Color.appAccent.opacity(0.65))
                            )
                            .frame(width: max(geo.size.width * store.fraction, 8))
                    }
                    .frame(height: 8)
                    .background(Color.appFill, in: Capsule())
                }
            }
        }
        .padding(18)
        .card(cornerRadius: 22)
    }
}

// MARK: - Weekday pattern

private struct WeekdayCard: View {
    let weekdays: [InsightsSnapshot.WeekdaySpend]
    let topWeekdayName: String?

    private var maxTotal: Double {
        max(weekdays.map(\.total).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                CardSectionHeader("Por dia da semana")
                if let topWeekdayName {
                    Text("\(topWeekdayName) é seu dia")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(weekdays) { day in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(barStyle(for: day))
                            .frame(height: max(70 * day.total / maxTotal, 6))
                        Text(day.letter)
                            .font(.system(size: 10.5, weight: day.rank == 0 ? .heavy : .semibold))
                            .foregroundStyle(day.rank == 0 && day.total > 0 ? Color.appAccent : Color.label3)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 84, alignment: .bottom)
        }
        .padding(18)
        .card(cornerRadius: 22)
    }

    private func barStyle(for day: InsightsSnapshot.WeekdaySpend) -> AnyShapeStyle {
        guard day.total > 0 else { return AnyShapeStyle(Color.appFillSubtle) }
        return switch day.rank {
        case 0: AnyShapeStyle(AppGradient.accent)
        case 1: AnyShapeStyle(Color.appAccentTint)
        default: AnyShapeStyle(Color.appFill)
        }
    }
}

// MARK: - Empty state

private struct EmptyInsightsView: View {
    let scanFirst: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "chart.pie")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .frame(width: 96, height: 96)
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(.bottom, 22)

            Text("Sem insights por enquanto")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            Text("Registre suas compras e os gráficos aparecem aqui: categorias, mercados e a evolução dos seus gastos.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Button(action: scanFirst) {
                Text("Escanear primeira nota")
                    .font(.headline)
                    .foregroundStyle(Color.appAccentForeground)
                    .padding(.horizontal, 22)
                    .frame(height: 50)
                    .background(AppGradient.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.appAccent.opacity(0.25), radius: 10, y: 4)
            }
            .padding(.top, 24)
        }
        .padding(.horizontal, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
}

#Preview {
    InsightsView(store: Store(initialState: InsightsFeature.State()) { InsightsFeature() })
}

#Preview("Vazio") {
    InsightsView(
        store: Store(initialState: InsightsFeature.State()) {
            InsightsFeature()
        } withDependencies: {
            $0.purchasesRepository.recentPurchases = { _ in [] }
        }
    )
}
