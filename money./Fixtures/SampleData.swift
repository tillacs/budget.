import Foundation

/// Stand-in data for stage 3, replaced by the real import in stage 4.
nonisolated struct SampleBundle: Sendable {
    let transactions: [Transaction]
    let categories: [BudgetCategory]
    let budgets: [BudgetCategory.ID: Decimal]
    let rules: [Rule]
    let categorizer: Categorizer
}

nonisolated enum SampleData {
    static let bundle = make()

    private static func make() -> SampleBundle {
        let month = YearMonth.current()

        let groceries = BudgetCategory(name: "Lebensmittel", kind: .spending, sortIndex: 0)
        let restaurants = BudgetCategory(name: "Restaurants", kind: .spending, sortIndex: 1)
        let bars = BudgetCategory(name: "Bars", kind: .spending, sortIndex: 2)
        let transport = BudgetCategory(name: "Transport", kind: .spending, sortIndex: 3)
        let shopping = BudgetCategory(name: "Shopping", kind: .spending, sortIndex: 4)
        let cash = BudgetCategory(name: "Bargeld", kind: .spending, sortIndex: 5)
        let rent = BudgetCategory(name: "Miete", kind: .fixed, sortIndex: 6)
        let phone = BudgetCategory(name: "Handy", kind: .fixed, sortIndex: 7)
        let insurance = BudgetCategory(name: "Versicherung", kind: .fixed, sortIndex: 8)
        let salary = BudgetCategory(name: "Gehalt", kind: .income, sortIndex: 9)
        let other = BudgetCategory(name: "Sonstige Einnahmen", kind: .income, sortIndex: 10)

        let categories = [groceries, restaurants, bars, transport, shopping, cash,
                          rent, phone, insurance, salary, other]

        let rules: [Rule] = [
            Rule(categoryID: groceries.id, matcher: .mcc("5411")),
            Rule(categoryID: groceries.id, matcher: .mcc("5462")),
            Rule(categoryID: restaurants.id, matcher: .mcc("5814")),
            Rule(categoryID: restaurants.id, matcher: .mcc("5812")),
            Rule(categoryID: bars.id, matcher: .mcc("5813")),
            Rule(categoryID: transport.id, matcher: .mcc("4111")),
            Rule(categoryID: transport.id, matcher: .mcc("7523")),
            Rule(categoryID: shopping.id, matcher: .mcc("5611")),
            Rule(categoryID: shopping.id, matcher: .mcc("5699")),
            Rule(categoryID: cash.id, matcher: .mcc("6011")),
            Rule(categoryID: rent.id, matcher: .pattern(Pattern("Miete"))),
            Rule(categoryID: phone.id, matcher: .pattern(Pattern("fraenk"))),
            Rule(categoryID: insurance.id, matcher: .pattern(Pattern("Versicherung"))),
            Rule(categoryID: salary.id, matcher: .pattern(Pattern("Gehalt"))),
            Rule(categoryID: other.id, matcher: .pattern(Pattern("PayPal Europe"))),
        ]

        let budgets: [BudgetCategory.ID: Decimal] = [
            groceries.id: 400,
            restaurants.id: 200,
            bars.id: 100,
            transport.id: 80,
            shopping.id: 250,
            cash.id: 150,
            rent.id: 1250,
            phone.id: 10,
            insurance.id: 42,
        ]

        let transactions: [Transaction] = [
            booking(month, 1, "Gehalt August", "2480.00", mcc: nil, type: "TRANSFER_INBOUND"),
            booking(month, 1, "Miete August", "-1250.00", mcc: nil,
                    type: "TRANSFER_DIRECT_DEBIT_INBOUND"),
            booking(month, 2, "EDEKA Muenchen. Impler", "-36.75", mcc: "5411"),
            booking(month, 2, "HandyParken Muenchen", "-6.77", mcc: "4111"),
            booking(month, 3, "I love leo sagt Danke", "-7.00", mcc: "5814"),
            booking(month, 4, "ALDI SUED", "-27.81", mcc: "5411"),
            booking(month, 5, "Tierpark Parken", "-2.00", mcc: "7523"),
            booking(month, 5, "SP GREEN ROOM HEADWEAR", "-98.00", mcc: "5611"),
            booking(month, 6, "Alte Utting", "-42.50", mcc: "5812"),
            booking(month, 6, "Alte Utting", "2.00", mcc: "5812"),
            booking(month, 7, "Ernst LebensmittelGmbH", "-21.39", mcc: "5411"),
            booking(month, 8, "fraenk", "-10.00", mcc: "4814"),
            booking(month, 8, "Ihle REWE Icking, Fil. 50", "-9.89", mcc: "5462"),
            booking(month, 9, "Bar Centrale", "-34.00", mcc: "5813"),
            booking(month, 10, "UBUDPASAR ADLDPS", "-53.06", mcc: "6011", fee: "-1.00"),
            booking(month, 11, "SP SYS-TEMIC", "-195.90", mcc: "5699"),
            booking(month, 11, "EDEKA Ebenhausen", "-10.05", mcc: "5411"),
            booking(month, 12, "PayPal Europe S.a.r.l. et Cie S.C.A", "39.21", mcc: nil,
                    type: "TRANSFER_INBOUND"),
            booking(month, 12, "DHL*BBY8CWC378Z2", "-1.80", mcc: "7399"),
            booking(month, 13, "ALDI SUED", "-31.14", mcc: "5411"),
            booking(month, 13, "Cafe Kosmos", "-11.20", mcc: "5813"),
            booking(month, 14, "BMW AG AUFWERTER MUC 1000", "-50.00", mcc: "5921"),
            booking(month, 14, "Ernst LebensmittelGmbH", "-2.51", mcc: "5411"),
            // Last month, so switching months shows something.
            booking(month.advanced(by: -1), 20, "EDEKA Muenchen. Impler", "-88.10", mcc: "5411"),
            booking(month.advanced(by: -1), 21, "Miete Juli", "-1250.00", mcc: nil,
                    type: "TRANSFER_DIRECT_DEBIT_INBOUND"),
        ]

        return SampleBundle(
            transactions: transactions,
            categories: categories,
            budgets: budgets,
            rules: rules,
            categorizer: Categorizer(rules: rules))
    }

    /// Amounts are strings on purpose: `let x: Decimal = -27.81` would go through `Double`
    /// and land on -27.80999999999999488.
    private static func booking(
        _ month: YearMonth,
        _ day: Int,
        _ merchant: String,
        _ amount: String,
        mcc: String?,
        fee: String = "0",
        type: String = "CARD_TRANSACTION"
    ) -> Transaction {
        Transaction(
            id: "\(month.year)-\(month.month)-\(day)-\(merchant)-\(amount)",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(day) * 86_400),
            bookingDate: CalendarDate(year: month.year, month: month.month, day: day),
            account: .cash,
            type: TransactionType(rawValue: type),
            merchant: merchant,
            detail: merchant,
            amount: TransactionCSVParser.decimal(from: amount) ?? 0,
            fee: TransactionCSVParser.decimal(from: fee) ?? 0,
            tax: 0,
            currency: "EUR",
            originalAmount: nil,
            originalCurrency: nil,
            fxRate: nil,
            counterpartyName: nil,
            counterpartyIBAN: nil,
            paymentReference: nil,
            mcc: mcc)
    }
}
