import SwiftUI

struct BudgetsPage: View {
    let store: AppStore
    let overview: MonthlyOverview
    let month: YearMonth

    @State private var showsNewCategory = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var bubbleScale: CGFloat = 1

    private var largestBudget: Decimal {
        overview.spending.map { $0.hasBudget ? $0.budget : $0.spent }.max() ?? 0
    }

    private var forecast: MonthlyForecast? {
        ForecastCalculator.forecast(for: overview, today: .today())
    }

    /// Says plainly what the projection can and cannot see. Without recurring-charge
    /// detection it only knows the fixed costs that were entered by hand, and pretending
    /// otherwise would be the dishonest part.
    private func forecastText(_ forecast: MonthlyForecast) -> String {
        let pace = forecast.isProjectedOver
            ? "In diesem Tempo fehlen bis Monatsende \(MoneyFormat.amount(-forecast.projectedRemaining))"
            : "In diesem Tempo bleiben bis Monatsende \(MoneyFormat.amount(forecast.projectedRemaining))"

        if forecast.outstandingFixed > 0 {
            return pace + " · \(MoneyFormat.amount(forecast.outstandingFixed)) eingetragene laufende Kosten kommen noch dazu"
        }
        return pace + " · noch nicht eingetragene Abbuchungen sind nicht eingerechnet"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                hero
                bubbles
                flowSummary
            }
            .padding(.horizontal, Metrics.screenInset)
            .padding(.top, 4)
            .padding(.bottom, 96)
            .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0), value: overview)
        }
        .sheet(isPresented: $showsNewCategory) {
            CategoryEditorSheet(store: store, category: nil, defaultKind: .spending)
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Noch übrig")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)

            Text(MoneyFormat.rounded(overview.totalRemaining))
                .font(.system(size: heroSize, weight: .semibold))
                .tracking(-heroSize * 0.042)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(overview.totalRemaining < 0 ? Palette.warn : Palette.ink)
                .padding(.top, 2)

            Text(overview.totalBudget > 0
                 ? "\(MoneyFormat.amount(overview.totalSpent)) von \(MoneyFormat.amount(overview.totalBudget)) verplant"
                 : "Noch kein Budget festgelegt")
                .font(.footnote)
                .foregroundStyle(Palette.muted)

            if let forecast, forecast.isReliable, forecast.budget > 0 {
                Text(forecastText(forecast))
                    .font(.footnote)
                    .foregroundStyle(forecast.isProjectedOver ? Palette.warn : Palette.muted)
            }
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: Bubbles

    private var bubbles: some View {
        BubbleLayout(spacing: 14) {
            ForEach(overview.spending) { progress in
                // Tapping a budget shows what is behind it; editing lives inside that screen.
                NavigationLink(value: progress.category) {
                    BudgetBubble(
                        progress: progress,
                        diameter: BubbleSize.diameter(
                            for: progress.hasBudget ? progress.budget : progress.spent,
                            largest: largestBudget,
                            scale: bubbleScale))
                }
                .buttonStyle(BubblePressStyle())
            }

            Button {
                showsNewCategory = true
            } label: {
                AddBubble(diameter: BubbleSize.minimum * bubbleScale)
            }
            .buttonStyle(BubblePressStyle())
        }
    }

    // MARK: Everything that moved

    private var flowSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Diesen Monat")
            CardStack {
                FlowRow(label: "Eingenommen", value: overview.flow.inflow, emphasis: true)
                RowDivider()
                FlowRow(label: "Ausgegeben", value: overview.flow.outflow, emphasis: true)
                RowDivider()
                FlowRow(label: "davon Kartenzahlungen", value: overview.flow.cardOutflow, indented: true)
                RowDivider()
                FlowRow(label: "davon Überweisungen", value: overview.flow.transferOutflow, indented: true)
                if overview.flow.otherOutflow > 0 {
                    RowDivider()
                    FlowRow(label: "davon Sonstiges", value: overview.flow.otherOutflow, indented: true)
                }
                RowDivider()
                FlowRow(label: "Unterm Strich", value: overview.flow.net, emphasis: true, signed: true)
            }

            if overview.flow.uncategorizedOutflow > 0 {
                NavigationLink(value: InboxRoute.inbox) {
                    CardStack {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Noch ohne Kategorie")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Palette.ink)
                                Text("\(overview.flow.uncategorizedCount) Buchungen · zählen in der Summe mit, aber in keinem Budget")
                                    .font(.caption)
                                    .foregroundStyle(Palette.muted)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 8)
                            Text(MoneyFormat.amount(overview.flow.uncategorizedOutflow))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.ink)
                        }
                        .padding(Metrics.cardPadding)
                    }
                }
                .buttonStyle(PressableRowStyle())
            }
        }
    }
}

struct FlowRow: View {
    let label: String
    let value: Decimal
    var emphasis: Bool = false
    var indented: Bool = false
    var signed: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(emphasis ? .subheadline.weight(.medium) : .subheadline)
                .foregroundStyle(indented ? Palette.muted : Palette.ink)
            Spacer(minLength: 8)
            Text(MoneyFormat.amount(value))
                .font(emphasis ? .subheadline.weight(.semibold) : .subheadline)
                .monospacedDigit()
                .foregroundStyle(signed && value < 0 ? Palette.warn : Palette.ink)
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.leading, indented ? 10 : 0)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

struct AddBubble: View {
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.faint, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            VStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.footnote.weight(.semibold))
                Text("Budget")
                    .font(.caption)
            }
            .foregroundStyle(Palette.muted)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel("Neues Budget anlegen")
    }
}

struct BubblePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.3, bounce: 0), value: configuration.isPressed)
    }
}
