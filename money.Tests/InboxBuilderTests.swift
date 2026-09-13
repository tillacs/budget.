import Foundation
import Testing
@testable import money_

struct InboxBuilderTests {
    let groceries = BudgetCategory(name: "Lebensmittel", kind: .spending, sortIndex: 0)

    // MARK: Grouping — the deduplication that matters in the Inbox

    @Test func fiveVisitsToOneShopAreOnePieceOfWork() throws {
        let transactions = (0..<5).map {
            Fixtures.card(merchant: "EDEKA Muenchen. Impler", mcc: "5411",
                          amount: "-10", id: "e\($0)")
        }
        let groups = InboxBuilder.groups(
            transactions: transactions, categorizer: Categorizer(rules: []))

        #expect(groups.count == 1)
        #expect(groups[0].count == 5)
        #expect(groups[0].total == 50)
    }

    @Test func punctuationAndCaseDoNotSplitAShop() throws {
        let transactions = [
            Fixtures.card(merchant: "EDEKA Muenchen. Impler", mcc: "5411", id: "a"),
            Fixtures.card(merchant: "EDEKA MUENCHEN IMPLER", mcc: "5411", id: "b"),
            Fixtures.card(merchant: "edeka muenchen  impler", mcc: "5411", id: "c"),
        ]
        let groups = InboxBuilder.groups(
            transactions: transactions, categorizer: Categorizer(rules: []))
        #expect(groups.count == 1)
        #expect(groups[0].count == 3)
    }

    @Test func differentShopsStaySeparate() throws {
        let transactions = [
            Fixtures.card(merchant: "EDEKA Muenchen", mcc: "5411", id: "a"),
            Fixtures.card(merchant: "EDEKA Ebenhausen", mcc: "5411", id: "b"),
            Fixtures.card(merchant: "ALDI SUED", mcc: "5411", id: "c"),
        ]
        let groups = InboxBuilder.groups(
            transactions: transactions, categorizer: Categorizer(rules: []))
        #expect(groups.count == 3)
    }

    @Test func areferenceNumberDoesNotSplitOneShopIntoMany() throws {
        // Each of these carries a unique order reference; without normalization they would
        // be three separate Inbox entries forever.
        let transactions = [
            Fixtures.card(merchant: "DHL*BBY8CWC378Z2", mcc: "7399", id: "a"),
            Fixtures.card(merchant: "DHL*QQ11ZZ99XX00", mcc: "7399", id: "b"),
            Fixtures.card(merchant: "DHL*AA22BB33CC44", mcc: "7399", id: "c"),
        ]
        let groups = InboxBuilder.groups(
            transactions: transactions, categorizer: Categorizer(rules: []))
        #expect(groups.count == 1)
        #expect(groups[0].count == 3)
    }

    @Test func namelessRowsAreSeparatedByMccRatherThanLumpedTogether() throws {
        let transactions = [
            Fixtures.card(merchant: "", detail: "", mcc: "6011", id: "a"),
            Fixtures.card(merchant: "", detail: "", mcc: "5411", id: "b"),
        ]
        let groups = InboxBuilder.groups(
            transactions: transactions, categorizer: Categorizer(rules: []))
        #expect(groups.count == 2)
    }

    // MARK: What lands in the Inbox

    @Test func categorizedBookingsNeverAppear() throws {
        let transactions = [
            Fixtures.card(merchant: "EDEKA", mcc: "5411", id: "a"),
            Fixtures.card(merchant: "Unbekannt", mcc: nil, id: "b"),
        ]
        let groups = InboxBuilder.groups(
            transactions: transactions,
            categorizer: Categorizer(rules: [Rule(categoryID: groceries.id, matcher: .mcc("5411"))]))
        #expect(groups.map(\.title) == ["Unbekannt"])
    }

    @Test func securitiesRowsAreNeverInboxWork() throws {
        let transactions = try TransactionCSVParser.parse(CSVFixtures.export).transactions
        let groups = InboxBuilder.groups(
            transactions: transactions, categorizer: Categorizer(rules: []))
        let all = groups.flatMap(\.transactions)
        #expect(all.allSatisfy { $0.isCash })
        #expect(!all.isEmpty)
    }

    @Test func aSecondVisitToARealMerchantDoesNotAddARow() throws {
        let transactions = try TransactionCSVParser.parse(CSVFixtures.export).transactions
        let categorizer = Categorizer(rules: [])
        let before = InboxBuilder.groups(transactions: transactions, categorizer: categorizer)

        let edeka = try #require(transactions.first { $0.merchant.hasPrefix("EDEKA") })
        let secondVisit = Transaction(
            id: "second-visit", timestamp: edeka.timestamp.addingTimeInterval(86_400),
            bookingDate: CalendarDate(year: 2026, month: 8, day: 20), account: .cash,
            type: edeka.type, merchant: edeka.merchant.uppercased(), detail: edeka.detail,
            amount: edeka.amount, fee: 0, tax: 0, currency: "EUR", originalAmount: nil,
            originalCurrency: nil, fxRate: nil, counterpartyName: nil, counterpartyIBAN: nil,
            paymentReference: nil, mcc: edeka.mcc)

        let after = InboxBuilder.groups(
            transactions: transactions + [secondVisit], categorizer: categorizer)

        // One more booking, but no more work.
        #expect(after.count == before.count)
        #expect(after.reduce(0) { $0 + $1.count } == before.reduce(0) { $0 + $1.count } + 1)
    }

    // MARK: Order and content

    @Test func newestWorkComesFirstAndTheOrderIsStable() throws {
        let old = Fixtures.card(merchant: "Alt", mcc: nil, id: "a")
        var transactions = [old]
        transactions.append(Transaction(
            id: "b", timestamp: old.timestamp.addingTimeInterval(10_000),
            bookingDate: CalendarDate(year: 2026, month: 8, day: 9), account: .cash,
            type: .cardTransaction, merchant: "Neu", detail: "Neu", amount: -5, fee: 0, tax: 0,
            currency: "EUR", originalAmount: nil, originalCurrency: nil, fxRate: nil,
            counterpartyName: nil, counterpartyIBAN: nil, paymentReference: nil, mcc: nil))

        let categorizer = Categorizer(rules: [])
        let groups = InboxBuilder.groups(transactions: transactions, categorizer: categorizer)
        #expect(groups.map(\.title) == ["Neu", "Alt"])
        #expect(InboxBuilder.groups(transactions: transactions.reversed(), categorizer: categorizer)
                == groups)
    }

    @Test func aGroupReportsItsSpanAndTheRuleItWouldWrite() throws {
        let transactions = [
            Fixtures.card(merchant: "EDEKA", mcc: "5411",
                          date: CalendarDate(year: 2026, month: 8, day: 2), id: "a"),
            Fixtures.card(merchant: "EDEKA", mcc: "5411",
                          date: CalendarDate(year: 2026, month: 8, day: 9), id: "b"),
        ]
        let group = try #require(InboxBuilder.groups(
            transactions: transactions, categorizer: Categorizer(rules: [])).first)

        #expect(group.mcc == "5411")
        #expect(group.earliest == CalendarDate(year: 2026, month: 8, day: 2))
        #expect(group.latest == CalendarDate(year: 2026, month: 8, day: 9))
        let proposal = RuleProposal.proposals(for: group.representative, categoryID: groceries.id)
        #expect(proposal.first?.matcher == .mcc("5411"))
    }

    /// Below the auto-assign bar the booking still reaches the Inbox — but it arrives with
    /// the classifier's guess already attached, so the sheet can pre-select it.
    @Test func aBookingBelowTheConfidenceBarArrivesWithItsGuess() throws {
        let restaurants = BudgetCategory(name: "Restaurants")
        var examples: [LabeledTransaction] = []
        // Four each: enough for both to be candidates, too few to auto-assign.
        for index in 0..<4 {
            examples.append(LabeledTransaction(
                Fixtures.card(merchant: "EDEKA Impler", mcc: "5411", id: "g\(index)"), groceries.id))
            examples.append(LabeledTransaction(
                Fixtures.card(merchant: "Alte Utting", mcc: "5812", id: "r\(index)"), restaurants.id))
        }
        let categorizer = Categorizer(
            rules: [], classifier: LearnedClassifier(examples: examples))

        let group = try #require(InboxBuilder.groups(
            transactions: [Fixtures.card(merchant: "EDEKA Sendling", mcc: nil, id: "new")],
            categorizer: categorizer).first)

        #expect(group.suggestion?.categoryID == groceries.id)
        #expect(group.suggestion?.evidence.contains("EDEKA") == true)
    }

    /// The other side of the same coin: once the history is long enough, the shop never
    /// reaches the Inbox at all. That is the Inbox emptying itself out.
    @Test func aConfidentGuessSkipsTheInboxEntirely() throws {
        let restaurants = BudgetCategory(name: "Restaurants")
        var examples: [LabeledTransaction] = []
        for index in 0..<6 {
            examples.append(LabeledTransaction(
                Fixtures.card(merchant: "EDEKA Impler", mcc: "5411", id: "g\(index)"), groceries.id))
            examples.append(LabeledTransaction(
                Fixtures.card(merchant: "Alte Utting", mcc: "5812", id: "r\(index)"), restaurants.id))
        }
        let categorizer = Categorizer(
            rules: [], classifier: LearnedClassifier(examples: examples))

        let newBooking = Fixtures.card(merchant: "EDEKA Sendling", mcc: nil, id: "new")
        #expect(InboxBuilder.groups(transactions: [newBooking], categorizer: categorizer).isEmpty)
        #expect(categorizer.assignment(for: newBooking).categoryID == groceries.id)
    }
}
