import Foundation
import Testing
@testable import money_

struct LearnedClassifierTests {
    let groceries = BudgetCategory(name: "Lebensmittel")
    let restaurants = BudgetCategory(name: "Restaurants")

    /// Rules already cover these; the point is what the classifier generalizes to next.
    private func trainedClassifier(
        configuration: LearnedClassifier.Configuration = .default
    ) -> LearnedClassifier {
        var examples: [LabeledTransaction] = []
        for (index, merchant) in ["EDEKA Muenchen. Impler", "EDEKA Ebenhausen", "ALDI SUED",
                                  "ALDI SUED", "Ernst LebensmittelGmbH", "REWE Icking"].enumerated() {
            examples.append(LabeledTransaction(
                Fixtures.card(merchant: merchant, mcc: "5411", id: "g\(index)"), groceries.id))
        }
        for (index, merchant) in ["FR freiraum Gastronomie", "Alte Utting", "Cafe Kosmos",
                                  "Trattoria Bella", "Bar Centrale", "Cafe Kosmos"].enumerated() {
            examples.append(LabeledTransaction(
                Fixtures.card(merchant: merchant, mcc: "5812", id: "r\(index)"), restaurants.id))
        }
        return LearnedClassifier(examples: examples, configuration: configuration)
    }

    @Test func aNewBranchOfAKnownChainIsRecognized() throws {
        let classifier = trainedClassifier()
        let transaction = Fixtures.card(merchant: "EDEKA Sendling", mcc: nil, id: "new")
        let suggestion = try #require(classifier.suggestion(for: transaction))
        #expect(suggestion.categoryID == groceries.id)
        #expect(suggestion.confidence > 0.9)
        #expect(suggestion.evidence.contains("EDEKA"))
    }

    @Test func anUnknownMerchantProducesNoGuessAtAll() throws {
        let classifier = trainedClassifier()
        let transaction = Fixtures.card(merchant: "Zahnarzt Dr Schmidt", mcc: "8021", id: "new")
        // Falling back to the prior here would sort every unknown shop into the biggest
        // category, which is worse than an Inbox entry.
        #expect(classifier.suggestion(for: transaction) == nil)
        #expect(classifier.confidentSuggestion(for: transaction) == nil)
    }

    @Test func theMccAloneIsEnoughEvidence() throws {
        let classifier = trainedClassifier()
        let transaction = Fixtures.card(merchant: "Namenloser Laden", mcc: "5812", id: "new")
        let suggestion = try #require(classifier.suggestion(for: transaction))
        #expect(suggestion.categoryID == restaurants.id)
        #expect(suggestion.evidence.contains("MCC 5812"))
    }

    @Test func aWeakGuessIsOfferedButNotApplied() throws {
        let classifier = trainedClassifier()
        // "Cafe" points at restaurants, "EDEKA" at groceries — genuinely ambiguous.
        let transaction = Fixtures.card(merchant: "EDEKA Cafe", mcc: nil, id: "new")
        let suggestion = try #require(classifier.suggestion(for: transaction))
        #expect(suggestion.confidence < 0.99)
        if suggestion.confidence < LearnedClassifier.Configuration.default.minimumConfidence {
            #expect(classifier.confidentSuggestion(for: transaction) == nil)
        }
    }

    @Test func nothingIsAppliedBeforeThereIsAHistory() throws {
        let sparse = LearnedClassifier(examples:
            (0..<3).map {
                LabeledTransaction(
                    Fixtures.card(merchant: "EDEKA", mcc: "5411", id: "g\($0)"), groceries.id)
            } + (0..<3).map {
                LabeledTransaction(
                    Fixtures.card(merchant: "Alte Utting", mcc: "5812", id: "r\($0)"), restaurants.id)
            })
        let transaction = Fixtures.card(merchant: "EDEKA Neu", mcc: "5411", id: "new")
        let suggestion = try #require(sparse.suggestion(for: transaction))
        #expect(suggestion.categoryID == groceries.id)
        // Six bookings are not a history. Offer it, do not act on it.
        #expect(sparse.confidentSuggestion(for: transaction) == nil)
    }

    @Test func aCategoryWithTooFewExamplesIsNotACandidate() throws {
        var examples = (0..<10).map {
            LabeledTransaction(Fixtures.card(merchant: "EDEKA", mcc: "5411", id: "g\($0)"), groceries.id)
        }
        examples.append(LabeledTransaction(
            Fixtures.card(merchant: "Alte Utting", mcc: "5812", id: "r0"), restaurants.id))

        let classifier = LearnedClassifier(examples: examples)
        let transaction = Fixtures.card(merchant: "Alte Utting", mcc: "5812", id: "new")
        // Restaurants has one example, so it is not a candidate — and its words are then not
        // evidence either. Groceries must not inherit them.
        #expect(classifier.suggestion(for: transaction) == nil)
    }

    @Test func aSingleKnownCategoryNeverReportsCertainty() throws {
        let classifier = LearnedClassifier(examples: (0..<20).map {
            LabeledTransaction(Fixtures.card(merchant: "EDEKA", mcc: "5411", id: "g\($0)"), groceries.id)
        })
        // One category means a softmax over one element, which is 100% by construction.
        #expect(classifier.suggestion(for: Fixtures.card(merchant: "EDEKA Neu", mcc: "5411", id: "n")) == nil)
    }

    @Test func referenceNumbersAreNotLearned() throws {
        #expect(MerchantTokenizer.words(in: "DHL*BBY8CWC378Z2") == ["DHL"])
        #expect(MerchantTokenizer.words(in: "BMW AG AUFWERTER MUC 1000") == ["BMW", "AUFWERTER", "MUC"])
        #expect(MerchantTokenizer.words(in: "Ernst LebensmittelGmbH") == ["ERNST", "LEBENSMITTELGMBH"])
        #expect(MerchantTokenizer.words(in: "SP SYS-TEMIC") == ["SYS", "TEMIC"])
    }

    @Test func umlautsAndCaseAreFoldedTogether() throws {
        #expect(MerchantTokenizer.words(in: "EDEKA München") == ["EDEKA", "MUNCHEN"])
        #expect(MerchantTokenizer.words(in: "edeka muenchen") == ["EDEKA", "MUENCHEN"])
    }

    @Test func aRepeatedWordCountsOnce() throws {
        let transaction = Fixtures.card(merchant: "EDEKA", detail: "EDEKA", mcc: "5411", id: "x")
        #expect(MerchantTokenizer.features(of: transaction) == ["word:EDEKA", "mcc:5411"])
    }

    @Test func theRankingIsStableAcrossRuns() throws {
        let classifier = trainedClassifier()
        let transaction = Fixtures.card(merchant: "EDEKA Sendling", mcc: nil, id: "new")
        let first = classifier.ranking(for: transaction)
        let second = classifier.ranking(for: transaction)
        #expect(first == second)
        #expect(first.map(\.confidence).reduce(0, +) > 0.999)
    }

    @Test func theClassifierNeverLearnsFromItsOwnGuesses() throws {
        let transactions = [
            Fixtures.card(merchant: "EDEKA", mcc: "5411", id: "a"),
            Fixtures.card(merchant: "EDEKA Neu", mcc: nil, id: "b"),
        ]
        let rules = [Rule(categoryID: groceries.id, matcher: .mcc("5411"))]
        let examples = Categorizer.trainingExamples(
            transactions: transactions, rules: rules, overrides: [:])
        // "b" would be a confident guess, but a guess is not evidence.
        #expect(examples.map(\.transaction.id) == ["a"])
    }
}
