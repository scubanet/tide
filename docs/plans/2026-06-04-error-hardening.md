# Error Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface silently-swallowed errors via OSLog (KeychainHelper get/delete status, ConversationStore.activeConversation fetch, ChatViewModel append/startNew) and distinguish keychain item-not-found from real errors — logging-only, no public-signature changes.

**Architecture:** Behaviour-preserving observability hardening. `get` still returns nil and `delete`/`activeConversation` keep their signatures; they just log unexpected failures instead of dropping them. No new behaviour ⇒ no new red-green tests; the existing Core test suite (KeychainHelperTests, ConversationStoreTests — already cover round-trip / missing-key / empty-store) must stay green.

**Tech Stack:** Swift 6, OSLog, XCTest. Core tests: `cd Packages/Core && swift test`. App build: `xcodebuild … CODE_SIGNING_ALLOWED=NO`.

**Branch:** Vor Task 1: `git checkout -b feat/error-hardening`

---

## Task 1: KeychainHelper + ConversationStore — log instead of swallow

**Files:**
- Modify: `Packages/Core/Sources/Core/Security/KeychainHelper.swift`
- Modify: `Packages/Core/Sources/Core/Persistence/ConversationStore.swift`

No new tests (behaviour unchanged; the existing CoreTests cover the contract). Verify they stay green.

- [ ] **Step 1: KeychainHelper — status distinction + logging**

In `KeychainHelper.swift`:

(a) Add `import OSLog` at the top (alongside `import Foundation` / `import Security`) and a logger inside the enum:
```swift
  private static let log = Logger(subsystem: "swiss.weckherlin.tide", category: "keychain")
```

(b) Replace `get(key:)`'s tail (the `guard status == errSecSuccess …` line) with explicit status handling:
```swift
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard let data = result as? Data else { return nil }
      return String(data: data, encoding: .utf8)
    case errSecItemNotFound:
      return nil
    default:
      // A locked or errored keychain (e.g. errSecInteractionNotAllowed)
      // is NOT the same as "no key set" — surface it so it's diagnosable.
      log.warning("keychain get '\(key, privacy: .public)' failed: \(status)")
      return nil
    }
```

(c) Replace `delete(key:)`'s `SecItemDelete(query as CFDictionary)` line with status handling:
```swift
    let status = SecItemDelete(query as CFDictionary)
    switch status {
    case errSecSuccess, errSecItemNotFound:
      break
    default:
      log.warning("keychain delete '\(key, privacy: .public)' failed: \(status)")
    }
```

- [ ] **Step 2: ConversationStore — log fetch failures**

In `ConversationStore.swift`:

(a) Add `import OSLog` and a logger:
```swift
  private static let log = Logger(subsystem: "swiss.weckherlin.tide", category: "store")
```

(b) Replace `activeConversation()`'s `try?` return:
```swift
    return (try? context.fetch(descriptor))?.first
```
with:
```swift
    do {
      return try context.fetch(descriptor).first
    } catch {
      // A fetch error is NOT "no conversations" — log it so a transient
      // store failure that would orphan history is visible.
      Self.log.warning("activeConversation fetch failed: \(error.localizedDescription, privacy: .public)")
      return nil
    }
```

- [ ] **Step 3: Build + run Core tests**

Run: `cd Packages/Core && swift test 2>&1 | tail -8`
Expected: PASS — all existing CoreTests green (KeychainHelperTests round-trip/missing/delete, ConversationStoreTests empty/start-new, etc.).

- [ ] **Step 4: Commit**

```bash
git add Packages/Core/Sources/Core/Security/KeychainHelper.swift \
        Packages/Core/Sources/Core/Persistence/ConversationStore.swift
git commit -m "fix(core): log keychain/store failures instead of swallowing them

KeychainHelper.get/delete now distinguish item-not-found from real
errors (a locked keychain no longer looks like 'no key'); both log
unexpected OSStatus. ConversationStore.activeConversation logs fetch
errors instead of silently returning nil (which orphaned history).
Signatures unchanged.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: ChatViewModel — log persistence failures

**Files:** `Tide/Panel/ChatViewModel.swift`

- [ ] **Step 1: Add a logger + replace the swallowed `try?`**

In `Tide/Panel/ChatViewModel.swift`:

(a) Add `import OSLog` near the existing imports (the file already `import Core`). Add a logger property to the class (e.g. just after the stored properties):
```swift
  private static let log = Logger(subsystem: "swiss.weckherlin.tide", category: "chat")
```

(b) Replace each swallowed call. The three `try? conversationStore.append(...)` (currently at ~lines 129, 133, 189) become:
```swift
    do { try conversationStore.append(userMsg, to: conv) }
    catch { Self.log.warning("append user message failed: \(error.localizedDescription, privacy: .public)") }
```
```swift
    do { try conversationStore.append(assistantMsg, to: conv) }
    catch { Self.log.warning("append assistant message failed: \(error.localizedDescription, privacy: .public)") }
```
```swift
      do { try conversationStore.append(assistantMsg, to: conv) }
      catch { Self.log.warning("persist assistant message failed: \(error.localizedDescription, privacy: .public)") }
```
(match each existing call site — there are two `assistantMsg` appends; use the wording above for the first occurrence in `send()` and the post-stream one respectively; the exact text doesn't matter, only that the catch logs.)

And the `startNew()` swallow `_ = try? conversationStore.startNew()` becomes:
```swift
    do { _ = try conversationStore.startNew() }
    catch { Self.log.warning("startNew failed: \(error.localizedDescription, privacy: .public)") }
```

Read the file first and replace exactly the four `try?` sites; leave all other logic (the `try?` is the only change). The send-flow must still proceed (the bubble stays visible) — only the swallow becomes a logged catch.

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild build -project Tide.xcodeproj -scheme Tide -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Tide/Panel/ChatViewModel.swift
git commit -m "fix(chat): log conversation persistence failures instead of swallowing

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: CHANGELOG

**Files:** `CHANGELOG.md`

- [ ] **Step 1:** Under `## [Unreleased]` → `### Fixed`, add:

```markdown
- **Fehler-Sichtbarkeit** — still verschluckte Fehler werden jetzt geloggt:
  `KeychainHelper` unterscheidet „Key nicht vorhanden" von echten Keychain-
  Fehlern (ein gesperrter Keychain sieht nicht mehr wie „kein Key" aus),
  `delete` prüft den Status, und Konversations-Persistenz-Fehler (Fetch/Append)
  landen im Log statt stillschweigend History zu verlieren.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for error hardening

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** Keychain get/delete + ConversationStore (T1), ChatViewModel appends/startNew (T2), changelog (T3). All covered.
- **Behaviour-preserving:** every return value/signature is unchanged; only the silent-drop paths gain an OSLog warning + (for keychain) an explicit `errSecItemNotFound` branch. Existing CoreTests therefore stay green without modification.
- **No new tests:** the contract (round-trip, missing-key→nil, empty-store→nil) is already covered by KeychainHelperTests/ConversationStoreTests; the logging itself isn't unit-testable. Verified by green existing suites + build.
- **Privacy:** keychain keys logged `.public` are stable identifiers (`anthropic.api_key`), NOT secrets; values are never logged.
```
