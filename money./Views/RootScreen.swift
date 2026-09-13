import SwiftUI
import UniformTypeIdentifiers

/// Three pages, budgets in the middle. Swipe left for what goes out every month, right for
/// what comes in.
enum Page: Int, CaseIterable, Hashable {
    case fixedCosts
    case budgets
    case income

    var title: String {
        switch self {
        case .fixedCosts: return "Laufend"
        case .budgets: return "Budgets"
        case .income: return "Einnahmen"
        }
    }
}

struct RootScreen: View {
    let store: AppStore

    @State private var page: Page = .budgets
    @State private var month: YearMonth = .current()
    @State private var showsFileImporter = false
    @State private var showsImportResult = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var overview: MonthlyOverview {
        BudgetCalculator.overview(
            month: month,
            transactions: store.data.transactions,
            categories: store.data.categories,
            budgets: store.data.budgets,
            categorizer: store.categorizer,
            sort: store.data.sort)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthBar
                if store.data.transactions.isEmpty {
                    EmptyStateView { showsFileImporter = true }
                } else {
                    pages
                }
            }
            .background(Palette.canvas)
            .navigationTitle("budget.")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .navigationDestination(for: BudgetCategory.self) { category in
                CategoryDetailScreen(category: category, month: month, store: store)
            }
            .navigationDestination(for: InboxRoute.self) { _ in
                InboxScreen(store: store)
            }
        }
        .tint(Palette.accent)
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.commaSeparatedText, .text, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    await store.importTransactions(from: url)
                    showsImportResult = true
                }
            case .failure(let error):
                store.importErrorMessage = error.localizedDescription
                showsImportResult = true
            }
        }
        .alert("Import", isPresented: $showsImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage)
        }
        .sensoryFeedback(.success, trigger: store.lastImport)
        .sensoryFeedback(.error, trigger: store.importErrorMessage) { _, new in new != nil }
    }

    // MARK: Chrome

    private var monthBar: some View {
        HStack(spacing: 8) {
            Button { month = month.advanced(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.faint)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Vorheriger Monat")

            Text(MoneyFormat.month(month))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(minWidth: 130)

            Button { month = month.advanced(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.faint)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Nächster Monat")
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Capsule().fill(Palette.chip))
        .padding(.bottom, 10)
    }

    private var pages: some View {
        TabView(selection: $page) {
            FixedCostsPage(store: store, overview: overview, month: month)
                .tag(Page.fixedCosts)
            BudgetsPage(store: store, overview: overview, month: month)
                .tag(Page.budgets)
            IncomePage(store: store, overview: overview, month: month)
                .tag(Page.income)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .overlay(alignment: .bottom) { pageIndicator }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(Page.allCases, id: \.self) { candidate in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0)) {
                        page = candidate
                    }
                } label: {
                    Text(candidate.title)
                        .font(.caption.weight(page == candidate ? .semibold : .regular))
                        .foregroundStyle(page == candidate ? Palette.ink : Palette.muted)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(
                            Capsule().fill(page == candidate ? Palette.chip : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == candidate ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(.ultraThinMaterial))
        .padding(.bottom, 8)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showsFileImporter = true } label: {
                if store.isImporting {
                    ProgressView()
                } else {
                    Label("CSV importieren", systemImage: "square.and.arrow.down")
                }
            }
            .disabled(store.isImporting)
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink(value: InboxRoute.inbox) {
                Label("Inbox", systemImage: "tray")
            }
            .overlay(alignment: .topTrailing) {
                if overview.inboxCount > 0 {
                    Circle()
                        .fill(Palette.warn)
                        .frame(width: 7, height: 7)
                        .offset(x: 3, y: -2)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var importMessage: String {
        if let error = store.importErrorMessage { return error }
        guard let summary = store.lastImport else { return "Kein Import durchgeführt." }

        var lines = ["\(summary.added) neu, \(summary.updated) aktualisiert, \(summary.unchanged) bereits vorhanden."]
        if let earliest = summary.earliest, let latest = summary.latest {
            lines.append("Zeitraum \(MoneyFormat.day(earliest)) bis \(MoneyFormat.day(latest)).")
        }
        if !store.lastFailures.isEmpty {
            let lineNumbers = store.lastFailures.prefix(5).map { String($0.line) }.joined(separator: ", ")
            let more = store.lastFailures.count > 5 ? " …" : ""
            lines.append("\(store.lastFailures.count) Zeilen übersprungen (Zeile \(lineNumbers)\(more)).")
            if let first = store.lastFailures.first {
                lines.append("Grund der ersten: \(first.reason)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

struct EmptyStateView: View {
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Noch keine Buchungen")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text("Exportiere in Trade Republic unter Service → Kontoauszüge → Transaktionsexport und importiere die CSV hier.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button(action: onImport) {
                Text("CSV importieren")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.card)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 26)
                    .background(Capsule().fill(Palette.accent))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Metrics.screenInset)
    }
}

#Preview("Root") {
    RootScreen(store: .preview)
}
