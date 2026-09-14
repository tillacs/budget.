# CLAUDE.md — budget.

iOS-App **budget.** Xcode-Projekt: `money..xcodeproj` — der Ordner-/Target-Name
„money." ist historisch, der Produktname ist **budget.**

Die App kann genau zwei Dinge, und das ist der Entwurf, nicht ein Zwischenstand:

1. **Erfassen über Kurzbefehl.** `LogExpenseIntent` / `LogIncomeIntent` öffnen die App
   direkt im Ziffernblock (`QuickEntrySheet`). Gedacht für „Auf Rückseite tippen →
   Doppeltippen". Der `QuickEntryRouter` ist die Brücke vom Intent in die Oberfläche.
2. **Eine einzige Seite** (`HomeScreen`): zwei Ringe (`FlowRings`, außen Ausgaben,
   innen Einnahmen, gemeinsamer Maßstab), die Summen, die Kategorienliste
   (`LedgerSection`) und darunter aufklappbar jede einzelne Buchung.

Es gibt **keinen Import, keine Regeln, keinen Klassifikator, keine Budgets** — das war
Schema 1 und ist bewusst entfernt worden. Kategorien legt der Nutzer selbst an.

- UI-Texte und Code-Kommentare sind **deutsch**.
- Quellcode in `money./` (`Core/`, `Persistence/`, `Intents/`, `Views/`),
  Tests in `money.Tests/`.

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
xcodebuild -project "money..xcodeproj" -scheme "money." -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```
