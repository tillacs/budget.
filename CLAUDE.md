# CLAUDE.md — budget.

iOS-App **budget.** (Finanzen: Transaktionen importieren, kategorisieren, Budgets,
Prognose). Xcode-Projekt: `money..xcodeproj` — der Ordner-/Target-Name „money." ist
historisch, der Produktname ist **budget.**

- UI-Texte und Code-Kommentare sind **deutsch**.
- Quellcode in `money./` (`Core/`, `Persistence/`, `Views/`), Tests in `money.Tests/`.

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
