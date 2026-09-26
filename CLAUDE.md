# CLAUDE.md — budget.

iOS-App **budget.** Xcode-Projekt: `money..xcodeproj` — der Ordner-/Target-Name
„money." ist historisch, der Produktname ist **budget.**

Die App kann drei Dinge, und das ist der Entwurf, nicht ein Zwischenstand:

1. **Einlesen des Trade-Republic-Exports** (Kontoauszüge → Transaktionsexport →
   Teilen → budget., oder aus „Dateien"). `TradeRepublicExport` liest die 23 Spalten,
   `ImportPipeline` macht daraus Buchungen nach den **sieben Dopplungsregeln** aus
   `KONZEPT.md` (Abschnitt 3): `transaction_id` ist der Schlüssel, Buchungen von Hand
   werden vom Export eingelöst, Erstattungen senken ihre Ausgabe statt Einnahme zu
   sein, Saveback-Gutschrift und -Kauf sind ein Paar, Überweisungen an den
   Kontoinhaber sind Umbuchungen. Nach jedem Import eine Prüfsumme je Monat gegen
   den Export. PayPal und Mitteilungen sind **bewusst nicht** angebunden — PayPal
   läuft über die TR-Karte und steht damit im Export.
2. **Vorschläge mit Konfidenz** (`SuggestionEngine`): neun Signale, gewichtete Summe,
   Konfidenz aus Stärke und Abstand zum Zweitbesten. `MerchantMemory` ist eine
   Tabelle mit Zählungen je Händler, Wort, MCC, Gegenkonto, ISIN und Buchungstyp —
   kein Modell, nichts verlässt das Gerät. Die Maschine bucht erst selbst, wenn
   derselbe Händler zweimal bestätigt wurde (`Ranking.autoEligible`), und nur ab
   `AppData.autoThreshold`. Jede Entscheidung im Posteingang (`AppStore.accept /
   correct / reject`) lernt und bewertet die offenen Vorschläge sofort neu
   (`rerankProposals`). Eine Entscheidung über eine Händler-Gruppe zählt für Wörter
   und MCC nur einmal (`learnable`).
3. **Zwei Seiten, seitlich blätterbar** (`HomeScreen` als Pager):
   - Übersicht: Monat, Saldo, die drei Summen, dann die Blasen (`BubbleField`, eine
     je Kategorie, Fläche nach Summe, Vorschläge gestrichelt, Neutral klein und
     grau, Drücken zeigt Zahlen), darunter die Liste (`LedgerSection`) und die
     neutrale Zeile. Tipp auf eine Blase öffnet `CategoryDetailSheet`, die graue
     `NeutralSheet`. Der Posteingang (`InboxSheet`) sitzt oben links mit Zähler.
     Die Ringe gab es bis 26.09.2026; sie sind bewusst entfernt.
   - `CategoriesPage`: Kategorien in drei Bereichen, Konten & Import, Kontoinhaber
     und eigene IBANs, Automatik-Schwelle, die Kurzbefehle.

Erfassen von Hand gibt es weiterhin: `LogExpenseIntent` / `LogIncomeIntent` öffnen
den Ziffernblock (`QuickEntrySheet`), `QuickLogIntent` bucht ohne die App zu öffnen.
Zwei Fallstricke stecken dort als Kommentar im Code: `AppEntity` lässt sich zur
Laufzeit nicht auflösen (daher `CategoryOptions` als Zeichenkettenliste), und der
Zahlen-Resolver verschluckt Nachkommastellen (daher Text plus `MoneyFormat.parse`).

- UI-Texte und Code-Kommentare sind **deutsch**.
- Quellcode in `money./` (`Core/`, `Import/`, `Persistence/`, `Intents/`, `Views/`),
  Tests in `money.Tests/`, die anonymisierte Export-Fixture in `money.Tests/Fixtures/`.
  **Echte Exporte nie ins Repo** — sie enthalten Namen und IBANs (`.gitignore`).
- `Direction` hat drei Fälle: `expense`, `income`, `invest`. `Entry.kind` (`flow`,
  `transfer`, `refund`) und `Entry.status` (`confirmed`, `proposed`, `autoBooked`)
  bestimmen, was zählt: `Entry.counts`.
- `AppStore.shared` ist der einzige Speicher: Oberfläche und Kurzbefehle greifen auf
  dieselbe Instanz zu, sonst überschreiben sie sich gegenseitig die Datei.
- `AppData` (Schema 3) wird **von Hand dekodiert** (`decodeIfPresent`), damit ein
  neues Feld keine bestehende Datei unlesbar macht. Schema 2 wird gelesen und seine
  `merchantCategories` ins Gedächtnis übernommen; Schema 1 wird abgelehnt.
- Deployment-Target **iOS 26** (Liquid Glass: `glassEffect`, `.glassProminent`).
  Die Extras aus `Views/Glass.swift` sind die einzigen Glas-Bausteine; Glas nur für
  das, was über der Fläche liegt.
- Die App ist **deutsch lokalisiert** (`de.lproj`, `developmentRegion = de`).
- `Support/Info.plist` ergänzt die generierte Info.plist um die Dokumenttypen (CSV).
  Sie liegt außerhalb des synchronisierten Ordners, sonst kopiert Xcode sie doppelt.
- Simulator: `-importCSV <Pfad>` als Startargument liest eine Datei vom Mac ein
  (nur DEBUG). Achtung: In `DerivedData` liegen mehrere `money.-*`-Ordner, der
  richtige ist der zuletzt gebaute.

## Git & GitHub — verbindlich

**Alles, was fertig ist, gehört auf GitHub.** Lokale Commits allein reichen nicht:
Arbeit, die nur auf der Platte liegt, ist bei Geräteverlust weg.

1. **Nach jedem grünen Build committen und im selben Zug pushen.**
   Kein Commit bei rotem Build.
   ```
   git push -u origin "$(git branch --show-current)"
   ```
2. **Am Ende jeder Session prüfen, dass nichts unpushed liegenbleibt:**
   ```
   git status --short && git log --oneline @{u}.. 2>/dev/null
   ```
   Beides leer = alles gesichert.
3. **Remote bitte via SSH** (`git@github.com:tillacs/<repo>.git`) — HTTPS scheitert
   auf diesem Rechner mit 403, weil das Token im Schlüsselbund veraltet ist.
4. **Stagen immer gezielt** per `git add "<Pfad>"`, nie `git add .` / `git add -A`.
5. Force-Push, `reset --hard` auf gepushte Commits und das Löschen fremder Branches
   nur nach ausdrücklicher Rückfrage.

## Build & Test

```
xcodebuild -project "money..xcodeproj" -scheme "money." -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project "money..xcodeproj" -scheme "money." -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:money.Tests test
```
