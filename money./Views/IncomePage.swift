import SwiftUI

struct IncomePage: View {
    let store: AppStore
    let overview: MonthlyOverview
    let month: YearMonth

    @State private var showsNew = false

    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 42

    /// Every euro that came in, including inflows nobody has categorized yet.
    private var uncategorized: Decimal { overview.flow.inflow - overview.totalIncome }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                hero
                if overview.income.isEmpty { empty } else { list }
            }
            .padding(.horizontal, Metrics.screenInset)
            .padding(.top, 4)
            .padding(.bottom, 96)
        }
        .sheet(isPresented: $showsNew) {
            CategoryEditorSheet(store: store, category: nil, defaultKind: .income)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Eingenommen")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)

            Text(MoneyFormat.rounded(overview.flow.inflow))
                .font(.system(size: heroSize, weight: .semibold))
                .tracking(-heroSize * 0.042)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(Palette.ink)
                .padding(.top, 2)

            Text("\(MoneyFormat.amount(overview.flow.outflow)) ausgegeben · unterm Strich \(MoneyFormat.amount(overview.flow.net))")
                .font(.footnote)
                .foregroundStyle(Palette.muted)

            if uncategorized > 0 {
                Text("\(MoneyFormat.amount(uncategorized)) davon noch ohne Kategorie")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Quellen", detail: MoneyFormat.amount(overview.totalIncome))
            CardStack {
                ForEach(Array(overview.income.enumerated()), id: \.element.id) { index, total in
                    if index > 0 { RowDivider() }
                    NavigationLink(value: total.category) {
                        IncomeRow(total: total)
                    }
                    .buttonStyle(PressableRowStyle())
                }
                RowDivider()
                addButton
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Quellen")
            CardStack { addButton }
        }
    }

    private var addButton: some View {
        Button { showsNew = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.footnote.weight(.semibold))
                Text("Einnahmequelle hinzufügen").font(.subheadline.weight(.medium))
                Spacer()
            }
            .foregroundStyle(Palette.accent)
            .padding(Metrics.cardPadding)
        }
        .buttonStyle(PressableRowStyle())
    }
}

struct IncomeRow: View {
    let total: IncomeTotal

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(total.category.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                Text(total.transactionCount == 1 ? "1 Buchung" : "\(total.transactionCount) Buchungen")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            Text(MoneyFormat.amount(total.received))
                .font(.title3.weight(.semibold))
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
        }
        .padding(Metrics.cardPadding)
        .accessibilityElement(children: .combine)
    }
}
