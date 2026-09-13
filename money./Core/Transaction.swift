import Foundation

/// String-backed token that encodes as a bare string and tolerates values Trade Republic
/// invents later. A closed `enum` would turn every new event type into a failed import.
nonisolated protocol StringToken: RawRepresentable, Codable, Hashable, Sendable where RawValue == String {
    init(rawValue: String)
}

nonisolated extension StringToken {
    init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The `category` column: which of the two Trade Republic accounts a booking belongs to.
nonisolated struct AccountCategory: StringToken {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    static let cash = AccountCategory(rawValue: "CASH")
    static let trading = AccountCategory(rawValue: "TRADING")
}

/// The `type` column. Note that the direction of money is *not* derivable from this —
/// `TRANSFER_DIRECT_DEBIT_INBOUND` appears on outgoing direct debits. Trust `amount`.
nonisolated struct TransactionType: StringToken {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    static let cardTransaction = TransactionType(rawValue: "CARD_TRANSACTION")
    static let cardTransactionInternational = TransactionType(rawValue: "CARD_TRANSACTION_INTERNATIONAL")
    static let cardOrderingFee = TransactionType(rawValue: "CARD_ORDERING_FEE")
}

/// One row of the CSV. Immutable: the export is the source of truth and the app never
/// edits a booking, only the rules that interpret it.
nonisolated struct Transaction: Identifiable, Hashable, Codable, Sendable {
    /// `transaction_id` — the deduplication key across overlapping exports.
    let id: String
    let timestamp: Date
    let bookingDate: CalendarDate
    let account: AccountCategory
    let type: TransactionType
    /// `name` — merchant for card payments, counterparty for transfers, empty for fees.
    let merchant: String
    /// `description` — free text; the only merchant signal on some rows.
    let detail: String
    let amount: Decimal
    let fee: Decimal
    let tax: Decimal
    let currency: String
    let originalAmount: Decimal?
    let originalCurrency: String?
    let fxRate: Decimal?
    let counterpartyName: String?
    let counterpartyIBAN: String?
    let paymentReference: String?
    /// Kept as `String`: MCCs are four-digit codes that can start with zero.
    let mcc: String?
}

nonisolated extension Transaction {
    /// What actually left the account. The ATM row books `-53.06` with a separate `-1.00`
    /// fee; both are the user's money.
    var netAmount: Decimal { amount + fee + tax }

    var isCash: Bool { account == .cash }

    /// Positive for money out. Refunds are negative spend, which is what makes a returned
    /// item give budget back without any special case.
    var spend: Decimal { -netAmount }

    var month: YearMonth { bookingDate.yearMonth }

    /// The text a merchant-pattern rule matches against.
    var matchableText: String { merchant.isEmpty ? detail : merchant }

    /// Money spent in a shop, at a terminal, at an ATM.
    var isCardPayment: Bool { type.rawValue.hasPrefix("CARD_") }

    /// Money moved by transfer or direct debit — rent, bills, paying people back. Reported
    /// apart from card spending because it is a different kind of decision.
    var isTransfer: Bool {
        let raw = type.rawValue
        return raw.contains("TRANSFER") || raw.contains("DIRECT_DEBIT")
    }
}
