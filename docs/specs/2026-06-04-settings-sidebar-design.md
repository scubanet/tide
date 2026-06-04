# Tide — Settings-Sidebar — Design-Spec

**Datum:** 04. Juni 2026
**Status:** Design abgesegnet (Dominik), bereit für Implementation-Plan

---

## Problem

Das Settings-Fenster nutzt eine `TabView` mit inzwischen **8 Tabs** (API,
Hotkey, Modell, Stimme, Diktat, Vokabular, Lokal, Actions). Bei 520 pt Breite
passen nicht alle in die Tab-Leiste — SwiftUI klappt den Überlauf in ein
hässliches „» Navigation Tab Bar"-Dropdown. Schlecht erreichbar, sieht kaputt
aus.

## Ziel

`TabView` durch eine **gruppierte Sidebar** (`NavigationSplitView`) ersetzen:
Sektions-Liste links (mit Gruppen-Headern wie in den macOS-Systemeinstellungen),
Inhalt rechts. Skaliert auf beliebig viele Sektionen, kein Überlauf.

Nicht-Ziel: Inhalt der 8 Section-Views ändern, Settings-Persistenz, Suche.

## Architektur

### `SettingsTab` (enum)
Neuer `enum SettingsTab: String, CaseIterable, Identifiable` mit allen acht
Sektionen. Pro Case:
- `label: String` (Sidebar-Titel)
- `systemImage: String` (bestehende Tab-Icons: `key`, `keyboard`, `cpu`,
  `waveform`, `mic.fill`, `character.book.closed`, `internaldrive`, `bolt`)

### `SettingsWindow` umbauen
`var body` von `TabView { … }` zu:

```swift
NavigationSplitView {
  List(selection: $selection) {
    Section("Allgemein") { row(.api); row(.model) }
    Section("Sprache")   { row(.voice); row(.vocabulary); row(.local) }
    Section("Diktat")    { row(.hotkey); row(.dictation) }
    Section("Erweitert") { row(.actions) }
  }
  .listStyle(.sidebar)
  .navigationSplitViewColumnWidth(min: 170, ideal: 185, max: 220)
} detail: {
  detailView(for: selection)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

- `row(_:)` = `Label(tab.label, systemImage: tab.systemImage).tag(tab)`.
- `selection: SettingsTab` als `@State`, default `.api`.
- `detailView(for:)` = `switch` über `SettingsTab`, gibt die bestehende
  Section-View zurück (`ApiKeySection()`, `HotkeySection()`, …).
- Die Detail-Views, die `Form`/lange Inhalte haben, behalten ihren eigenen
  Scroll (Form scrollt selbst). Kein zusätzlicher ScrollView nötig, falls die
  Section schon eine `Form` ist — wird beim Bauen pro View geprüft.

### Gruppen-Zuordnung (Sidebar-Sections)
| Gruppe | Sektionen |
|---|---|
| Allgemein | API, Modell |
| Sprache | Stimme, Vokabular, Lokal |
| Diktat | Hotkey, Diktat |
| Erweitert | Actions |

**Single source:** `static let groups: [(title: String, tabs: [SettingsTab])]`
auf `SettingsTab`. Die Sidebar-`List` rendert über `groups` (eine `Section` je
Eintrag), und der Test prüft `groups`-Invarianten (Vereinigung == allCases,
keine Dopplung). Kein Drift zwischen UI und Test.

### Fenstergröße
`.frame` von `520×380` auf `640×460` (Sidebar ~185 + Detail ~440 + Padding).
`.navigationSplitViewStyle(.balanced)` damit beide Spalten sichtbar bleiben.
Die bisherige `.padding(20)` am Root entfällt — `NavigationSplitView` bringt
eigene Insets; ein Außen-Padding würde die Sidebar-Optik brechen.

### State / Verhalten
- Settings öffnet immer mit `.api` selektiert (kein Persist — Welle-Scope).
- Sidebar-Auswahl ist nicht-optional (`SettingsTab`, kein `SettingsTab?`) —
  es ist immer genau eine Sektion aktiv.

## Fehlerbehandlung

Kein neuer Laufzeit-Pfad. Reiner View-Umbau.

## Tests

- `SettingsTabTests` (neu, `TideTests`): `SettingsTab.allCases.count == 8`;
  jeder Case hat nicht-leeres `label` und nicht-leeres `systemImage`; die vier
  Gruppen decken zusammen genau alle acht Cases ab (eine Liste der vier
  Gruppen-Arrays, deren Vereinigung == `Set(allCases)`, keine Dopplung).
- Rest: Build + manueller Smoke (keine „»"-Overflow-Leiste mehr, alle 8
  Sektionen über die Sidebar erreichbar, Inhalt rechts korrekt).

## Implementation-Qualität

Bei der Umsetzung den **`swiftui-pro`-Skill** für Review nutzen (moderne
`NavigationSplitView`-/`List(selection:)`-APIs, keine deprecated Muster,
korrekte Column-Width-Modifier).

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `Tide/Settings/SettingsTab.swift` | **neu** — enum (label + systemImage) + Gruppen-Definition |
| `Tide/Settings/SettingsWindow.swift` | `TabView` → `NavigationSplitView` + Sidebar + Detail-Switch + Fenstergröße |
| `TideTests/SettingsTabTests.swift` | **neu** — enum/Gruppen-Invarianten |
| `CHANGELOG.md` | Unreleased-Eintrag |
