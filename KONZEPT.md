# Konzept: budget. erfasst selbst

Stand: 25.09.2026. Ziel der Überarbeitung: Buchungen kommen von allein aus PayPal und
Trade Republic in die App, werden mit Konfidenz einer Kategorie zugeordnet, und die
App lernt aus jeder Bestätigung, Korrektur und Ablehnung.

## 1. Was technisch wirklich geht

| Kanal | Was es liefert | Aufwand | Verdikt |
|---|---|---|---|
| **A. Mitteilungs-Auslöser (iOS 27)** | Jede Push von Trade Republic / PayPal startet sofort einen Kurzbefehl, der Titel, Untertitel und Text der Mitteilung an `SuggestEntryIntent` gibt. Echtzeit, keine API, kein Login. | klein, die Aktion gibt es schon | **Sofort machen.** Hauptkanal für „live". |
| **B. Trade-Republic-CSV** | In der TR-App: Kontoauszüge → Transaktionsexport → Teilen. 23 Spalten, darunter `type`, `mcc_code`, `counterparty_name`, `counterparty_iban`, `transaction_id`. Vollständig und exakt. | mittel (Share Extension + Parser + Abgleich) | **Sofort machen.** Die „Wahrheit", gegen die Kanal A abgeglichen wird. |
| **C. PayPal-CSV** | Nur über paypal.com („Aktivitäten exportieren"), nicht in der App. Viele technische Spalten, aber Transaktionscode, Name, Typ, Betrag sind drin. | klein, wenn B steht | Machen, aber nach B. |
| **D. PSD2-Schnittstelle (z. B. Enable Banking)** | Echte Automatik: Umsätze von TR und PayPal per API abrufen. Finanzblick/Finanzguru beweisen, dass TR eine XS2A-Schnittstelle hat; PayPal hat eine (GoCardless-ID `PAYPAL_PPLXLULL`). | groß: Registrierung als Entwickler, Schlüsselverwaltung, alle 90 Tage neu freigeben (gesetzlich), Hintergrund-Abruf | Optional, Phase 5. GoCardless nimmt seit Juli 2025 keine neuen Konten. |
| PayPal-eigene API | Transaction Search API braucht ein **Geschäftskonto**. | — | Nein. |
| pytr (inoffizielle TR-API) | Loggt das Handy aus, gegen die AGB, kann jederzeit brechen. | — | Nein. |
| Mitteilungen direkt lesen | Kann keine App unter iOS. | — | Nein — aber Kanal A umgeht das. |

**Empfehlung:** A + B als Kern. A bringt jede Kartenzahlung in Sekunden auf den Schirm,
B liefert einmal im Monat die lückenlose Liste mit MCC-Codes und räumt auf, was A
verpasst oder falsch gelesen hat. C ergänzt PayPal-Zahlungen, die nicht über die
TR-Karte laufen. D kommt nur, wenn A+B im Alltag zu wenig Automatik sind.

Der Hinweis in `CLAUDE.md` („Mitteilungen anderer Apps kann keine App lesen") stimmt
seit iOS 27 nur noch zur Hälfte: Lesen kann die App sie nicht, aber Kurzbefehle
können sie an die App weiterreichen. Das Deployment-Target bleibt 17.0; die
Automation lebt in der Kurzbefehle-App, nicht im Code.

## 2. Datenmodell — Schema 3

Alles additiv, `decodeIfPresent` wie bisher. Eine Schema-2-Datei bleibt lesbar.

### Buchung (`Entry`) bekommt

```swift
var source: EntrySource          // .manual, .notification, .importTR, .importPayPal, .api
var externalID: String?          // TR transaction_id / PayPal-Transaktionscode → Dedupe
var account: AccountKind?        // .tradeRepublic, .paypal, nil = von Hand
var merchant: String?            // Rohname, wie die Quelle ihn nennt
var mcc: String?                 // aus TR-CSV, z. B. "5411"
var counterpartyIBAN: String?    // für Überweisungen/Lastschriften
var kind: EntryKind              // .flow (zählt), .transfer (Umbuchung, zählt nicht)
var status: EntryStatus          // .expected (angekündigt), .proposed, .confirmed, .autoBooked
var refundOf: UUID?              // Erstattung: senkt diese Buchung, statt Einnahme zu sein
var pairedWith: UUID?            // Saveback-Gutschrift ↔ der Kauf, den sie finanziert
var suggestion: Suggestion?      // was die Maschine meinte, auch nach Bestätigung (für Lernen)
```

`Direction` bekommt einen dritten Fall: **`.invest`**. Kategorien haben damit drei
Bereiche — Ausgaben, Einnahmen, Investiert — und der Nutzer legt in jedem seine
eigenen an. Der Seed für „Investiert": Sparplan, Einzelkauf, Saveback, Round-up,
Krypto. `kind` regelt daneben nur noch, ob etwas zählt:

- `.flow`: Ausgabe, Einnahme oder Investition. Zählt in Ringe und Blasen.
- `.transfer`: Geld zwischen eigenen Konten (Überweisung an dich selbst bei einer
  anderen Bank). Zählt nicht. Erkennung über den Kontoinhaber-Namen und gelernte
  eigene IBANs (Regel 6). PayPal ist **kein** eigenes Konto: Gutschriften von PayPal
  sind Erstattungen oder Einnahmen, siehe Abschnitt 3.

Investitionen im Einzelnen (alle `.flow`, Richtung `.invest`), geprüft am
vollständigen Export von 14 Monaten (1.648 Zeilen):

- `BUY` mit „Savings plan execution" in `description` → Sparplan (107 von 109
  Käufen). `BUY` mit „Buy trade" → Einzelkauf. Die Maschine lernt zusätzlich je
  **ISIN** (`symbol`) und je `asset_class` (STOCK, FUND, …), damit „NVIDIA-Sparplan"
  und „MSCI-World-Sparplan" getrennte Kategorien sein können, wenn man das will.
- **Saveback** heißt im Export `BENEFITS_SAVEBACK` und ist eine **Gutschrift**
  (positiver Betrag, „Your Saveback payment", „Saveback cash reward", „Cash reward
  allocation", „Fixed income bonus"). Bis Ende 2025 steht daneben am selben Tag ein
  `BUY` über denselben Betrag und dieselbe ISIN — das Geld wurde direkt angelegt.
  Seitdem bleibt die Gutschrift auf dem Verrechnungskonto. Modell: die Gutschrift ist
  eine Einnahme „Saveback"; der gepaarte `BUY` wird Investiert „Saveback" statt
  Sparplan und mit der Gutschrift **verknüpft** („finanziert durch Saveback"). Beide
  Seiten sind echtes Geld, nichts zählt doppelt, und die Blasen zeigen, wie viel von
  selbst ins Depot fließt.
- **Round-up** kommt im Export nicht vor — du nutzt es offenbar nicht. Der Parser
  behandelt einen unbekannten Typ nie als Fehler, sondern legt ihn mit niedriger
  Konfidenz vor; taucht Round-up auf, lernt die App ihn wie jeden anderen Händler.
- `IPO_SUBSCRIPTION`: Einzelkauf. Die Teilrückzahlung („partial reimbursement") wird
  als Erstattung mit der Vorauszahlung verknüpft (siehe Abschnitt 3), netto bleibt
  der tatsächlich gezeichnete Betrag.
- `SELL`: Investition mit negativem Vorzeichen (Geld zurück ins Verrechnungskonto).
  Die Investitionssumme des Monats ist Käufe minus Verkäufe; der Ring wird bei
  Nettoverkauf leer, nicht negativ.
- `INTEREST_PAYMENT`, `DIVIDEND`: `.flow`, Einnahme, Kategorie „Kapitalerträge"
  (wird beim ersten Import angelegt, falls nicht vorhanden).
- `SPLIT`, `TAX_OPTIMIZATION`: kein Geld, werden übersprungen (mit ID gemerkt, damit
  die Zusammenfassung sie als „ohne Betrag" ausweist, nicht als Fehler).

Kartenzahlungen kommen als `CARD_TRANSACTION` und `CARD_TRANSACTION_INTERNATIONAL`
(letztere sogar häufiger; `description` enthält dann Fremdwährung und Kurs, `amount`
ist bereits in Euro). Überweisungen als `TRANSFER_INBOUND`, `TRANSFER_INSTANT_INBOUND`,
`TRANSFER_OUTBOUND`, `TRANSFER_INSTANT_OUTBOUND`, Lastschriften als
`TRANSFER_DIRECT_DEBIT_INBOUND` (negativ, trotz „inbound"). `payment_reference` ist
in allen 1.648 Zeilen leer — der Verwendungszweck steht nicht im Export, nur Name
und IBAN der Gegenseite.

Investitionen sind also nichts Zweitklassiges mehr, sondern ein dritter Bereich mit
denselben Vorschlägen, demselben Lernen und derselben Bestätigung wie Ausgaben.

### Vorschlag (`Suggestion`)

```swift
struct Suggestion {
    var categoryID: UUID
    var confidence: Double          // 0…1
    var runnerUp: UUID?             // zweitbeste, für die Schnellauswahl
    var evidence: [Evidence]        // erklärbar: „EDEKA 7× als Lebensmittel bestätigt"
    var decidedAt: Date?
    var decision: Decision?         // .accepted, .corrected(to:), .rejected
}
```

### Gedächtnis (`MerchantMemory`) ersetzt `merchantCategories`

Nicht mehr „Händler → eine Kategorie", sondern Zählungen mit Zeitstempel je Signal:

```swift
struct Tally { var confirmed: Int; var rejected: Int; var lastAt: Date }

var byMerchant: [String: [UUID: Tally]]   // MerchantKey → Kategorie → Zählung
var byToken:    [String: [UUID: Tally]]   // "EDEKA", "PARKEN", "DHL" → …
var byMCC:      [String: [UUID: Tally]]   // "5411" → …
var byIBAN:     [String: [UUID: Tally]]   // Gegenkonto → …
var byISIN:     [String: [UUID: Tally]]   // Wertpapier → …
var recurring:  [String: RecurringHint]   // MerchantKey → Betrag, Rhythmus, letzter Tag
```

Das ist weiterhin eine Tabelle, die der Nutzer füllt — nur mit mehr Spalten. Kein
Modell, kein Training, nichts verlässt das Gerät. Der alte Import von Schema 1 war ein
Klassifikator mit mitgelieferten Regeln; das hier lernt ausschließlich aus dem, was
der Nutzer selbst bestätigt hat.

### Konten (`Account`)

Klein: `kind`, `label`, `lastImportAt`, `lastExternalDate`. Dient der Anzeige
(„Trade Republic: Stand 31.08.") und der Lücken-Warnung („seit 34 Tagen kein Export").

## 3. Keine Dopplungen — die Regeln

Das ist die wichtigste Anforderung, deshalb steht sie vor der Maschine. Sieben
Regeln, jede mit Test:

1. **Geld gibt es nur einmal, und zwar bei Trade Republic.** PayPal hat kein eigenes
   Guthaben, jede PayPal-Zahlung läuft über die TR-Karte (`PAYPAL *…`) oder per
   Lastschrift vom TR-Konto, jede PayPal-Gutschrift kommt als Überweisung von „PayPal
   Europe" an. Der TR-Export ist damit vollständig. **PayPal erzeugt nie eine
   Buchung** — weder die Mitteilung noch der CSV-Export. PayPal darf nur zwei Dinge:
   eine Buchung **ankündigen** (Mitteilung, damit nichts vergessen wird) und eine
   Buchung **anreichern** (Name, Zweck, Gegenüber).
2. **Jede TR-Zeile hat eine `transaction_id`, und die ist der Schlüssel.** Im Export
   gibt es keine leeren und keine doppelten. Ein zweiter Import derselben Zeitspanne
   ändert nichts. Der Export enthält immer die gesamte Historie — genau deshalb.
3. **Angekündigte Buchungen sind vorläufig.** Was aus einer Mitteilung kommt, hat
   den Status `.expected` und wird von **genau einer** TR-Zeile eingelöst: gleicher
   Betrag, Datum ±3 Tage, Händler-Tokens überlappen oder die TR-Zeile beginnt mit
   `PAYPAL *`. Die TR-Zeile gewinnt bei Betrag, Datum, Händler; die bestätigte
   Kategorie bleibt. Bleibt eine Ankündigung 10 Tage ohne Einlösung, wird sie
   markiert („nicht bei Trade Republic gefunden") — behalten oder löschen, aber nie
   stumm mitgezählt.
4. **Zwei Mitteilungen, eine Zahlung.** Eine PayPal-Zahlung per Karte löst die
   PayPal-Mitteilung *und* die TR-Mitteilung aus. Gleicher Betrag innerhalb von
   15 Minuten, und die TR-Seite nennt PayPal → eine einzige vorläufige Buchung; der
   PayPal-Text liefert das Gegenüber und den Zweck.
5. **Erstattungen sind keine Einnahmen.** Positive Kartenzeilen (im Export 20, davon
   die Hälfte mit exakt passender Abbuchung am Vortag oder Tage davor) und
   Rückzahlungen werden mit der ursprünglichen Ausgabe **verknüpft**: gleiche
   Händler-Tokens, Betrag ≤ Original, innerhalb von 90 Tagen; exakter Betrag zuerst.
   Die Verknüpfung senkt die Ausgabe in ihrer Kategorie, die Blase schrumpft. Ohne
   Treffer fragt der Posteingang „Erstattung — wofür?" und bietet die jüngsten
   Ausgaben ähnlicher Höhe als Chips an; Rückfall ist eine Kategorie „Erstattung",
   die gegen die Ausgabensumme rechnet, nie in die Einnahmen.
6. **Hin und her mit Freunden ist Ausgleich, kein Umsatz.** Drei Muster im Export:
   `PAYPAL *nutzername` mit MCC 4829 (Geld an Freunde), 54 Gutschriften von „PayPal
   Europe" (Freunde zahlen zurück), Überweisungen an und von Personen. Modell:
   - Geld **von** einer Person → Erstattung nach Regel 5: „du hast das Essen bezahlt,
     drei Leute schicken dir 12,50 €" senkt die Buchung „Restaurant 50 €" auf 12,50 €.
     Der Posteingang schlägt die passende Ausgabe vor (gleicher Tag oder Vortag,
     Betrag passt als Teil), du bestätigst mit einem Tipp.
   - Geld **an** eine Person → eine Ausgabe in der Kategorie dessen, was es war (dein
     Anteil am Essen). Die Maschine lernt je Person, was das üblicherweise ist;
     wiederkehrende gleiche Beträge (2,50 € monatlich an dieselbe Person) landen bei
     „Abos".
   - Überweisung an **dich selbst** bei einer anderen Bank → Umbuchung. Erkannt am
     Kontoinhaber-Namen (der Nutzer trägt ihn einmal ein) und gelernt je IBAN; eine
     Liste „Eigene Konten" unter Konten & Import zeigt, welche IBANs die App dafür
     hält.
7. **Gleich ist nicht doppelt.** Zwei Zeilen mit gleichem Betrag, Händler und Tag,
   aber verschiedenen IDs, sind zwei Zahlungen (im Export: zweimal 7,00 € an dieselbe
   Person am selben Tag). Zusammengeführt wird nur über Regel 2 bis 4, nie über
   Ähnlichkeit allein.

**Prüfsumme:** Nach jedem Import rechnet die App je Monat die Summe aller Buchungen
(Ausgaben, Einnahmen, Investiert, Umbuchungen, Erstattungen) gegen die Summe der
TR-Zeilen des Monats. Stimmt es nicht, zeigt die Zusammenfassung die Differenz an,
statt sie zu verstecken. Diese Rechnung ist der Test, der die sieben Regeln
zusammenhält.

## 4. Die Vorschlagsmaschine

### Eingabe

Ein `Observation`: Betrag, Richtung, Datum, `merchant`, `mcc`, `counterpartyIBAN`,
`description`, `type` (TR-Typ) oder Mitteilungstext. Jede Quelle baut so ein Objekt;
danach ist der Weg identisch.

### Normalisierung

`MerchantKey` wird ausgebaut:

1. Präfixe abschneiden: `PAYPAL *`, `SP ` (Shopify), `SQ *`, `DHL*…` → Token vor `*`.
2. Rauschen entfernen: Ortsnamen (`MUENCHEN`, `EBENHAUSEN`), Filialnummern (`FIL. 50`),
   Rechtsformen (`GMBH`, `AG`, `S.A.R.L.`), Zahlenfolgen, „SAGT DANKE".
3. Tokens: die verbleibenden Wörter, klein geschrieben. `EDEKA MUENCHEN. IMPLER` und
   `EDEKA EBENHAUSEN` treffen sich bei `edeka`.

### Signale, jeweils → (Kategorie, Stärke 0…1, Begründung)

| # | Signal | Stärke | Beispiel |
|---|---|---|---|
| 1 | Händlerschlüssel exakt, n Bestätigungen, 0 Ablehnungen | 0,80 bei n=1, 0,95 ab n=3 | „ALDI SUED 4× als Lebensmittel" |
| 2 | Gegenkonto-IBAN | 0,90 | „Dieselbe IBAN wie die Miete" |
| 3 | Wiederkehrend: gleicher Händler, gleicher Betrag ±2 %, Rhythmus ~30 Tage | +0,10 auf 1 | „fraenk, monatlich 10 €" |
| 4 | Token-Übereinstimmung (naiver Bayes über `byToken`) | 0,50–0,85 je nach Zählung | „edeka" bekannt, Filiale neu |
| 5 | MCC gelernt (`byMCC`) | 0,60–0,80 | „5411 bisher 12× Lebensmittel" |
| 6 | MCC-Vorbelegung (fest, ~40 Codes → Seed-Kategorie) | 0,55 | 5411 → Lebensmittel, 5812/5814 → Essen, 4111/7523/4121 → Unterwegs, 4814 → Abos |
| 7 | TR-Typ + `description` | 0,95 für Zinsen/Dividenden → Kapitalerträge; 0,90 für PayPal-Transfer → Umbuchung; 0,90 für „Savings plan execution" → Sparplan, Saveback → Saveback, Round-up → Round-up | |
| 8 | ISIN / `asset_class` gelernt | 0,85 | „US67066G1040 bisher 6× Sparplan Tech" |
| 9 | Zuletzt benutzt (`lastUsed`) | 0,25 | Rückfallebene |

Ablehnungen wirken als Strafe: `rejected` in einer `Tally` zieht die Stärke für genau
diese Kombination ab (n_confirmed − 2·n_rejected, nie unter 0). Wer „DHL → Freizeit"
zweimal abgelehnt hat, sieht das nicht mehr.

Zeitgewichtung: Bestätigungen älter als 12 Monate zählen halb. Wer seine Kategorien
umbaut, wird nicht ewig von alten Entscheidungen verfolgt.

### Zusammenführung

Für jede Kategorie werden die Stärken addiert (Signale sind nicht unabhängig, daher
keine echte Wahrscheinlichkeitsrechnung, sondern gewichtete Summe, dann normalisiert):

```
score(k)      = Σ strength_i(k)
confidence    = score(top) / Σ score(alle)  ×  min(1, margin_zu_zweitbester / 0,3)
```

Der zweite Faktor drückt die Konfidenz, wenn zwei Kategorien nah beieinander liegen
(„Essen" vs. „Lebensmittel" bei einem Bäcker). Genau dann soll die App fragen.

### Drei Bänder

| Konfidenz | Verhalten | Status |
|---|---|---|
| ≥ 0,90 **und** Händler ≥ 2× bestätigt | Bucht sofort. Insel zeigt „12,50 € · Lebensmittel · automatisch". Ein Tipp macht es rückgängig oder ändert die Kategorie. | `.autoBooked` |
| 0,60 – 0,90 | Vorschlag mit vorausgewählter Kategorie und Zweitplatzierter; ein Tipp bestätigt. | `.proposed` |
| < 0,60 | Offene Frage mit der ganzen Kategorienliste, die drei besten oben. | `.proposed` |

Die Schwelle für Automatik ist einstellbar (Standard 0,90; „nie" möglich). Beim
allerersten Import gibt es keine Automatik: Die Bedingung „Händler ≥ 2× bestätigt"
sorgt dafür, dass die App erst bucht, was der Nutzer ihr wirklich beigebracht hat.

### Lernen

Jede Entscheidung schreibt in **alle** passenden Tallies:

- **Angenommen:** +1 confirmed für Händlerschlüssel, jedes Token, MCC, IBAN.
- **Korrigiert:** +1 confirmed für die gewählte Kategorie, +1 rejected für die
  vorgeschlagene, jeweils auf alle Signale, die den Vorschlag getragen haben.
- **Abgelehnt** (ohne neue Kategorie, „das gehört nicht rein"): +1 rejected, Buchung
  wird `.transfer` oder gelöscht — je nachdem, was der Nutzer wählt.
- **Nachträglich in der Liste umkategorisiert:** wie korrigiert.

Auto-Buchungen lernen **nicht**, bis der Nutzer sie angesehen hat (sonst bestätigt die
Maschine sich selbst). Angesehen heißt: die Insel-Bestätigung wurde nicht innerhalb
von 24 h zurückgenommen — dann gilt sie als still akzeptiert und zählt.

Jeder Vorschlag ist erklärbar: `evidence` wird in der Oberfläche als eine Zeile
gezeigt („weil du EDEKA 7× so gebucht hast · MCC Supermarkt").

## 5. Die Kanäle im Detail

### A. Mitteilungs-Auslöser

- Zwei Automationen in Kurzbefehle: „Wenn ich eine Mitteilung von Trade Republic
  erhalte" und dasselbe für PayPal, Aktion „Buchung vorschlagen", Text = Mitteilung.
- `SuggestEntryIntent` bekommt einen Parameter `Quelle` (Trade Republic / PayPal /
  unbekannt) und einen Parser je Quelle: Betrag, Händler, Richtung (PayPal: „gesendet"
  vs. „erhalten"; TR: Kartenzahlung vs. Gutschrift). **Die genauen Texte müssen wir
  an echten Mitteilungen prüfen** — bitte Screenshots von je einer TR-Kartenzahlung,
  einer TR-Gutschrift und einer PayPal-Zahlung.
- Die Aktion fragt bei hoher Konfidenz nicht mehr per `requestConfirmation`, sondern
  bucht und meldet über die Insel. Wird die Einblendung weggewischt oder das Band ist
  „fragen", landet der Vorschlag im Posteingang der App.
- Alles aus diesem Kanal ist `.expected` (Regel 3) und wird beim nächsten TR-Import
  eingelöst. Die PayPal-Mitteilung legt nichts an, wenn innerhalb von 15 Minuten die
  TR-Mitteilung derselben Zahlung kommt oder schon da war (Regel 4); sie ergänzt dann
  nur Gegenüber und Zweck.
- Vor iOS 27: Wallet-Auslöser für Apple-Pay-Zahlungen, wie heute.

### B. Trade-Republic-CSV

- Neues Target **Share Extension** „In budget. importieren", nimmt
  `public.comma-separated-values-text`. Zusätzlich Dateiimport aus der App
  (`fileImporter`) und Öffnen per „Öffnen mit".
- Parser `TradeRepublicExport`: die 23 Spalten, Dezimalpunkt, ISO-Datum, die 18
  `type`-Werte aus Abschnitt 2 (unbekannte Typen → `.flow` mit niedriger Konfidenz,
  nie verwerfen). Der komplette Export hat 470 KB und 1.648 Zeilen — das Parsen muss
  im Hintergrund laufen, mit Fortschritt im Blatt.
- Reihenfolge je Zeile: `transaction_id` bekannt → überspringen (Regel 2). Sonst
  eine `.expected`-Buchung einlösen (Regel 3). Sonst Erstattung verknüpfen (Regel 5).
  Sonst Saveback-Paar bilden. Sonst durch die Maschine. Manuelle Buchungen gleichen
  Betrags am selben Tag werden als „vermutlich dieselbe" markiert und gefragt.
- Ergebnis: Import-Zusammenfassung („1.648 Zeilen, 1.617 schon bekannt, 12
  automatisch gebucht, 9 Vorschläge, 6 Umbuchungen, 4 Erstattungen verknüpft,
  Prüfsumme stimmt").
- Der echte Export wird zur Test-Fixture, aber **anonymisiert**: ein Skript ersetzt
  Namen, IBANs und Nutzernamen durch stabile Platzhalter und behält Typen, Beträge,
  Daten, MCCs und IDs. Die Rohdatei bleibt außerhalb des Repos.

### C. PayPal-CSV — nur Anreicherung

Nach Regel 1 legt PayPal keine Buchungen an. Der CSV-Export (paypal.com: Aktivitäten
→ exportieren) ist trotzdem nützlich, weil TR bei PayPal nur `PAYPAL *nutzername`
kennt, PayPal aber Name, Betreff und Gegenüber:

- Parser `PayPalExport`: deutsche Spaltennamen (Datum, Name, Typ, Brutto, Netto,
  Transaktionscode, Betreff), Dezimalkomma, Datum `TT.MM.JJJJ`.
- Jede PayPal-Zeile sucht **ihre** TR-Buchung (Betrag, Datum ±3 Tage, TR-Händler
  `PAYPAL *` oder Gutschrift von PayPal Europe). Gefunden → Händler und Notiz werden
  ergänzt („Jakob · Kinotickets"), die Kategorie bleibt. Nicht gefunden → die Zeile
  wird **verworfen**, nicht angelegt; die Zusammenfassung nennt die Anzahl.
- Ein PayPal-Export ändert keine Summe. Das ist der Test.

Priorität niedrig: Für Zweck und Gegenüber reicht in der Praxis meist die
PayPal-Mitteilung aus Kanal A, die dasselbe liefert, nur sofort.

### D. PSD2 (optional, später)

- Anbieter: Enable Banking (kostenfrei für eigene Konten, „Restricted Production",
  Registrierung als Privatentwickler). Vorher prüfen, ob TR und PayPal in deren
  ASPSP-Liste für DE/LU stehen.
- Architektur: Schlüssel im Schlüsselbund, Abruf per `BGAppRefreshTask` etwa alle
  6 h, jede neue Transaktion → `Observation` → Maschine → Posteingang. Alle 90 Tage
  Re-Consent im Browser (SCA), die App erinnert daran.
- Kein eigener Server nötig, solange nur das eigene Konto abgerufen wird.

## 6. Oberfläche

Die App bleibt minimal: drei Ebenen, jede eine Bewegung vom Vorgänger entfernt, kein
Tab-Bar, keine Einstellungsseiten mit zwanzig Zeilen.

### Ebene 1 — Vogelperspektive: Blasen

Ersetzt die Ringe als erste Seite (die Ringe bleiben als zweite Ansicht erhalten,
siehe unten). Ein Monat ist eine Fläche mit Blasen:

- **Eine Blase je Kategorie**, Fläche proportional zur Summe, Farbe = `tint`, Emoji
  in der Mitte. Bewusst vage: keine Zahl auf der Blase. Man sieht auf einen Blick,
  was groß war, nicht wie groß.
- **Drei Schwerkraftzentren** statt Sektionen: Ausgaben sammeln sich links unten,
  Einnahmen rechts oben, Investiert unten rechts. Die Blasen finden ihren Platz per
  einfacher Kräfte-Simulation (Anziehung zum Zentrum, Abstoßung untereinander, im
  Rahmen bleiben) — ~60 Zeilen, keine Bibliothek. Sie **atmen** beim Erscheinen
  (Feder, leicht gestaffelt) und schieben sich weg, wenn eine wächst.
- **Vorschläge** sind halbtransparente Blasen mit gestricheltem Rand am Rand der
  Fläche: das, was noch nicht entschieden ist. Ein Tipp öffnet den Posteingang.
- **Monat wechseln:** horizontal wischen wie heute. Die Blasen fliegen nicht neu,
  sondern wachsen und schrumpfen in ihre neuen Größen — dieselbe Kategorie bleibt
  an ihrem Ort, so wird der Vergleich zweier Monate zur Bewegung.
- **Drücken und halten** auf die Fläche: die Zahlen erscheinen kurz auf allen Blasen
  (Peek), loslassen blendet sie aus. Wer es genau wissen will, bekommt es, ohne dass
  es dauerhaft da steht.
- **Tipp auf eine Blase** → Ebene 2. Die Blase wird per `matchedGeometryEffect` zum
  Kopf der Detailansicht; alles andere weicht zurück.

Die Ringe (`FlowRings`) leben weiter als zweite Ansicht derselben Seite, erreichbar
über einen Tipp auf die Monatsangabe oder den Summenbereich: erst grob (Blasen), dann
genau (Ringe mit Zahlen, Summen, Kategorienliste). Beide zeigen dieselben Daten, die
Ringe bekommen einen dritten, innersten Ring für Investiert.

### Ebene 2 — Detail einer Kategorie

Ein Blatt, das von der Blase aufgeht. Oben die Blase als Kopf mit Zahl, darunter:

- **Verlauf**: die letzten sechs Monate als schlichte Balken, aktueller Monat betont.
  Kein Achsenbeschriftungs-Klein-Klein, nur der höchste Wert steht dran.
- **Händler**: gruppiert und nach Summe sortiert („EDEKA 4×, 143,20 €"), aufklappbar
  zu den einzelnen Buchungen. Bei Investiert: gruppiert nach Wertpapier.
- **Jede Buchung**: Betrag, Tag, Quellen-Symbol, „automatisch" als dezenter Zusatz.
  Tipp = Kategorie wechseln (lernt), Wischen = löschen oder als Umbuchung markieren.
- **Umbuchungen** haben keine Blase, sondern eine eigene kleine Zeile unter der Fläche
  („3 Umbuchungen, 111,21 €"), aufklappbar.

### Posteingang

Ein Blatt über allem, nicht eine dritte Seite. Kommt hoch, wenn man die gestrichelten
Blasen antippt oder nach einem Import:

- Je Zeile Betrag, Händler, Datum, die vorgeschlagene Kategorie als Blasen-Chip und
  die Begründung in einer Zeile. Ein Konfidenz-Punkt (satt / halb / hohl) statt
  Prozentzahlen.
- **Wischen nach rechts** = annehmen. Der Chip rastet bei 40 % Weg spürbar ein
  (`.sensoryFeedback(.selection)`), bei Loslassen davor federt er zurück, danach
  fliegt die Zeile weg und die Kategorie-Blase auf Ebene 1 wächst.
- **Tipp auf den Chip** = die drei besten Kategorien als Chips, dahinter „alle".
  Antippen bestätigt sofort; kein zweiter Schritt.
- **Wischen nach links** = ablehnen mit der Wahl „Umbuchung" / „löschen".
- „Alle sicheren annehmen" oben, mit Anzahl. Ein Tipp, ein Haptik-Schlag
  (`.impact(weight: .medium)`), Blasen wachsen nacheinander.

### Kategorienseite

Bleibt, mit drei Bereichen (Ausgaben, Einnahmen, Investiert). Unten der Abschnitt
**Konten & Import**: Stand je Konto („Trade Republic · bis 31.08."), „Export
importieren", Automatik-Schwelle als ein Regler mit drei Rasten (nie / vorsichtig /
mutig), Anleitung für die Mitteilungs-Automation.

### Liquid Glass

Das Deployment-Target geht auf **iOS 26** — auf dem Gerät läuft iOS 27, und die
Kanal-A-Automation braucht ohnehin 27. Damit ist Liquid Glass nativ, kein
Nachbau:

- Blätter (Detail, Posteingang, Ziffernblock) sind Glas: `.glassEffect()` auf dem
  Container, die Blasen der Ebene 1 scheinen unscharf durch.
- Chips, die Monatsangabe, die Summen: `.glassEffect(.regular.interactive())`, damit
  sie beim Drücken das Licht brechen und leicht nachgeben.
- Zusammengehörige Glas-Elemente (Kategorie-Chips im Posteingang) liegen in einem
  `GlassEffectContainer`, mit `glassEffectID`, damit ein Chip in den nächsten
  **morpht**, wenn man die Kategorie wechselt, statt hart zu tauschen.
- Die Blase, die zum Kopf der Detailansicht wird, trägt das Glas mit: derselbe
  Effekt, dieselbe Form, nur die Größe ändert sich.
- Kein Glas auf Glas. Die Blasenfläche selbst ist matt; Glas nur für das, was darüber
  liegt. Sonst verschwindet der Effekt im Rauschen.

### Haptik und Interaktion — Regeln, nicht Einzelfälle

Die Prinzipien aus `SKILL(1).md` (Apple, *Designing Fluid Interfaces*), auf SwiftUI
übersetzt und für jede Geste gleich:

1. **Antwort beim Berühren, nicht beim Loslassen.** Jede Blase, jeder Chip skaliert
   auf 0,97 beim Touch-down, `.sensoryFeedback(.impact(flexibility: .soft))`.
2. **1:1 und unterbrechbar.** Wischen im Posteingang, Monatswechsel, das Aufziehen
   eines Blatts: die Geometrie folgt dem Finger, Feder-Animationen
   (`.spring(response: 0.35, dampingFraction: 0.8)`) übernehmen die
   Fingergeschwindigkeit. Nichts wartet, bis eine Animation zu Ende ist.
3. **Rasten spürbar machen.** Schwellen (annehmen, Monat wechseln, Blatt schließen)
   geben `.selection`, das Überschreiten ist fühlbar, das Zurückfedern nicht.
4. **Ergebnis bestätigen.** Sichern / Annehmen: `.success`. Rückgängig: `.warning`.
   Nie Haptik für rein dekorative Bewegungen (Blasen atmen lautlos).
5. **Rubber-Banding an Grenzen.** Die Blasenfläche lässt sich leicht ziehen und
   federt zurück; der erste und letzte Monat stauchen sich beim Weiterwischen.
6. **Reduzierte Bewegung respektieren.** `accessibilityReduceMotion`: Blasen
   erscheinen ohne Federn, Morphs werden Überblendungen, Haptik bleibt.

Die Ringe, `SaveFlight` und der Ziffernblock übernehmen dieselben Regeln;
`SaveFlight` bekommt einen zweiten Zustand für Auto-Buchungen mit Rückgängig.

## 7. Reihenfolge der Umsetzung

| Phase | Inhalt | Ergebnis |
|---|---|---|
| **0** | Schema 3: neue Felder, dritte Richtung `.invest`, `MerchantMemory`, `Account`, Migration aus 2 (`merchantCategories` → `byMerchant` mit confirmed=1), Deployment-Target iOS 26, Tests. | Datei bleibt lesbar, App sieht fast unverändert aus (dritter Bereich auf der Kategorienseite). |
| **1** | Vorschlagsmaschine + Normalisierung + Lernen + die sieben Dopplungsregeln mit Prüfsumme. Reine Logik, ohne Oberfläche, gegen die anonymisierte Fixture getestet („nach 3 bestätigten EDEKA-Buchungen liegt die vierte bei ≥ 0,9", „zweiter Import ändert keine Summe", „Erstattung senkt die Kategorie"). | Kern steht, nachvollziehbar per Test. |
| **2** | TR-CSV: Parser (inkl. Sparplan, Saveback, Round-up), Share Extension, Abgleich, Posteingang mit Wisch-Haptik, Import-Zusammenfassung. | Monatsexport reinreichen → fertig kategorisiert. |
| **3** | Blasen-Übersicht, Detailansicht, Liquid Glass, Haptik-Regeln auf alle bestehenden Gesten; dritter Ring. | Die App sieht aus und fühlt sich an wie gewünscht. |
| **4** | Mitteilungs-Kanal: `SuggestEntryIntent` mit Quelle, Parser für TR- und PayPal-Texte, Automatik-Band, Anleitung auf der Kategorienseite. | Kartenzahlung → Sekunden später gebucht. |
| **5** | PayPal-CSV + Dedupe gegen TR. | PayPal vollständig. |
| **6** | PSD2 über Enable Banking, falls gewünscht. | Kein Export mehr nötig. |

Phase 0 und 1 ändern kaum Sichtbares und sind der größte Teil der Denkarbeit. Ab
Phase 2 ist die App im Alltag nutzbar, ab Phase 3 sieht sie so aus wie gedacht. Der
Mitteilungs-Kanal kommt erst danach, weil er ohne Posteingang und Blasen keinen Ort
hat, an dem seine Vorschläge landen.

## 8. Offene Punkte

Was ich brauche, bevor die jeweilige Phase startet:

1. **Screenshots von Mitteilungen** (Phase 4): TR-Kartenzahlung, TR-Gutschrift,
   TR-Lastschrift, PayPal „gesendet", PayPal „erhalten". Sonst rät der Parser.
2. **Ein PayPal-CSV-Export** von paypal.com (Phase 5, niedrige Priorität), damit
   der Parser gegen die echten Spaltennamen entsteht.
3. **Deployment-Target iOS 26** — ist das in Ordnung? Ohne Liquid Glass und ohne
   Mitteilungs-Auslöser bliebe von den beiden Wünschen wenig übrig.
4. **Eigene Konten**: Beim ersten Import fragt die App nach dem Kontoinhaber-Namen
   und zeigt die IBANs, an die Überweisungen unter diesem Namen gingen, zur
   Bestätigung als „eigenes Konto".

Geklärt durch den vollständigen Export: die Typnamen (auch Saveback), PayPal läuft
ausschließlich über TR (Karte oder Lastschrift), Round-up wird nicht genutzt.

Und mit Phase 0 wird **`CLAUDE.md`** umgeschrieben: „kein Import" und „Investments
zählen nicht" gelten nicht mehr, der Hinweis zu Mitteilungen wird präzisiert.
