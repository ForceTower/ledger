import Charts
import ComposableArchitecture
import SwiftUI

struct HistoryView: View {
    @Bindable var store: StoreOf<HistoryFeature>

    private var searchBinding: Binding<String> {
        Binding(get: { store.searchText }, set: { store.send(.searchChanged($0)) })
    }

    var body: some View {
        NavigationStack {
            List {
                if let hero = store.hero {
                    Section {
                        HeroSpendCard(stats: hero)
                        if !hero.topCategories.isEmpty {
                            CategoryQuickStrip(categories: hero.topCategories)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                }

                ForEach(store.sections) { section in
                    Section {
                        ForEach(section.purchases) { purchase in
                            Button { store.send(.purchaseTapped(purchase)) } label: {
                                PurchaseCard(summary: purchase)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    } header: {
                        HStack {
                            Text(section.title).textCase(nil)
                            Spacer()
                            Text(Format.brl(section.total)).foregroundStyle(Color.label3)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .insetGroupedListStyle()
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Histórico")
            .searchable(text: searchBinding, prompt: "Buscar loja ou item")
            .refreshable { await store.send(.refresh).finish() }
            .overlay {
                if store.isInitialLoading {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.appBackground)
                } else if store.isEmpty {
                    EmptyHistoryView { store.send(.scanFirstTapped) }
                }
            }
            .navigationDestination(item: $store.scope(state: \.detail, action: \.detail)) { detailStore in
                PurchaseDetailView(store: detailStore)
            }
        }
        .task { store.send(.onAppear) }
    }
}

#Preview {
    HistoryView(store: Store(initialState: HistoryFeature.State()) { HistoryFeature() })
}

// MARK: - Hero spend card

private struct HeroSpendCard: View {
    let stats: HistoryFeature.HeroStats

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Gasto em \(stats.monthName)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.heroInkSecondary)
                Spacer()
                if let trend = stats.trendPercent, trend != 0 {
                    HStack(spacing: 5) {
                        Image(systemName: trend > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(abs(trend))%")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(Color.heroInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.16), in: Capsule())
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            CountUpText(value: stats.total, font: .system(size: 40, weight: .heavy))
                .foregroundStyle(Color.heroInk)
                .padding(.horizontal, 18)
                .padding(.top, 6)

            Text("\(stats.purchaseCount) notas · média \(Format.brl(stats.average)) por compra")
                .font(.caption)
                .foregroundStyle(Color.heroInkSecondary)
                .padding(.horizontal, 18)
                .padding(.top, 5)

            if stats.points.count > 1 {
                cumulativeChart
                    .padding(.top, 8)
            } else {
                Color.clear.frame(height: 14)
            }
        }
        .background(AppGradient.hero, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(hex: 0x0A6E66, alpha: 0.32), radius: 15, y: 5)
    }

    private var cumulativeChart: some View {
        Chart(stats.points) { point in
            AreaMark(x: .value("Dia", point.date), y: .value("Acumulado", point.cumulative))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white.opacity(0.34), .white.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            LineMark(x: .value("Dia", point.date), y: .value("Acumulado", point.cumulative))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.white)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            if point == stats.points.last {
                PointMark(x: .value("Dia", point.date), y: .value("Acumulado", point.cumulative))
                    .foregroundStyle(.white)
                    .symbolSize(64)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 80)
        .overlay(alignment: .bottom) {
            HStack {
                Text(Format.dayMonth(fromISO: stats.points.first?.date ?? ""))
                Spacer()
                Text(Format.dayMonth(fromISO: stats.points.last?.date ?? ""))
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.heroInkSecondary)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }
}

// MARK: - Category quick strip

private struct CategoryQuickStrip: View {
    let categories: [(category: Category, amount: Double)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(categories, id: \.category) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(entry.category.color)
                            .frame(width: 8, height: 8)
                        Text(entry.category.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(Format.brl(entry.amount))
                        .font(.callout.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .card(cornerRadius: 14)
            }
        }
        .padding(.top, 7)
    }
}

// MARK: - Receipt card

private struct PurchaseCard: View {
    let summary: PurchaseSummary

    private var dominantColor: Color { summary.dominantCategory?.color ?? .appAccent }

    var body: some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(dominantColor.gradient)
                .frame(width: 44, height: 44)
                .overlay {
                    Text(String(summary.store.first.map(String.init) ?? "?"))
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(summary.store)
                    .font(.callout.weight(.bold))
                    .lineLimit(1)
                CategoryProportionBar(segments: summary.barSegments, height: 4, spacing: 1.5)
                    .frame(width: 66)
                Text("\(Format.dayMonth(fromISO: summary.date)) · \(summary.itemCount) itens")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(Format.brl(summary.totalPaid))
                    .font(.callout.weight(.heavy))
                HStack(spacing: 3) {
                    Text("Ver").font(.caption2.weight(.semibold))
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Color.label3)
            }
        }
        .padding(.vertical, 14)
        .padding(.leading, 18)
        .padding(.trailing, 15)
        .background(Color.appElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(bottomTrailingRadius: 3, topTrailingRadius: 3)
                .fill(dominantColor)
                .frame(width: 4)
                .padding(.vertical, 14)
        }
        .shadow(color: .black.opacity(0.05), radius: 9, y: 3)
        .contentShape(Rectangle())
    }
}

// MARK: - Empty state

private struct EmptyHistoryView: View {
    let scanFirst: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .frame(width: 96, height: 96)
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(.bottom, 22)

            Text("Nenhuma nota por aqui ainda")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            Text("Escaneie o QR code da sua primeira compra e ela aparece organizada aqui.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .frame(maxWidth: 280)

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
