import Foundation

/// Starting points, not a taxonomy. Each one is a name plus the MCCs that usually mean it —
/// pick one and it arrives with working rules. Everything about it stays editable, and
/// nothing here is required.
nonisolated struct CategoryTemplate: Identifiable, Hashable, Sendable {
    let name: String
    let kind: CategoryKind
    let mccCodes: [String]
    /// Only used when the MCC table cannot carry the meaning, as with subscriptions.
    let patterns: [String]
    let suggestedBudget: Decimal?

    var id: String { name }

    init(
        _ name: String,
        kind: CategoryKind = .spending,
        mcc: [String] = [],
        patterns: [String] = [],
        budget: String? = nil
    ) {
        self.name = name
        self.kind = kind
        self.mccCodes = mcc
        self.patterns = patterns
        self.suggestedBudget = budget.flatMap(TransactionCSVParser.decimal(from:))
    }
}

nonisolated enum CategoryTemplates {
    static let spending: [CategoryTemplate] = [
        CategoryTemplate("Lebensmittel", mcc: ["5411", "5422", "5451", "5462", "5499"], budget: "400"),
        CategoryTemplate("Restaurants", mcc: ["5812", "5814"], budget: "200"),
        CategoryTemplate("Bars", mcc: ["5813"], budget: "100"),
        CategoryTemplate("Shopping", mcc: ["5611", "5621", "5641", "5651", "5691", "5699"], budget: "150"),
        CategoryTemplate("Elektronik", mcc: ["5732", "5734", "5045", "7372"], budget: "50"),
        CategoryTemplate(
            "Online-Abos", mcc: ["4899", "5968", "7841"],
            patterns: ["Spotify", "Netflix", "Apple.com/bill", "Google", "Amazon Prime", "Disney"],
            budget: "40"),
        CategoryTemplate("Öffentlicher Verkehr", mcc: ["4111", "4112", "4131", "4789"], budget: "60"),
        CategoryTemplate("Tanken", mcc: ["5541", "5542"], budget: "150"),
        CategoryTemplate("Fortbewegung", mcc: ["4121", "7512", "7523", "5013", "7538"], budget: "80"),
        CategoryTemplate("Drogerie & Apotheke", mcc: ["5122", "5912", "5977"], budget: "50"),
        CategoryTemplate("Gesundheit", mcc: ["8011", "8021", "8062", "8099"], budget: "50"),
        CategoryTemplate("Freizeit", mcc: ["7832", "7911", "7991", "7997", "7999"], budget: "80"),
        CategoryTemplate("Reisen", mcc: ["3000", "4511", "4722", "7011"], budget: "100"),
        CategoryTemplate("Bargeld", mcc: ["6011"], budget: "100"),
    ]

    static let fixed: [CategoryTemplate] = [
        CategoryTemplate("Miete", kind: .fixed, patterns: ["Miete"]),
        CategoryTemplate("Strom", kind: .fixed, patterns: ["Strom", "Stadtwerke"]),
        CategoryTemplate("Handy & Internet", kind: .fixed, mcc: ["4814", "4816"]),
        CategoryTemplate("Versicherung", kind: .fixed, mcc: ["6300"], patterns: ["Versicherung"]),
        CategoryTemplate("Fitness", kind: .fixed, mcc: ["7997"]),
    ]

    static let income: [CategoryTemplate] = [
        CategoryTemplate("Gehalt", kind: .income, patterns: ["Gehalt", "Lohn", "Salary"]),
        CategoryTemplate("Erstattungen", kind: .income, patterns: ["PayPal Europe"]),
        CategoryTemplate("Zinsen", kind: .income, patterns: ["Interest payment", "Zinsen"]),
        CategoryTemplate("Sonstige Einnahmen", kind: .income),
    ]

    static let all: [CategoryTemplate] = spending + fixed + income

    static func templates(for kind: CategoryKind) -> [CategoryTemplate] {
        switch kind {
        case .spending: return spending
        case .fixed: return fixed
        case .income: return income
        }
    }

    /// The rules a template brings with it.
    static func rules(for template: CategoryTemplate, categoryID: BudgetCategory.ID, now: Date = Date()) -> [Rule] {
        template.mccCodes.map {
            Rule(categoryID: categoryID, matcher: .mcc($0), createdAt: now)
        } + template.patterns.map {
            Rule(categoryID: categoryID, matcher: .pattern(Pattern($0)), createdAt: now)
        }
    }
}
