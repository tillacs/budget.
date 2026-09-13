import Foundation
import Testing
@testable import money_

struct CategorizerTests {
    let groceries = BudgetCategory(name: "Lebensmittel")
    let restaurants = BudgetCategory(name: "Restaurants")
    let cash = BudgetCategory(name: "Bargeld")

    // MARK: Order of resolution

    @Test func patternRuleBeatsMccRule() throws {
        let transaction = Fixtures.card(merchant: "EDEKA Impler", mcc: "5411")
        let categorizer = Categorizer(rules: [
            Rule(categoryID: groceries.id, matcher: .mcc("5411")),
            Rule(categoryID: restaurants.id, matcher: .pattern(Pattern("EDEKA"))),
        ])
        #expect(categorizer.assignment(for: transaction).categoryID == restaurants.id)
    }

    @Test func mccRuleAppliesWhenNoPatternMatches() throws {
        let transaction = Fixtures.card(merchant: "Irgendein Laden", mcc: "5411")
        let categorizer = Categorizer(rules: [
            Rule(categoryID: groceries.id, matcher: .mcc("5411")),
            Rule(categoryID: restaurants.id, matcher: .pattern(Pattern("EDEKA"))),
        ])
        #expect(categorizer.assignment(for: transaction).categoryID == groceries.id)
    }

    @Test func manualOverrideBeatsEveryRule() throws {
        let transaction = Fixtures.card(merchant: "EDEKA Impler", mcc: "5411", id: "tx-1")
        let categorizer = Categorizer(
            rules: [Rule(categoryID: groceries.id, matcher: .mcc("5411"))],
            overrides: ["tx-1": restaurants.id]
        )
        #expect(categorizer.assignment(for: transaction) == .manual(categoryID: restaurants.id))
    }

    @Test func nothingMatchingLandsInTheInbox() throws {
        let transaction = Fixtures.card(merchant: "Unbekannt", mcc: "9999")
        let categorizer = Categorizer(rules: [Rule(categoryID: groceries.id, matcher: .mcc("5411"))])
        #expect(categorizer.assignment(for: transaction) == .unmatched(suggestion: nil))
        #expect(categorizer.assignment(for: transaction).needsReview)
    }

    @Test func theMoreSpecificPatternWins() throws {
        let transaction = Fixtures.card(merchant: "EDEKA Muenchen. Impler", mcc: nil)
        let categorizer = Categorizer(rules: [
            Rule(categoryID: groceries.id, matcher: .pattern(Pattern("EDEKA"))),
            Rule(categoryID: restaurants.id, matcher: .pattern(Pattern("EDEKA Muenchen"))),
        ])
        #expect(categorizer.assignment(for: transaction).categoryID == restaurants.id)
    }

    @Test func theNewerMccRuleWins() throws {
        let old = Rule(categoryID: groceries.id, matcher: .mcc("5411"),
                       createdAt: Date(timeIntervalSince1970: 1_000))
        let new = Rule(categoryID: restaurants.id, matcher: .mcc("5411"),
                       createdAt: Date(timeIntervalSince1970: 2_000))
        let transaction = Fixtures.card(merchant: "Laden", mcc: "5411")
        #expect(Categorizer(rules: [old, new]).assignment(for: transaction).categoryID == restaurants.id)
        // Array order must not change the answer.
        #expect(Categorizer(rules: [new, old]).assignment(for: transaction).categoryID == restaurants.id)
    }

    @Test func securitiesRowsNeverGetAnAssignment() throws {
        let transactions = try TransactionCSVParser.parse(CSVFixtures.export).transactions
        let categorizer = Categorizer(rules: [])
        let assignments = categorizer.assignments(for: transactions)
        let trading = transactions.filter { !$0.isCash }
        #expect(!trading.isEmpty)
        #expect(trading.allSatisfy { assignments[$0.id] == nil })
    }

    // MARK: Patterns

    @Test func patternsIgnoreCaseAndDiacritics() throws {
        let pattern = Pattern("muenchen")
        #expect(pattern.matches(Fixtures.card(merchant: "EDEKA MÜNCHEN. IMPLER", mcc: nil)) == false)
        #expect(pattern.matches(Fixtures.card(merchant: "EDEKA Muenchen. Impler", mcc: nil)))
        #expect(Pattern("münchen").matches(Fixtures.card(merchant: "edeka MUENCHEN", mcc: nil)) == false)
        #expect(Pattern("ALTE").matches(Fixtures.card(merchant: "Alte Utting", mcc: nil)))
    }

    @Test func aPatternCanTargetTheDescriptionOnly() throws {
        let transaction = Fixtures.card(merchant: "", detail: "Trade Republic Card", mcc: nil)
        let merchantOnly = Pattern("Trade Republic", field: .merchant)
        let detailOnly = Pattern("Trade Republic", field: .detail)
        #expect(merchantOnly.matches(transaction) == false)
        #expect(detailOnly.matches(transaction))
    }

    @Test func regexPatternsWork() throws {
        let pattern = Pattern("^PAYPAL \\*", kind: .regex)
        #expect(pattern.matches(Fixtures.card(merchant: "PAYPAL *lino.viehmann", mcc: nil)))
        #expect(pattern.matches(Fixtures.card(merchant: "Kein PayPal *x", mcc: nil)) == false)
    }

    @Test func aBrokenRegexIsReportedAndNeverMatches() throws {
        let pattern = Pattern("[unclosed", kind: .regex)
        #expect(pattern.validationError != nil)
        #expect(pattern.matches(Fixtures.card(merchant: "[unclosed", mcc: nil)) == false)
        #expect(Pattern("", kind: .substring).validationError != nil)
        #expect(Pattern("EDEKA").validationError == nil)
    }

    // MARK: Rule proposals

    @Test func aTapDefaultsToTheMccRuleWhenThereIsAnMcc() throws {
        let transaction = Fixtures.card(merchant: "EDEKA Muenchen. Impler", mcc: "5411")
        let proposals = RuleProposal.proposals(for: transaction, categoryID: groceries.id)
        #expect(proposals.first?.matcher == .mcc("5411"))
        #expect(proposals.contains { $0.matcher == .pattern(Pattern("EDEKA Muenchen. Impler")) })
        #expect(proposals.contains { $0.matcher == .pattern(Pattern("EDEKA")) })
        #expect(proposals.allSatisfy { $0.categoryID == groceries.id })
    }

    @Test func aTapFallsBackToTheMerchantRuleWithoutAnMcc() throws {
        let transaction = Fixtures.card(merchant: "Handyvertrag", mcc: nil)
        let proposals = RuleProposal.proposals(for: transaction, categoryID: groceries.id)
        #expect(proposals.first?.matcher == .pattern(Pattern("Handyvertrag")))
        #expect(proposals.count == 1)
    }

    @Test func aProposedRuleActuallyMatchesItsOwnTransaction() throws {
        let transaction = Fixtures.card(merchant: "EDEKA Muenchen. Impler", mcc: "5411")
        for rule in RuleProposal.proposals(for: transaction, categoryID: groceries.id) {
            let categorizer = Categorizer(rules: [rule])
            #expect(categorizer.assignment(for: transaction).categoryID == groceries.id)
        }
    }

    // MARK: Learning hand-off

    @Test func onlyConfirmedAssignmentsBecomeTrainingData() throws {
        let transactions = [
            Fixtures.card(merchant: "EDEKA", mcc: "5411", id: "a"),
            Fixtures.card(merchant: "Unbekannt", mcc: nil, id: "b"),
            Fixtures.card(merchant: "Kiosk", mcc: nil, id: "c"),
        ]
        let examples = Categorizer.trainingExamples(
            transactions: transactions,
            rules: [Rule(categoryID: groceries.id, matcher: .mcc("5411"))],
            overrides: ["c": restaurants.id]
        )
        #expect(examples.count == 2)
        #expect(examples.first { $0.transaction.id == "a" }?.categoryID == groceries.id)
        #expect(examples.first { $0.transaction.id == "c" }?.categoryID == restaurants.id)
        #expect(examples.contains { $0.transaction.id == "b" } == false)
    }

    @Test func theClassifierOnlyRunsAfterTheRules() throws {
        let history = (0..<12).map { Fixtures.card(merchant: "EDEKA", mcc: "5411", id: "h\($0)") }
        let classifier = LearnedClassifier(examples: history.map { LabeledTransaction($0, groceries.id) })
        let transaction = Fixtures.card(merchant: "EDEKA Neu", mcc: "5411", id: "new")
        let categorizer = Categorizer(
            rules: [Rule(categoryID: restaurants.id, matcher: .mcc("5411"))],
            classifier: classifier
        )
        // The rule is wrong on purpose: it must still win.
        #expect(categorizer.assignment(for: transaction).categoryID == restaurants.id)
    }

    // MARK: Default setup

    @Test func theDefaultSetupCategorizesARealExport() throws {
        let (categories, rules) = DefaultSetup.make()
        let transactions = try TransactionCSVParser.parse(CSVFixtures.export).transactions
        let assignments = Categorizer(rules: rules).assignments(for: transactions)

        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        func categoryName(forTransaction id: String) -> String? {
            assignments[id]?.categoryID.flatMap { byID[$0]?.name }
        }

        #expect(categoryName(forTransaction: "019fccaa-5ffe-74ba-abbb-969255669474") == "Lebensmittel")
        #expect(categoryName(forTransaction: "019fd691-dcd3-7b6c-ac2d-b9e132e7e50d") == "Restaurants")
        #expect(categoryName(forTransaction: "019fc6a5-7da2-76ca-9205-27c13fd779c6") == "Restaurants")
        #expect(categoryName(forTransaction: "bc82b0be-fa09-4fea-a274-a259124c6e94") == "Bargeld")
        // No MCC, so the Inbox has to ask.
        #expect(assignments["019fbc33-359b-71e8-b5dc-4cd8f8498cad"]?.needsReview == true)
    }

    @Test func theDefaultSetupHasNoDuplicateMccCodes() throws {
        let (_, rules) = DefaultSetup.make()
        let codes = rules.compactMap { rule -> String? in
            guard case .mcc(let code) = rule.matcher else { return nil }
            return code
        }
        #expect(Set(codes).count == codes.count)
        #expect(codes.count == 11)
    }
}

enum Fixtures {
    static func card(
        merchant: String,
        detail: String? = nil,
        mcc: String?,
        /// A string, not a `Decimal` literal: `let x: Decimal = -27.81` is
        /// -27.80999999999999488, because a float literal goes through `Double`.
        amount: String = "-10",
        date: CalendarDate = CalendarDate(year: 2026, month: 8, day: 4),
        id: String = UUID().uuidString
    ) -> Transaction {
        Transaction(
            id: id,
            timestamp: Date(timeIntervalSince1970: 1_775_000_000),
            bookingDate: date,
            account: .cash,
            type: .cardTransaction,
            merchant: merchant,
            detail: detail ?? merchant,
            amount: TransactionCSVParser.decimal(from: amount)!,
            fee: 0,
            tax: 0,
            currency: "EUR",
            originalAmount: nil,
            originalCurrency: nil,
            fxRate: nil,
            counterpartyName: nil,
            counterpartyIBAN: nil,
            paymentReference: nil,
            mcc: mcc
        )
    }
}
