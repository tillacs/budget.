import Foundation

/// Turns a booking into the features the classifier learns from.
///
/// Only letter-only words survive. Everything with a digit in it — `BBY8CWC378Z2`,
/// `MUC 1000`, order numbers — is a one-off reference that would be learned once and
/// never seen again, which is exactly the noise that makes a naive classifier confident
/// about nonsense.
nonisolated enum MerchantTokenizer {
    static let minimumWordLength = 3

    /// Legal-form noise that appears across unrelated merchants.
    static let stopWords: Set<String> = ["GMBH", "MBH", "AG", "KG", "SARL", "CIE", "SCA", "INC", "LTD"]

    static func words(in text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .uppercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { word in
                word.count >= minimumWordLength
                    && word.allSatisfy(\.isLetter)
                    && !stopWords.contains(word)
            }
    }

    /// Deduplicated, because `name` and `description` are usually the same string and a
    /// word must not count twice just for being repeated.
    static func features(of transaction: Transaction) -> Set<String> {
        var features = Set<String>()
        for word in words(in: transaction.merchant) + words(in: transaction.detail) {
            features.insert("word:" + word)
        }
        if let mcc = transaction.mcc, !mcc.isEmpty {
            features.insert("mcc:" + mcc)
        }
        return features
    }

    /// Human-readable form for the "why" line in the Inbox.
    static func label(for feature: String) -> String {
        if let range = feature.range(of: "mcc:"), range.lowerBound == feature.startIndex {
            return "MCC " + feature[range.upperBound...]
        }
        if let range = feature.range(of: "word:"), range.lowerBound == feature.startIndex {
            return String(feature[range.upperBound...])
        }
        return feature
    }
}
