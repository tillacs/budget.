import SwiftUI

struct FixedCostsPage: View {
    let store: AppStore
    let overview: MonthlyOverview
    let month: YearMonth

    @State private var showsNew = false

    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 42

    private var expected: Decimal { overview.fixedCosts.reduce(0) { $0 + $1.expected } }
    private var booked: Decimal { overview.fixedCosts.reduce(0) { $0 + $1.booked } }
    private var settled: Int { overview.fixedCosts.filter(\.isSettled).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                hero
                if overview.fixedCosts.isEmpty { empty } else { list }
            }
            .padding(.horizontal, Metrics.screenInset)
            .padding(.top, 4)
            .padding(.bottom, 96)
        }
        .sheet(isPresented: $showsNew) {
            CategoryEditorSheet(store: store, category: nil, defaultKind: .fixed)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Laufende Kosten")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)

            Text(MoneyFormat.rounded(expected))
                .font(.system(size: heroSize, weight: .semibold))
                .tracking(-heroSize * 0.042)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(Palette.ink)
                .padding(.top, 2)

            Text(overview.fixedCosts.isEmpty
                 ? "Noch nichts hinterlegt"
                 : "\(MoneyFormat.amount(booked)) abgebucht · \(settled) von \(overview.fixedCosts.count) erledigt")
                .font(.footnote)
                .foregroundStyle(Palette.muted)

            if overview.outstandingFixedCosts > 0 {
                Text("\(MoneyFormat.amount(overview.outstandingFixedCosts)) stehen noch aus")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Monatlich")
            CardStack {
                ForEach(Array(overview.fixedCosts.enumerated()), id: \.element.id) { index, progress in
                    if index > 0 { RowDivider() }
                    NavigationLink(value: progress.category) {
                        FixedCostRow(progress: progress)
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
            SectionHeader(title: "Monatlich")
            CardStack { addButton }
        }
    }

    private var addButton: some View {
        Button { showsNew = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.footnote.weight(.semibold))
                Text("Laufende Kosten hinzufügen").font(.subheadline.weight(.medium))
                Spacer()
            }
            .foregroundStyle(Palette.accent)
            .padding(Metrics.cardPadding)
        }
        .buttonStyle(PressableRowStyle())
    }
}

struct FixedCostRow: View {
    let progress: FixedCostProgress

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(progress.category.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                Text(progress.expected > 0
                     ? "erwartet \(MoneyFormat.amount(progress.expected))"
                     : "kein Betrag hinterlegt")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            if progress.isSettled {
                Label("abgebucht", systemImage: "checkmark")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.muted)
            } else if progress.expected > 0 {
                Text("offen")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
            } else {
                Text(MoneyFormat.amount(progress.booked))
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(Metrics.cardPadding)
        .accessibilityElement(children: .combine)
    }
}
