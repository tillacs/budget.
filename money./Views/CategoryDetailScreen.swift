import SwiftUI

struct CategoryDetailScreen: View {
    let category: BudgetCategory
    let month: YearMonth
    let store: AppStore

    @State private var showsEditor = false

    private var transactions: [Transaction] {
        BudgetCalculator.transactions(
            in: category.id, month: month,
            transactions: store.data.transactions, categorizer: store.categorizer)
    }

    private var total: Decimal {
        transactions.reduce(0) { $0 + $1.spend }
    }

    private var budget: Decimal { store.data.budgets[category.id] ?? 0 }

    private var comparison: CategoryComparison? {
        TrendCalculator.comparison(
            for: category.id, month: month,
            transactions: store.data.transactions, categorizer: store.categorizer)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                hero
                list
            }
            .padding(.horizontal, Metrics.screenInset)
            .padding(.top, 4)
            .padding(.bottom, 48)
        }
        .background(Palette.canvas)
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Bearbeiten") { showsEditor = true }
            }
        }
        .sheet(isPresented: $showsEditor) {
            CategoryEditorSheet(store: store, category: category)
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline)
                .font(.subheadline)
                .foregroundStyle(Palette.muted)

            Text(MoneyFormat.amount(category.kind == .income ? -total : total))
                .font(.system(size: 38, weight: .semibold))
                .tracking(-1.6)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Palette.ink)
                .padding(.top, 2)

            if category.kind != .income, budget > 0 {
                Text("von \(MoneyFormat.amount(budget)) · \(MoneyFormat.amount(budget - total)) übrig")
                    .font(.footnote)
                    .foregroundStyle(budget - total < 0 ? Palette.warn : Palette.muted)
            }

            if let comparison {
                Text(comparisonText(comparison))
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        switch category.kind {
        case .spending: return "Ausgegeben im \(MoneyFormat.month(month))"
        case .fixed: return "Abgebucht im \(MoneyFormat.month(month))"
        case .income: return "Eingenommen im \(MoneyFormat.month(month))"
        }
    }

    /// Puts the number in context. A bare figure cannot answer "is that a lot".
    private func comparisonText(_ comparison: CategoryComparison) -> String {
        let window = comparison.monthsCompared == 1
            ? "im Vormonat"
            : "im Schnitt der letzten \(comparison.monthsCompared) Monate"
        let average = MoneyFormat.amount(comparison.average)

        if comparison.average == comparison.current { return "Genau wie \(window)" }
        let direction = comparison.isAbove ? "mehr" : "weniger"
        let difference = MoneyFormat.amount(abs(comparison.delta))
        return "\(difference) \(direction) als \(window) (\(average))"
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: transactions.count == 1 ? "1 Buchung" : "\(transactions.count) Buchungen")
            if transactions.isEmpty {
                CardStack {
                    Text("Keine Buchungen in diesem Monat.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Metrics.cardPadding)
                }
            } else {
                CardStack {
                    ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                        if index > 0 { RowDivider() }
                        TransactionRow(transaction: transaction)
                    }
                }
            }
        }
    }
}

struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.matchableText)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            Text(MoneyFormat.amount(transaction.netAmount))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
        }
        .padding(Metrics.cardPadding)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [MoneyFormat.day(transaction.bookingDate)]
        if let mcc = transaction.mcc { parts.append("MCC \(mcc)") }
        if transaction.fee != 0 {
            parts.append("inkl. \(MoneyFormat.amount(abs(transaction.fee))) Gebühr")
        }
        return parts.joined(separator: " · ")
    }
}
