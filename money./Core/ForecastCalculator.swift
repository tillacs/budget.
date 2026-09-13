import Foundation

/// A straight-line projection of the month, nothing cleverer.
///
/// It knows two things: what has been spent so far, and which fixed costs the user entered
/// that have not been debited yet. It does **not** know about recurring charges nobody has
/// set up as a fixed cost — those are invisible to it, and the UI has to say so rather than
/// imply a precision this cannot have.
nonisolated struct MonthlyForecast: Equatable, Sendable {
    let dayOfMonth: Int
    let daysInMonth: Int
    let budget: Decimal
    let spentSoFar: Decimal
    /// Spend so far, extrapolated over the remaining days at the same pace.
    let projectedSpend: Decimal
    /// Entered fixed costs still outstanding this month.
    let outstandingFixed: Decimal

    var projectedRemaining: Decimal { budget - projectedSpend }
    var isProjectedOver: Bool { projectedRemaining < 0 }
    var daysLeft: Int { max(0, daysInMonth - dayOfMonth) }

    /// The first days of a month say almost nothing about the whole month — one big shop on
    /// the 2nd would project to a catastrophe.
    static let minimumDaysForConfidence = 5
    var isReliable: Bool { dayOfMonth >= MonthlyForecast.minimumDaysForConfidence }
}

nonisolated enum ForecastCalculator {
    /// `nil` for any month that is not currently running: a finished month needs no
    /// projection, and a future one has nothing to project from.
    static func forecast(for overview: MonthlyOverview, today: CalendarDate) -> MonthlyForecast? {
        guard today.yearMonth == overview.month else { return nil }

        let daysInMonth = today.numberOfDaysInMonth
        let dayOfMonth = min(max(1, today.day), daysInMonth)
        let spent = overview.totalSpent

        let projected = spent * Decimal(daysInMonth) / Decimal(dayOfMonth)

        return MonthlyForecast(
            dayOfMonth: dayOfMonth,
            daysInMonth: daysInMonth,
            budget: overview.totalBudget,
            spentSoFar: spent,
            projectedSpend: projected,
            outstandingFixed: overview.outstandingFixedCosts)
    }
}
