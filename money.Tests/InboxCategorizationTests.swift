import Foundation
import Testing
@testable import money_

/// What actually happens when a tap lands: a rule gets written, the group disappears, and
/// the same shop never asks again.
@MainActor
struct InboxCategorizationTests {
    private func store(_ transactions: [Transaction]) -> AppStore {
        AppStore(
            data: AppData(transactions: transactions, categories: [], rules: []),
            file: .temporary())
    }

    private func cleanup(_ store: AppStore) {
        // Each store writes to its own throwaway file; nothing shared to restore.
    }

    @Test func oneTapClearsTheWholeGroup() throws {
        let store = store((0..<5).map {
            Fixtures.card(merchant: "EDEKA Impler", mcc: "5411", amount: "-10", id: "e\($0)")
        })
        let groceries = store.addCategory(name: "Lebensmittel", kind: .spending)
        let group = try #require(store.inboxGroups.first)

        store.categorize(group, as: groceries.id,
                         writing: Rule(categoryID: groceries.id, matcher: .mcc("5411")))

        #expect(store.inboxGroups.isEmpty)
        #expect(store.data.rules.count == 1)
    }

    @Test func theTapAlsoClearsOtherShopsTheRuleCovers() throws {
        let store = store([
            Fixtures.card(merchant: "EDEKA Impler", mcc: "5411", id: "a"),
            Fixtures.card(merchant: "ALDI SUED", mcc: "5411", id: "b"),
            Fixtures.card(merchant: "Alte Utting", mcc: "5812", id: "c"),
        ])
        let groceries = store.addCategory(name: "Lebensmittel", kind: .spending)
        #expect(store.inboxGroups.count == 3)

        let edeka = try #require(store.inboxGroups.first { $0.title == "EDEKA Impler" })
        store.categorize(edeka, as: groceries.id,
                         writing: Rule(categoryID: groceries.id, matcher: .mcc("5411")))

        // ALDI went with it — that is the payoff of writing a rule instead of an assignment.
        #expect(store.inboxGroups.map(\.title) == ["Alte Utting"])
    }

    @Test func aNewBookingFromAKnownShopNeverReachesTheInbox() throws {
        let store = store([Fixtures.card(merchant: "EDEKA Impler", mcc: "5411", id: "a")])
        let groceries = store.addCategory(name: "Lebensmittel", kind: .spending)
        let group = try #require(store.inboxGroups.first)
        store.categorize(group, as: groceries.id,
                         writing: Rule(categoryID: groceries.id, matcher: .mcc("5411")))

        store.merge([Fixtures.card(merchant: "EDEKA Sendling", mcc: "5411", id: "new")])

        #expect(store.inboxGroups.isEmpty)
    }

    @Test func choosingOnlyTheseBookingsWritesNoRule() throws {
        let store = store([
            Fixtures.card(merchant: "Zahnarzt", mcc: "8021", id: "a"),
            Fixtures.card(merchant: "Zahnarzt", mcc: "8021", id: "b"),
        ])
        let health = store.addCategory(name: "Gesundheit", kind: .spending)
        let group = try #require(store.inboxGroups.first)

        store.categorize(group, as: health.id, writing: nil)

        #expect(store.data.rules.isEmpty)
        #expect(store.data.overrides.count == 2)
        #expect(store.inboxGroups.isEmpty)

        // No rule means the next visit asks again — which is what the option promises.
        store.merge([Fixtures.card(merchant: "Zahnarzt", mcc: "8021", id: "c")])
        #expect(store.inboxGroups.count == 1)
    }

    @Test func aRuleThatMissesASiblingStillClearsTheGroup() throws {
        // Same shop, but one booking carries no MCC at all.
        let store = store([
            Fixtures.card(merchant: "Kiosk am Eck", mcc: "5499", id: "a"),
            Fixtures.card(merchant: "Kiosk am Eck", mcc: nil, id: "b"),
        ])
        let groceries = store.addCategory(name: "Lebensmittel", kind: .spending)
        let group = try #require(store.inboxGroups.first)
        #expect(group.count == 2)

        store.categorize(group, as: groceries.id,
                         writing: Rule(categoryID: groceries.id, matcher: .mcc("5499")))

        // The MCC rule only covers one of them, so the other got a direct assignment rather
        // than being left behind as a confusing leftover.
        #expect(store.inboxGroups.isEmpty)
        #expect(store.data.overrides.count == 1)
        #expect(store.categorizer.assignment(
            for: store.data.transactions.first { $0.id == "b" }!).categoryID == groceries.id)
    }

    @Test func categorizingSurvivesARelaunch() throws {
        let file = DataFile.temporary()
        defer { file.removeDirectory() }

        let store = AppStore(
            data: AppData(transactions: [
                Fixtures.card(merchant: "EDEKA Impler", mcc: "5411", id: "a"),
            ]),
            file: file)
        let groceries = store.addCategory(name: "Lebensmittel", kind: .spending)
        let group = try #require(store.inboxGroups.first)
        store.categorize(group, as: groceries.id,
                         writing: Rule(categoryID: groceries.id, matcher: .mcc("5411")))

        let relaunched = AppStore.loadFromDisk(file: file)
        #expect(relaunched.inboxGroups.isEmpty)
        #expect(relaunched.data.rules.count == 1)
        #expect(relaunched.data.categories.contains(groceries))
    }

    @Test func deletingARuleSendsItsBookingsBackToTheInbox() throws {
        let store = store([Fixtures.card(merchant: "EDEKA Impler", mcc: "5411", id: "a")])
        let groceries = store.addCategory(name: "Lebensmittel", kind: .spending)
        let group = try #require(store.inboxGroups.first)
        store.categorize(group, as: groceries.id,
                         writing: Rule(categoryID: groceries.id, matcher: .mcc("5411")))
        #expect(store.inboxGroups.isEmpty)

        store.deleteRule(try #require(store.data.rules.first).id)
        #expect(store.inboxGroups.count == 1)
    }

    @Test func aCorrectionOverridesTheRuleForThatBookingOnly() throws {
        let store = store([
            Fixtures.card(merchant: "EDEKA Impler", mcc: "5411", id: "a"),
            Fixtures.card(merchant: "ALDI SUED", mcc: "5411", id: "b"),
        ])
        let groceries = store.addCategory(name: "Lebensmittel", kind: .spending)
        let gifts = store.addCategory(name: "Geschenke", kind: .spending)
        store.categorize(try #require(store.inboxGroups.first), as: groceries.id,
                         writing: Rule(categoryID: groceries.id, matcher: .mcc("5411")))

        let aldi = try #require(store.data.transactions.first { $0.id == "b" })
        store.categorize(
            InboxGroup(key: "x", title: aldi.matchableText, mcc: aldi.mcc,
                       transactions: [aldi], suggestion: nil),
            as: gifts.id, writing: nil)

        #expect(store.categorizer.assignment(for: aldi).categoryID == gifts.id)
        let edeka = try #require(store.data.transactions.first { $0.id == "a" })
        #expect(store.categorizer.assignment(for: edeka).categoryID == groceries.id)
    }
}
