import Foundation

/// Enough to make the first import useful. Deliberately not an exhaustive MCC list — the
/// Inbox is meant to fill the gaps with rules the user actually wants.
nonisolated enum DefaultSetup {
    nonisolated struct Seed: Sendable {
        let name: String
        let kind: CategoryKind
        let mccCodes: [String]
    }

    static let seeds: [Seed] = [
        // 5462 is here because it is what the user's own bakery/REWE rows carry.
        Seed(name: "Lebensmittel", kind: .spending, mccCodes: ["5411", "5462"]),
        Seed(name: "Restaurants", kind: .spending, mccCodes: ["5812", "5814"]),
        Seed(name: "Bars", kind: .spending, mccCodes: ["5813"]),
        Seed(name: "Tanken", kind: .spending, mccCodes: ["5541", "5542"]),
        Seed(name: "Transport", kind: .spending, mccCodes: ["4111", "4121"]),
        Seed(name: "Apotheke", kind: .spending, mccCodes: ["5912"]),
        Seed(name: "Bargeld", kind: .spending, mccCodes: ["6011"]),
        Seed(name: "Einnahmen", kind: .income, mccCodes: []),
    ]

    static func make(
        now: Date = Date(),
        makeID: () -> UUID = UUID.init
    ) -> (categories: [BudgetCategory], rules: [Rule]) {
        var categories: [BudgetCategory] = []
        var rules: [Rule] = []

        for (index, seed) in seeds.enumerated() {
            let category = BudgetCategory(
                id: makeID(), name: seed.name, kind: seed.kind, sortIndex: index)
            categories.append(category)
            rules.append(contentsOf: seed.mccCodes.map { code in
                Rule(id: makeID(), categoryID: category.id, matcher: .mcc(code), createdAt: now)
            })
        }

        return (categories, rules)
    }
}
