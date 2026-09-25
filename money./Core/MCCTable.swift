// MCCTable.swift
// budget. — was ein Händlercode über die Kategorie verrät
//
// Trade Republic liefert zu jeder Kartenzahlung den Merchant Category Code. Das ist
// kein Wissen über den Nutzer, nur ein Vorurteil: 5411 ist ein Supermarkt. Es zählt
// deshalb schwach und nur, wenn eine Kategorie mit passendem Namen existiert. Sobald
// der Nutzer denselben Code ein paarmal selbst zugeordnet hat, übernimmt das Gelernte.

import Foundation

nonisolated enum MCCTable {
    struct Hint: Sendable {
        let label: String
        /// Kategorienamen, in Reihenfolge der Wahrscheinlichkeit. Der erste, der bei
        /// den Kategorien des Nutzers existiert, gewinnt.
        let candidates: [String]
    }

    static func hint(for code: String?) -> Hint? {
        guard let code else { return nil }
        return table[code]
    }

    private static let table: [String: Hint] = {
        var t: [String: Hint] = [:]
        func add(_ codes: [String], _ label: String, _ names: [String]) {
            for code in codes { t[code] = Hint(label: label, candidates: names) }
        }
        add(["5411", "5422", "5441", "5451", "5499", "5921", "5300", "5310"], "Supermarkt", ["Lebensmittel", "Einkaufen", "Essen"])
        add(["5462"], "Bäckerei", ["Lebensmittel", "Essen"])
        add(["5812", "5813", "5814", "5811"], "Gastronomie", ["Essen", "Restaurant", "Ausgehen", "Freizeit"])
        add(["4111", "4112", "4121", "4131", "4784", "4789"], "Nahverkehr", ["Unterwegs", "Mobilität", "Verkehr"])
        add(["7523", "7511", "7512", "7513", "7519"], "Parken & Mietwagen", ["Unterwegs", "Mobilität", "Auto"])
        add(["5541", "5542", "5172", "5983"], "Tankstelle", ["Unterwegs", "Auto", "Mobilität"])
        add(["5511", "5521", "5531", "5532", "5533", "7531", "7534", "7538", "7549"], "Auto", ["Auto", "Unterwegs", "Mobilität"])
        add(["4411", "4511", "4722", "7011", "7012", "7032", "7033", "4582"], "Reisen", ["Reisen", "Urlaub", "Unterwegs"])
        add(["4814", "4815", "4816", "4821", "4899", "4900"], "Telefon & Internet", ["Abos", "Telefon", "Wohnen"])
        add(["5815", "5816", "5817", "5818", "5734", "5968", "7372"], "Digitales & Software", ["Abos", "Technik", "Freizeit"])
        add(["5912", "5122", "5977"], "Drogerie", ["Drogerie", "Gesundheit", "Lebensmittel", "Einkaufen"])
        add(["8011", "8021", "8031", "8041", "8042", "8043", "8049", "8062", "8071", "8099", "7297"], "Gesundheit", ["Gesundheit", "Arzt"])
        add(["5611", "5621", "5631", "5641", "5651", "5655", "5661", "5691", "5699", "5697", "5941", "5940"], "Kleidung & Sport", ["Kleidung", "Shopping", "Einkaufen", "Freizeit"])
        add(["5311", "5331", "5399", "5964", "5965", "5969", "5999", "5945", "5947", "5970", "5992"], "Handel", ["Shopping", "Einkaufen", "Sonstiges"])
        add(["5732", "5722", "5045", "5065", "5946"], "Technik", ["Technik", "Shopping", "Einkaufen"])
        add(["5200", "5211", "5231", "5251", "5261", "5712", "5713", "5714", "5718", "5719", "5261"], "Haus & Garten", ["Wohnen", "Einrichtung", "Shopping"])
        add(["7832", "7829", "7841", "7922", "7929", "7932", "7933", "7941", "7991", "7992", "7993", "7994", "7996", "7997", "7998", "7999", "5735", "5942", "5943", "7911"], "Freizeit", ["Freizeit", "Kultur", "Ausgehen"])
        add(["7230", "7298", "7299", "7210", "7211", "7216", "7217"], "Dienstleistungen", ["Sonstiges", "Persönliches", "Freizeit"])
        add(["6011", "6010"], "Bargeld", ["Bargeld", "Sonstiges"])
        add(["6300", "6381", "6399", "5960"], "Versicherung", ["Versicherung", "Wohnen", "Abos"])
        add(["4900", "4911"], "Strom & Wasser", ["Wohnen", "Nebenkosten"])
        add(["8211", "8220", "8241", "8244", "8249", "8299", "5942"], "Bildung", ["Bildung", "Freizeit"])
        add(["8398", "8641", "8651", "8661", "8699"], "Vereine & Spenden", ["Spenden", "Sonstiges", "Abos"])
        add(["5192", "5994", "2741"], "Zeitungen & Bücher", ["Abos", "Freizeit", "Bildung"])
        add(["7399", "7392", "7393", "8999", "8931", "8111"], "Geschäftliches", ["Sonstiges", "Arbeit"])
        add(["5995", "0742"], "Tiere", ["Haustier", "Sonstiges"])
        add(["5993", "5921"], "Tabak & Spirituosen", ["Lebensmittel", "Freizeit"])
        add(["4829", "6012", "6051", "6211"], "Geldtransfer", [])
        return t
    }()
}
