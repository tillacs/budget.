import Foundation

nonisolated struct Suggestion: Equatable, Sendable {
    let categoryID: BudgetCategory.ID
    /// Posterior probability in 0…1. Not money, so `Double` is the right type here.
    let confidence: Double
    /// The features that pushed hardest toward this category, best first.
    let evidence: [String]
}

nonisolated struct LabeledTransaction: Sendable {
    let transaction: Transaction
    let categoryID: BudgetCategory.ID

    init(_ transaction: Transaction, _ categoryID: BudgetCategory.ID) {
        self.transaction = transaction
        self.categoryID = categoryID
    }
}

/// Multinomial naive Bayes over merchant words and MCC, trained on the categorizations the
/// user has already committed to.
///
/// It never overrides a rule and never learns from its own output — training data is only
/// what a rule matched or what the user assigned by hand. That keeps a wrong guess from
/// reinforcing itself, which is the failure mode that makes self-training classifiers rot.
nonisolated struct LearnedClassifier: Sendable {
    nonisolated struct Configuration: Equatable, Sendable {
        /// Below this, a guess is offered but never applied on its own.
        var minimumConfidence: Double = 0.85
        /// A category with too little history is not a candidate at all.
        var minimumExamplesPerCategory: Int = 3
        /// Nothing is auto-assigned until there is a history worth calling one.
        var minimumTotalExamples: Int = 12
        /// Laplace alpha. Add-1 is far too flat here: with a vocabulary of a few dozen
        /// words, a decisive token like EDEKA only reached ~0.74 and never cleared the
        /// confidence bar. A smaller alpha lets a word that appears in exactly one
        /// category actually mean something.
        var smoothing: Double = 0.1

        static let `default` = Configuration()
    }

    private let configuration: Configuration
    private let exampleCounts: [BudgetCategory.ID: Int]
    private let featureCounts: [BudgetCategory.ID: [String: Int]]
    private let featureTotals: [BudgetCategory.ID: Int]
    private let vocabulary: Set<String>
    private let totalExamples: Int
    private let candidates: [BudgetCategory.ID]

    init(examples: [LabeledTransaction], configuration: Configuration = .default) {
        var exampleCounts: [BudgetCategory.ID: Int] = [:]
        var featureCounts: [BudgetCategory.ID: [String: Int]] = [:]
        var featureTotals: [BudgetCategory.ID: Int] = [:]

        for example in examples {
            let features = MerchantTokenizer.features(of: example.transaction)
            guard !features.isEmpty else { continue }
            exampleCounts[example.categoryID, default: 0] += 1
            featureTotals[example.categoryID, default: 0] += features.count
            for feature in features {
                featureCounts[example.categoryID, default: [:]][feature, default: 0] += 1
            }
        }

        let candidates = exampleCounts
            .filter { $0.value >= configuration.minimumExamplesPerCategory }
            .keys
            .sorted { $0.uuidString < $1.uuidString }

        // Only words from categories that can actually be suggested count as evidence.
        // Otherwise a word learned solely from a category with too little history would
        // still make some unrelated category look informed.
        var vocabulary: Set<String> = []
        for categoryID in candidates {
            vocabulary.formUnion(featureCounts[categoryID]?.keys ?? Dictionary().keys)
        }

        self.vocabulary = vocabulary
        self.configuration = configuration
        self.exampleCounts = exampleCounts
        self.featureCounts = featureCounts
        self.featureTotals = featureTotals
        self.totalExamples = exampleCounts.values.reduce(0, +)
        self.candidates = candidates
    }

    /// It takes two categories before the classifier can say anything meaningful.
    var isTrained: Bool { candidates.count >= 2 }

    /// Best guess with no confidence gate — what the Inbox pre-selects.
    func suggestion(for transaction: Transaction) -> Suggestion? {
        ranking(for: transaction).first
    }

    /// Only returned when the app may apply it without asking.
    func confidentSuggestion(for transaction: Transaction) -> Suggestion? {
        guard totalExamples >= configuration.minimumTotalExamples,
              let best = suggestion(for: transaction),
              best.confidence >= configuration.minimumConfidence
        else { return nil }
        return best
    }

    func ranking(for transaction: Transaction) -> [Suggestion] {
        let features = MerchantTokenizer.features(of: transaction).intersection(vocabulary)
        // No shared feature means no evidence. Falling back to the prior here would make the
        // largest category swallow every unknown merchant.
        //
        // Fewer than two candidates means there is nothing to compare against either, and a
        // softmax over one category would report a confident 100% for anything at all.
        guard !features.isEmpty, candidates.count >= 2 else { return [] }

        let scores = candidates.map { categoryID in
            (categoryID, logScore(categoryID: categoryID, features: features))
        }
        let maximum = scores.map(\.1).max() ?? 0
        let exponentials = scores.map { exp($0.1 - maximum) }
        let normalizer = exponentials.reduce(0, +)
        guard normalizer > 0, normalizer.isFinite else { return [] }

        return zip(scores, exponentials)
            .map { score, exponential in
                Suggestion(
                    categoryID: score.0,
                    confidence: exponential / normalizer,
                    evidence: evidence(for: score.0, features: features)
                )
            }
            .sorted {
                $0.confidence == $1.confidence
                    ? $0.categoryID.uuidString < $1.categoryID.uuidString
                    : $0.confidence > $1.confidence
            }
    }

    private func logScore(categoryID: BudgetCategory.ID, features: Set<String>) -> Double {
        var score = log(Double(exampleCounts[categoryID] ?? 0) / Double(totalExamples))
        for feature in features.sorted() {
            score += logLikelihood(feature, categoryID: categoryID)
        }
        return score
    }

    /// Additive smoothing: an unseen-in-this-category feature costs a lot but never sets
    /// the whole product to zero.
    private func logLikelihood(_ feature: String, categoryID: BudgetCategory.ID) -> Double {
        let occurrences = Double(featureCounts[categoryID]?[feature] ?? 0)
        let total = Double(featureTotals[categoryID] ?? 0)
        let alpha = configuration.smoothing
        return log((occurrences + alpha) / (total + alpha * Double(vocabulary.count)))
    }

    /// A feature is evidence when it is likelier here than under the best rival category.
    private func evidence(for categoryID: BudgetCategory.ID, features: Set<String>) -> [String] {
        var scored: [(feature: String, margin: Double)] = []
        for feature in features {
            let here = logLikelihood(feature, categoryID: categoryID)
            var best: Double?
            for rival in candidates where rival != categoryID {
                let score = logLikelihood(feature, categoryID: rival)
                if best == nil || score > best! { best = score }
            }
            let margin = here - (best ?? here)
            if margin > 0 { scored.append((feature, margin)) }
        }

        scored.sort { left, right in
            left.margin == right.margin ? left.feature < right.feature : left.margin > right.margin
        }
        return scored.prefix(3).map { MerchantTokenizer.label(for: $0.feature) }
    }
}
