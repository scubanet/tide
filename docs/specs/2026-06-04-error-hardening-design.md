# Tide — Error-Hardening — Design-Spec

**Datum:** 04. Juni 2026
**Status:** Design abgesegnet (Dominik), bereit für Implementation-Plan
**Herkunft:** App-Audit (MEDIUM-Findings: still verschluckte Fehler in
Keychain/Persistenz).

---

## Problem

Mehrere Stellen verschlucken echte Fehler still und sind dadurch nicht
diagnostizierbar:

1. **`KeychainHelper.get`** gibt `nil` bei **jedem** Nicht-Erfolg zurück — ein
   gesperrter/fehlerhafter Keychain (`errSecInteractionNotAllowed`) sieht aus
   wie „kein Key gesetzt". Das kann fälschlich das Onboarding triggern.
2. **`KeychainHelper.delete`** ignoriert den `OSStatus` komplett — ein
   fehlgeschlagenes „Zurücksetzen" meldet trotzdem Erfolg.
3. **`ConversationStore.activeConversation`** nutzt `try?` → ein Fetch-Fehler
   ist ununterscheidbar von „keine Konversation" → `send()` startet still eine
   neue und verwaist die History.
4. **`ChatViewModel`** swallowt drei `try? conversationStore.append(...)` —
   ein Persist-Fehler bleibt unsichtbar; eine Konversation kann mit fehlenden
   Nachrichten gespeichert werden.

## Ziel

Diese Fehler **sichtbar machen** (OSLog-Warnings) statt sie zu verschlucken,
und `KeychainHelper.get`/`delete` zwischen „nicht vorhanden" und „echter
Fehler" unterscheiden — **ohne** öffentliche Signaturen zu ändern (kein
Ripple).

Nicht-Ziel (eigene größere Refactors): throwing Keychain-/Store-APIs, das
`AppSettings`-`@Observable`-Redesign.

## Komponenten & Fixes

### `KeychainHelper` (`Packages/Core/Sources/Core/Security/KeychainHelper.swift`)
- Neuer `private let log = Logger(subsystem: "swiss.weckherlin.tide", category: "keychain")`.
- **`get(key:) -> String?`**: nach `SecItemCopyMatching` den Status auswerten:
  - `errSecSuccess` + decodebare Data → Wert.
  - `errSecItemNotFound` → `nil` (erwartet, kein Log).
  - sonst → `log.warning("keychain get '<key>' failed: <status>")` + `nil`.
  Signatur unverändert.
- **`delete(key:)`**: `SecItemDelete`-Status auswerten:
  - `errSecSuccess` / `errSecItemNotFound` → still ok.
  - sonst → `log.warning("keychain delete '<key>' failed: <status>")`.
  Bleibt non-throwing.

### `ConversationStore` (`Packages/Core/Sources/Core/Persistence/ConversationStore.swift`)
- Neuer `private static let log = Logger(subsystem: "swiss.weckherlin.tide", category: "store")`.
- **`activeConversation()`**: `try?` durch do/catch ersetzen — bei Fehler
  `log.warning("activeConversation fetch failed: <error>")` und `nil`
  zurückgeben. Rückgabetyp `Conversation?` unverändert. (Surfact den Orphan-
  Fall im Log; verhindert ihn nicht aktiv — bewusst, Scope.)

### `ChatViewModel` (`Tide/Panel/ChatViewModel.swift`)
- Bestehenden `Logger` nutzen oder einen hinzufügen
  (`category: "chat"`).
- Die drei `try? conversationStore.append(...)` durch do/catch ersetzen, die
  bei Fehler `log.warning("append failed: <error>")` loggen. Der Sende-Flow
  läuft weiter (die Bubble bleibt sichtbar); nur das stille Verschlucken
  entfällt. (Falls `startNew()` o.ä. ebenfalls `try?` nutzt und in Scope passt,
  gleich behandeln — aber NUR die append-Swallows sind Pflicht.)

## Tests

- **`KeychainHelperTests`** (neu oder erweitern, CoreTests):
  - `get` für einen nicht-gesetzten Key → `nil` (kein Crash, kein false-positive).
  - set → get round-trip → Wert; delete → get → `nil`.
  (Echte Fehler-Stati wie `errSecInteractionNotAllowed` sind im Test nicht
  erzwingbar; nur der itemNotFound- + happy-Pfad.)
- **`ConversationStoreTests`** (bestehend bleibt grün): ein Test, dass
  `activeConversation()` bei leerem (in-memory) Store `nil` liefert.
- Logging-Pfade selbst sind nicht unit-testbar → Build + Code-Review.

## Betroffene Dateien

| Datei | Fix |
|---|---|
| `Packages/Core/Sources/Core/Security/KeychainHelper.swift` | get/delete Status + Logging |
| `Packages/Core/Tests/CoreTests/KeychainHelperTests.swift` | get/round-trip Tests |
| `Packages/Core/Sources/Core/Persistence/ConversationStore.swift` | activeConversation do/catch + Log |
| `Packages/Core/Tests/CoreTests/ConversationStoreTests.swift` | empty-store Test |
| `Tide/Panel/ChatViewModel.swift` | append-Swallows → do/catch + Log |
| `CHANGELOG.md` | Eintrag |
