# FlowDictate → NativeDictate – Rebranding-Arbeitsplan

**Vorhaben:** Umbenennung des Open-Source-Projekts und der sichtbaren macOS-App von FlowDictate zu NativeDictate
**Status:** `ERLEDIGT` – R0 bis R7 abgeschlossen; optionales R8 in Arbeit
**Stand:** 8. Oktober 2026
**Ausgangsbasis:** FlowDictate 4.1.0, Build 33, Tag `v4.1.0`, Commit `afa02eb`
**Zielversion:** NativeDictate 4.2.0
**Geplanter Arbeitsbranch:** `codex/rebrand-native-dictate`
**Ausgangs-Repository:** `Hank1210/FlowDictate`
**Aktuelles Repository:** `Hank1210/NativeDictate`
**Kanonische Schreibweise:** `NativeDictate`
**Ablage:** öffentlich und versioniert unter `docs/engineering/`

## 1. Zweck

Dieser Plan beschreibt die kontrollierte Umbenennung von FlowDictate zu NativeDictate. Das Rebranding soll die Verwechslung mit einem unabhängigen kommerziellen Produkt beenden, ohne bestehende Installationen erneut unnötig von Einstellungen, History, lokalem Modell, Keychain-Zugang oder Ordnerfreigaben zu trennen.

Der Plan behandelt das Rebranding als eigenständige, möglichst verhaltensneutrale 4.2-Arbeit. Neue Produktfunktionen, Datenbankschemata und Architekturumbauten werden nicht mit der Umbenennung vermischt. Sichtbare Produktidentität, technische App-Identität, persistente Datenpfade und historische Dokumentation werden ausdrücklich getrennt bewertet.

## 2. Statuslegende und Arbeitsregel

| Status | Bedeutung |
|---|---|
| `OFFEN` | noch nicht begonnen |
| `IN ARBEIT` | lokale Änderungen vorhanden, Exit noch nicht erreicht |
| `GATE` | Entscheidung oder Nachweis ist vor dem Folgeschritt erforderlich |
| `ERLEDIGT` | Implementierung, Tests und Exit-Kriterium sind erfüllt |
| `BLOCKIERT` | ein dokumentierter technischer oder externer Blocker verhindert den nächsten Schritt |

Ein Schritt wird erst `ERLEDIGT`, wenn seine Code-, Dokumentations-, Test- und Migrationskriterien erfüllt sind. Ein grüner Build allein schließt keinen Schritt ab.

Für jeden abgeschlossenen Schritt gilt:

1. Rebranding und Funktionsentwicklung nicht vermischen.
2. Historische Tags, Releases und wahrheitsgemäße alte Dokumente nicht rückwirkend umschreiben.
3. Persistente Legacy-Identifier nur nach ausdrücklicher Migrationsentscheidung ändern.
4. Keine Benutzerdateien, Container oder Keychain-Einträge im Zuge des Rebrandings löschen.
5. Keine Veröffentlichung, bevor Upgrade und Neuinstallation getrennt geprüft wurden.
6. `git diff --check`, vollständige Testsuite und Paketprüfung sind für jeden Releasekandidaten Pflicht.

## 3. Verbindliche Entscheidungen

### 3.1 Neue öffentliche Identität

- Der sichtbare Produkt- und Projektname lautet ausschließlich `NativeDictate`.
- `Native Dictate` und `Native Dictation` werden nicht als wechselnde Markenschreibweisen verwendet.
- Der englische Kurztext lautet zunächst: `Open-source dictation and meeting transcription for macOS.`
- Die technische Produktbeschreibung darf ergänzen: `Native macOS dictation with local or BYOK transcription.`
- Es wird keine Domain vorausgesetzt oder registriert; GitHub bleibt die kanonische Projekt- und Downloadadresse.
- Es wird keine Markenregistrierung behauptet.

### 3.2 GitHub-Vertrag

- Es wird kein zweites leeres Repository angelegt.
- Das bestehende Repository wird erst kurz vor der 4.2-Veröffentlichung von `Hank1210/FlowDictate` in `Hank1210/NativeDictate` umbenannt.
- Issues, Tags, Releases, Stars, Followers und Git-Historie bleiben im bestehenden Repository.
- Das alte Repository `Hank1210/FlowDictate` wird nach der Umbenennung nicht neu angelegt, damit GitHub-Weiterleitungen erhalten bleiben.
- Lokale Remotes und alle hart codierten Repository-URLs werden auf das neue Ziel aktualisiert.
- GitHub Pages ist nicht Bestandteil des Rebrandings.

### 3.3 Technischer Kompatibilitätsvertrag

Folgende Identitäten und Pfade bleiben in NativeDictate 4.2.0 absichtlich unverändert:

- Bundle-Identifier `de.mcc.FlowDictate`,
- bestehende macOS-Container- und UserDefaults-Identität,
- Keychain-Service auf Basis des Bundle-Identifiers,
- persistente `Application Support/FlowDictate`-Pfade,
- History-, Jobs-, Profile-, Smart-Dictation-, Modell- und Transkriptionsverzeichnisse,
- gespeichertes Recording-Folder-Bookmark,
- vorhandene Serial-Queue-, Logger- und interne Diagnose-Identifier, soweit sie nicht benutzersichtbar sind.

Diese Legacy-Namen sind keine fortgesetzte öffentliche Produktbezeichnung, sondern Kompatibilitätsanker. Sie dürfen dauerhaft bestehen bleiben. Eine spätere Bundle-ID-Änderung ist ein separates Migrationsprojekt und kein Rebranding-Nachlauf.

### 3.4 Historischer Vertrag

Unverändert bleiben:

- Tags bis einschließlich `v4.1.0`,
- bereits veröffentlichte Release-Titel und Release-Archive,
- alte Checksummen,
- historische Release Notes und abgeschlossene PRDs,
- Git-Committexte und Git-Historie,
- historische Aussagen, die sich ausdrücklich auf eine damalige FlowDictate-Version beziehen.

Aktuelle Einstiegsdokumente dürfen auf die Umbenennung hinweisen und auf historische Dokumente verlinken. Historische Dateien werden nur korrigiert, wenn sie unabhängig vom Rebranding sachlich falsch oder sicherheitskritisch sind.

## 4. Ausgangslage und Inventar

Am 2. Oktober 2026 enthielt das Repository bei einer ersten Inventur 686 Fundzeilen in 75 Dateien für `FlowDictate`, `de.mcc.FlowDictate` oder `de.euler.FlowDictate`. Der reproduzierte R0-Snapshot vom 3. Oktober 2026 enthält nach Aufnahme des vollständigen Rebranding-Plans 710 Fundzeilen in weiterhin exakt 75 Ausgangsdateien. Die vollständige Dateiklassifikation liegt maschinenlesbar in `docs/engineering/REBRANDING_NAME_INVENTORY.tsv`; die Inventardatei selbst ist kein Bestandteil ihres eigenen Scans.

Die Treffer gehören mindestens zu diesen Gruppen:

| Gruppe | Beispiele | Behandlung |
|---|---|---|
| sichtbare App-Texte | Fenster, Menüs, Onboarding, Fehlermeldungen | in 4.2 umbenennen |
| aktuelle Dokumentation | README, Features, Installation, Privacy, Release Guide | in 4.2 umbenennen und Migration erklären |
| Releasepaket | App-Name, ZIP, Checksummenname, enthaltene Anleitungen | in 4.2 umbenennen |
| Repository-Verweise | README-Links, Release-API, Downloadlinks | zum Umschaltzeitpunkt aktualisieren |
| persistente Pfade | `Application Support/FlowDictate`, Modelle, History, Jobs | als Legacy-Vertrag beibehalten |
| technische Identität | `de.mcc.FlowDictate`, Keychain-Service | beibehalten |
| interne Typen und Dateinamen | `FlowDictateApp`, `FlowDictateMenu`, Xcode-Scheme | optional später bereinigen |
| historische Dokumente | alte PRDs und Release Notes | nicht global ersetzen |
| alte Identität | `de.euler.FlowDictate` in 4.1-Migrationshinweisen | historisch beibehalten |

Vor der Umsetzung wird aus diesem Inventar eine maschinenprüfbare Allowlist für zulässige Legacy- und Historientreffer abgeleitet. Ein globales Suchen-und-Ersetzen ist ausdrücklich ausgeschlossen.

## 5. Zielbild und Reihenfolge

```text
4.1.0 Releasebasis
       │
       ▼
Namens- und Kompatibilitätsvertrag
       │
       ▼
Sichtbare App-Identität + aktuelle Dokumentation
       │
       ▼
Packaging + Upgradepfad + automatisierte Tests
       │
       ▼
Manueller 4.1.0-→4.2.0-Migrationstest
       │
       ▼
GitHub-Repository umbenennen + URLs umstellen
       │
       ▼
NativeDictate 4.2.0 Release-Gate
       │
       ▼
Optionale interne Namensbereinigung in späteren Versionen
```

| Schritt | Status | Voraussetzung | Entsperrt |
|---|---|---|---|
| R0 Vertrags- und Baseline-Gate | `ERLEDIGT` | 4.1.0 | sichere Arbeitsbasis |
| R1 Identitätsgrenzen und Regressionstests | `ERLEDIGT` | R0 | geschützte Legacy-Verträge |
| R2 sichtbare Produktumbenennung | `ERLEDIGT` | R1 | NativeDictate-Appoberfläche |
| R3 Packaging und Installationsmigration | `ERLEDIGT` | R2 | testbares 4.2-Paket |
| R4 aktuelle Dokumentation und Historiengrenze | `ERLEDIGT` | R2 | konsistente Projektkommunikation |
| R5 automatisierte und manuelle Migrationstests | `ERLEDIGT` | R3, R4 | Freigabe für GitHub-Umschaltung |
| R6 GitHub-Umschaltung | `ERLEDIGT` | R5 | kanonische neue Projektadresse |
| R7 Release-Gate NativeDictate 4.2.0 | `ERLEDIGT` | R6 | Veröffentlichungsentscheidung |
| R8 optionale interne Bereinigung | `IN ARBEIT` | stabiler 4.2-Nachweis | langfristige Codekonsistenz |

## 6. R0 – Vertrags- und Baseline-Gate

**Status:** `ERLEDIGT`

### 6.1 Arbeiten

- Arbeitsbranch `codex/rebrand-native-dictate` von Tag `v4.1.0` beziehungsweise Commit `afa02eb` erstellen.
- Prüfen, dass `main`, `origin/main` und `v4.1.0` weiterhin auf der dokumentierten Basis liegen.
- Vollständige Testsuite auf der unveränderten Basis ausführen.
- Aktuelle Community-Release-Erstellung einmal unverändert verifizieren oder den letzten akzeptierten 4.1-Nachweis referenzieren.
- Namens-, GitHub-, Bundle-ID-, Speicher- und Historienverträge dieses Plans reviewen.
- Umfang der 75 Funddateien erneut ermitteln und nach den Gruppen aus Abschnitt 4 klassifizieren.

### 6.2 Nicht erlaubt

- keine neue Produktfunktion,
- keine Schemaänderung,
- keine Bundle-ID-Änderung,
- keine GitHub-Umbenennung,
- kein globales Ersetzen aller Vorkommen.

### 6.3 Nachweis vom 3. Oktober 2026

- Der Branch `codex/rebrand-native-dictate` wurde direkt auf dem aufgelösten Tagziel `v4.1.0^{}` beziehungsweise Commit `afa02eb451b03b0a2cfb63a0e7bfad058ac53feb` angelegt.
- Der Live-Abgleich mit GitHub zeigte zwei nach der Veröffentlichung auf `main` hinzugekommene README-only-Commits: `3c11274` und `1c1f5ad`. Sie ergänzen ein Installationsvideo und bereinigen Leerzeilen; App-Code, Paketierung und technische Identitäten bleiben unverändert. Der Arbeitsbranch wurde daraufhin per Fast-Forward mit `main` und `origin/main` synchronisiert. Sein Merge-Base mit `v4.1.0` bleibt exakt `afa02eb`.
- Die vollständige serielle macOS-Suite lief mit `SWT_USE_SERIAL_EXECUTION=1` und deaktiviertem Xcode-Paralleltesting: 222 von 222 Tests bestanden, 0 Fehler, 0 Skips und 0 Runtime-Warnungen auf macOS 26.7.1. Der Ergebnisbundle-Titel lautet `Test - FlowDictate`.
- Ein vorausgegangener paralleler Standardlauf zeigte auf demselben unveränderten Quellstand zwei nicht reproduzierte Last-/Timingfehler in `historyStoreHandlesOneThousandRecordsIncludingMeetingSummaries()` und `openAIReturnsBeforeSlowTemporaryFileCleanupFinishes()`. Beide sind in der für den bisherigen Release-Nachweis maßgeblichen seriellen Gesamtsuite bestanden. Der erste Build meldete außerdem eine bestehende Swift-Actor-Isolation-Compilerwarnung am Defaultwert von `makeCoordinatorHarness`; dies ist keine Runtime-Warnung und wurde in R0 nicht mit einer Codeänderung vermischt.
- Das vorhandene, bereits veröffentlichte Build-33-Artefakt wurde nicht neu gebaut. Die lokale Datei `dist/FlowDictate-4.1.0-Community-macOS.zip` besteht ihre Prüfsummendatei weiterhin mit SHA-256 `e22b1b4d73e0cea50986569bc14bc16ea0dd0be37a48b4e7b09ece12906b5002`. Der übrige akzeptierte Paket- und Realtestnachweis bleibt in `RELEASE.md` und `docs/releases/RELEASE_NOTES_4.1.0.md` erhalten.
- Der Namensscan umfasst 75 Ausgangsdateien und 710 Fundzeilen. `docs/engineering/REBRANDING_NAME_INVENTORY.tsv` ordnet jede Datei genau einer der Kategorien `sichtbar`, `aktuell`, `legacy`, `historisch` oder `optional intern` zu und dokumentiert für Mischdateien zusätzlich, welche geschützten Werte erhalten bleiben müssen.
- Mit der Freigabe dieses Plans sind Namens-, GitHub-, Bundle-ID-, Speicher- und Historienvertrag ausdrücklich bestätigt. R0 hat keine Produktfunktion, kein Schema, keine Bundle-ID, keine GitHub-Adresse und keine Nutzerdaten verändert.

### 6.4 Exit

- [x] Arbeitsbranch basiert exakt auf dem akzeptierten 4.1.0-Stand.
- [x] Baseline-Tests sind grün und dokumentiert.
- [x] Jede Funddatei besitzt eine Zielkategorie: `sichtbar`, `aktuell`, `legacy`, `historisch` oder `optional intern`.
- [x] Die Kompatibilitätsentscheidungen sind ausdrücklich bestätigt.

## 7. R1 – Identitätsgrenzen und Regressionstests

**Status:** `ERLEDIGT`

### 7.1 Ziel

Vor sichtbaren Umbenennungen werden die Werte geschützt, die bestehende Installationen zusammenhalten. Tests sollen verhindern, dass eine spätere mechanische Umbenennung versehentlich Bundle-ID, Keychain-Service oder Speicherorte ändert.

### 7.2 Arbeiten

- Bestehende Produkt- und Persistenzkonstanten erfassen und, soweit sinnvoll, zentralisieren.
- Einen klaren Unterschied zwischen `displayName = NativeDictate` und Legacy-Identifiern herstellen.
- Regressionstests beziehungsweise Buildprüfungen ergänzen für:
  - Bundle-Identifier `de.mcc.FlowDictate`,
  - Keychain-Service,
  - History-Pfad,
  - Modell-Pfad,
  - Jobs-, Profile- und Smart-Dictation-Pfade,
  - Transkriptionssession-Pfad,
  - Recording-Folder-Bookmark und UserDefaults-Kontinuität.
- Sicherstellen, dass 4.2 keine Datenmigration allein aufgrund des neuen Anzeigenamens auslöst.
- Zulässige Legacy-Vorkommen in einer prüfbaren Liste dokumentieren.

### 7.3 Voraussichtlich betroffene Dateien

- `FlowDictate.xcodeproj/project.pbxproj`
- `NativeDictate/Settings/KeychainCredentialStore.swift`
- `NativeDictate/History/DictationHistoryStore.swift`
- `NativeDictate/Jobs/DictationJobStore.swift`
- `NativeDictate/Profiles/AppDictationProfile.swift`
- `NativeDictate/SmartDictation/SmartDictationStores.swift`
- `NativeDictate/Transcription/Local/LocalModelManager.swift`
- `NativeDictate/Transcription/LongForm/TranscriptionSessionStore.swift`
- `NativeDictate/Audio/AudioStore.swift`
- `NativeDictateTests/NativeDictateTests.swift`

### 7.4 Nachweis vom 3. Oktober 2026

- `ProductIdentity.displayName` definiert den künftigen sichtbaren Namen unabhängig von `ProductIdentity.Legacy`. Unter `Legacy` stehen die unveränderte Produktions-Bundle-ID `de.mcc.FlowDictate`, die Testhost-ID, der Keychain-Service, die Application-Support-Wurzel sowie die beiden Recording-Folder-Defaults-Schlüssel.
- Audio, History, Jobs, App-Profile, Dictionary, Writing Styles, lokales Modell und Long-Form-Transkriptionssessions beziehen ihre Standardpfade nun aus den zentralen Legacy-Konstanten. Das ist eine verhaltensneutrale Quellzentralisierung; die resultierenden Pfade sind bytegenau dieselben wie in 4.1.0.
- `KeychainCredentialStore` verwendet den expliziten Legacy-Service statt den Service aus dem sichtbaren Produktnamen abzuleiten. `RecordingLocationStore` verwendet weiterhin `recordingDirectoryBookmark` und `recordingDirectoryDisplayPath` im unveränderten UserDefaults-Container.
- Vier neue Regressionstests sichern Anzeigename-Entkopplung, Bundle- und Testhost-ID im Xcode-Projekt, Keychain-Service, alle acht Standardpfade, Bookmark-Schlüssel sowie die Gültigkeit jeder Allowlist-Zeile. Die bereits vorhandene AppSettings-Regression prüft weiterhin das Roundtrip der bestehenden UserDefaults-Schlüssel.
- Die gezielten R1-Tests bestanden 4/4. Anschließend bestand die vollständige serielle macOS-Suite mit 226/226 Tests, 0 Fehlern, 0 Skips und 0 Runtime-Warnungen auf macOS 26.7.1.
- Die aufgelösten Release-Buildsettings melden weiterhin `PRODUCT_BUNDLE_IDENTIFIER = de.mcc.FlowDictate`, `PRODUCT_NAME = FlowDictate` und `FULL_PRODUCT_NAME = FlowDictate.app`. Produkt- und App-Ausgabename werden erst in R2/R3 geändert.
- `docs/engineering/REBRANDING_LEGACY_ALLOWLIST.tsv` enthält die zulässigen technischen Legacy-Werte und vollständig historischen Dateien als maschinenlesbare Ausgangsliste. Aktuelle Benutzertexte sind nicht pauschal erlaubt und müssen in R2 beziehungsweise R4 einzeln bereinigt werden.
- R1 enthält keine Kopier-, Verschiebe-, Lösch- oder Schemaoperation für Nutzerdaten. Alle Änderungen betreffen Konstantenauflösung, Testzugriff und Regressionen.

### 7.5 Exit

- [x] Automatisierte Tests schlagen fehl, wenn ein geschützter Legacy-Identifier versehentlich auf `NativeDictate` geändert wird.
- [x] Der neue Anzeigename kann unabhängig von Persistenz- und Bundle-Identität gesetzt werden.
- [x] Keine Nutzerdaten werden kopiert, verschoben oder gelöscht.

## 8. R2 – Sichtbare Produktumbenennung

**Status:** `ERLEDIGT`

### 8.1 Pflichtumfang

- App-, Fenster- und Menütitel,
- Onboarding und Settings,
- Aufnahmeoverlay und History,
- Berechtigungs- und Datenschutztexte,
- sichtbare Fehler-, Diagnose- und Updatehinweise,
- neue Exportdateinamen,
- sichtbare Audio-Geräte- und Capture-Bezeichnungen,
- Copyright-/About-Informationen, soweit vorhanden,
- App-Icon nur dann, wenn es den alten Namen oder alte Initialen enthält.

### 8.2 Interne Namen

Diese Namen dürfen zunächst bestehen bleiben, sofern sie nicht benutzersichtbar sind:

- Swift-Typen wie `FlowDictateApp`, `FlowDictateMenu` und `FlowDictateVersion`,
- Source- und Testordner,
- Xcode-Projekt-, Target- und Scheme-Namen,
- Entitlements- und Info-Plist-Dateinamen,
- Queue-Labels und interne Log-Subsystem-Fallbacks,
- temporäre Kompatibilitätspfade.

Die Umbenennung interner Symbole darf nicht den eigentlichen Produktwechsel blockieren.

### 8.3 Textregeln

- Aktuelle Benutzeroberfläche verwendet nur `NativeDictate`.
- Ein Übergangshinweis darf `NativeDictate, formerly FlowDictate` verwenden.
- `FlowDictate` bleibt in aktuellen Texten nur zulässig, wenn eine alte Installation, ein Legacy-Pfad oder eine historische Version gemeint ist.
- Neue Fehlermeldungen dürfen keine alten Produktnamen enthalten.

### 8.4 Nachweis vom 4. Oktober 2026

- Die sichtbaren Fenster-, Menü-, Onboarding-, Settings-, History-, Berechtigungs-, Datenschutz-, Fehler-, Diagnose- und Update-Texte verwenden `NativeDictate`. Dazu gehören auch die Hinweise für Mikrofon, Bedienungshilfen, Systemaudio, Login Items, Aufnahmeordner und Meeting-Einwilligung.
- `CFBundleDisplayName` ist in der Quell-Info-Plist auf `NativeDictate` gesetzt. Der gebaute Testhost enthält außerdem ausschließlich `NativeDictate` in den drei steuerbaren TCC-Nutzungstexten für Mikrofon, Speech Recognition und Systemaudio. `CFBundleName`, Executable, Xcode-Projekt, Target und Scheme heißen bis R3 beziehungsweise einer optionalen internen Bereinigung weiterhin technisch `FlowDictate`; der Bundle-Identifier bleibt absichtlich `de.mcc.FlowDictate`.
- Neue vorgeschlagene Nutzerexporte heißen `NativeDictate-<ID>.txt`, `NativeDictate-Diagnostics.json`, `NativeDictate-Dictionary.json` und `NativeDictate-Writing-Styles.json`.
- Die im Core-Audio-System sichtbaren Tap- und Aggregate-Device-Namen verwenden `NativeDictate`. Interne Aggregate-UIDs, Queue-Labels, temporäre Uploaddateien und Logger-Fallbacks bleiben als technische Legacy-Namen erhalten.
- Das vorhandene App-Icon zeigt Mikrofon, Wellenform und Aufnahmepunkt ohne alten Namen oder alte Initialen. Es wurde deshalb entsprechend dem Pflichtumfang nicht verändert. Eine eigene About- oder Copyright-Oberfläche existiert im aktuellen Quellstand nicht.
- Der neue Regressionstest `visibleProductBrandingUsesNativeDictate()` scannt die 24 benutzersichtbaren Produktionsquellen, die Quell-Info-Plist, die TCC-Buildsettings und die neuen Exportnamen. Das zu diesem Zeitpunkt noch erlaubte Queue-Label `FlowDictate.SystemAudioCapture` war eng begrenzt ausgenommen; R8.4 hat diese Ausnahme später entfernt. Der korrigierte Test bestand zunächst gezielt 1/1.
- Anschließend bestand die vollständige serielle macOS-Suite auf dem endgültigen R2-Stand mit 227/227 Tests, 0 Fehlern und 0 Skips. Der Lauf schließt alle 226 bestehenden Regressionstests und den neuen Brand-Test ein.
- Der kontrollierte Restscan findet in App-Code, Info-Plist und Xcode-Projekt noch 104 Zeilen beziehungsweise 34 String-Literale mit `FlowDictate`. Sie gehören ausschließlich zu den in R2.2 erlaubten internen Typ-, Datei-, Projekt-, Target- und Produktnamen, den in R1 geschützten Bundle-/Speicher-/Queue-Verträgen, temporären internen Dateinamen, Kommentaren oder der bis R6 absichtlich aktiven alten GitHub-API-Adresse. `REBRANDING_LEGACY_ALLOWLIST.tsv` dokumentiert die zusätzlichen R2-Ausnahmen.
- `plutil -lint` für die Quell-Info-Plist und `git diff --check` sind grün. Die bekannten, bereits in R0/R1 dokumentierten Xcode-27-Compilerwarnungen blieben unverändert.

### 8.5 Exit

- [x] Eine normale App-Nutzung zeigt keinen unbeabsichtigten alten Produktnamen.
- [x] Berechtigungsdialoge und Systemeinstellungen nennen soweit technisch steuerbar NativeDictate.
- [x] Exportierte neue Nutzerdateien verwenden NativeDictate im vorgeschlagenen Dateinamen.
- [x] Alle verbleibenden FlowDictate-Treffer sind klassifiziert und begründet.

## 9. R3 – Packaging und Installationsmigration

**Status:** `ERLEDIGT`

### 9.1 Zielartefakte

- `NativeDictate.app`
- `NativeDictate-4.2.0-Community-macOS.zip`
- `NativeDictate-4.2.0-Community-macOS.zip.sha256`

Das Paket enthält weiterhin Lizenz, Third-Party Notices, Privacy, Changelog sowie deutsche und englische Installationsanleitungen.

### 9.2 Buildanpassungen

- Produkt- beziehungsweise App-Ausgabename auf NativeDictate setzen, ohne den Bundle-Identifier zu ändern.
- Build- und Packaging-Skripte auf neue Artefaktnamen umstellen.
- Temporäre Buildverzeichnisse dürfen später umbenannt werden, müssen aber keine Nutzerdaten migrieren.
- Codesign-, Entitlements-, Universal-Binary- und Sandbox-Verträge unverändert prüfen.
- Releasepaket auf alte unerwünschte App-Bundles und doppelte Anwendungen prüfen.

### 9.3 Upgradevertrag 4.1.0 → 4.2.0

Da `FlowDictate.app` und `NativeDictate.app` unterschiedliche Dateinamen besitzen, ersetzt Finder die alte App nicht automatisch. Die Anleitung muss deshalb verbindlich vorgeben:

1. FlowDictate vollständig beenden.
2. NativeDictate nach `/Applications` kopieren.
3. NativeDictate starten und vorhandene Einstellungen, History, Modell und Aufnahmeordner prüfen.
4. FlowDictate nicht parallel starten.
5. Nach erfolgreicher Prüfung die alte `FlowDictate.app` entfernen.
6. Bedienungshilfen, Mikrofon, Speech Recognition sowie Systemaudio gegebenenfalls erneut freigeben.
7. `Launch at login` bei Bedarf einmal deaktivieren und erneut aktivieren.

Die Migration löscht keine Container oder Application-Support-Verzeichnisse. Ein automatisches Entfernen der alten App ist nicht Bestandteil von 4.2.

### 9.4 Nachweis vom 4. Oktober 2026

- Die App-Konfigurationen `Debug`, `Release` und `DebugTests` erzeugen `NativeDictate.app` mit dem Executable `NativeDictate`, Version `4.2.0` und Build `34`. Das Swift-Modul, Xcode-Projekt, Target und Scheme bleiben intern `FlowDictate`; der produktive Bundle-Identifier bleibt unverändert `de.mcc.FlowDictate`.
- Beide Release-Skripte verwenden standardmäßig NativeDictate-Artefaktnamen. Die bisherigen `FLOWDICTATE_*`-Umgebungsvariablen bleiben als technische Fallbacks kompatibel; neue Aufrufe können die entsprechenden `NATIVEDICTATE_*`-Variablen verwenden.
- Der Community-Paketbau lief vollständig durch und erzeugte `NativeDictate-4.2.0-Community-macOS.zip` samt gleichnamiger `.sha256`-Datei. Der SHA-256 des lokalen R3-Prüfarbeitsstands lautet `af6a72399f6e1c27a406ec115a0c042756e89dd508886b2328da4374a447aaf7`. Dieses strukturelle R3-Artefakt ist kein veröffentlichter Releasekandidat und wird nach R4/R5 erneut gebaut.
- Das unabhängig extrahierte ZIP enthält genau ein App-Bundle, ausschließlich `NativeDictate.app`, sowie Lizenz, Third-Party Notices, FluidAudio-Lizenz, Privacy, Changelog und beide Installationsanleitungen. Ein `FlowDictate.app`-Bundle ist nicht enthalten.
- Die extrahierte App meldet `CFBundleDisplayName`, `CFBundleName` und `CFBundleExecutable` jeweils als `NativeDictate`, `CFBundleShortVersionString = 4.2.0`, `CFBundleVersion = 34` und `CFBundleIdentifier = de.mcc.FlowDictate`. Das Executable enthält `arm64` und `x86_64`; `codesign --verify --deep --strict` ist grün.
- Die ausgelesenen Entitlements entsprechen weiterhin dem Community-Vertrag: App Sandbox, Audioeingang, vom Nutzer gewählte Dateien mit Lese-/Schreibzugriff und ausgehende Netzwerkverbindungen. Die App ist ad hoc signiert und absichtlich nicht notarisiert.
- Die deutsche und englische Installationsanleitung erklären den manuellen Wechsel von `FlowDictate.app` zu `NativeDictate.app`: alte App vollständig beenden, neue App zusätzlich installieren, gemeinsamen Zustand prüfen, beide Bundles niemals parallel starten, Berechtigungen und Launch-at-login bei Bedarf erneuern und die alte App erst nach erfolgreichem Funktionstest entfernen. Es wird weder eine App noch ein Container automatisch gelöscht.
- Der neue Regressionstest `packagingBuildSettingsUseNativeDictateWithoutChangingModuleIdentity()` schützt Produkt-, Executable-, Versions-, Testhost-, Modul-, Scheme- und Community-Paketnamen. Die vollständige serielle macOS-Suite bestand auf dem endgültigen R3-Stand mit 228/228 Tests, 0 Fehlern und 0 Skips. Der rein quelltextlesende Test `productionBuildSettingsKeepLegacyBundleIdentity()` benötigte in diesem Lauf auffällige 5.607 Sekunden; das ist kein bestandener App-Performance-Nachweis und wurde nicht als solcher gewertet.
- `zsh -n` für beide Release-Skripte, die aufgelösten Release-Buildsettings, die ZIP-Prüfsumme und `git diff --check` sind grün. Die bekannten Xcode-27-Compilerwarnungen blieben unverändert.

### 9.5 Exit

- [x] Das Paket enthält exakt eine `NativeDictate.app`.
- [x] Die App meldet Version 4.2.0 und den unveränderten Bundle-Identifier `de.mcc.FlowDictate`.
- [x] ZIP- und Checksum-Dateinamen verwenden NativeDictate.
- [x] Die Upgradeanleitung verhindert ausdrücklich parallelen Betrieb beider App-Bundles.

## 10. R4 – Aktuelle Dokumentation und Historiengrenze

**Status:** `ERLEDIGT`

### 10.1 Zu aktualisieren

- `README.md`
- `docs/README.md`
- `docs/FEATURES.md`
- `docs/MANUAL_VERIFICATION.md`
- `COMMUNITY_INSTALLATION.md`
- `COMMUNITY_INSTALLATION_EN.md`
- `PRIVACY.md`
- `RELEASE.md`
- `CHANGELOG.md` mit neuem 4.2-Eintrag
- neue `docs/releases/RELEASE_NOTES_4.2.0.md`
- `.env.example`, sofern Produktvariablen oder Kommentare betroffen sind
- aktuelle GitHub-, Download- und Release-Links

### 10.2 Historisch zu erhalten

- Release Notes bis 4.1.0,
- abgeschlossene PRDs bis 4.1,
- archivierte technische Spikes,
- alte Paketnamen in historischen Nachweisen,
- Erklärungen des Wechsels von `de.euler.FlowDictate` zu `de.mcc.FlowDictate`.

### 10.3 README-Übergangshinweis

Mindestens für 4.2 enthält das README einen knappen Hinweis:

> NativeDictate was previously released as FlowDictate. The project was renamed to avoid confusion with an unrelated commercial product. Existing release history remains available in this repository.

Der Hinweis behauptet keine Verbindung zum anderen Produkt und verlinkt nicht werbend auf dieses.

### 10.4 Nachweis vom 4. Oktober 2026

- `README.md`, Dokumentations- und Requirements-Index, Feature-Referenz, manuelle Prüfliste, Privacy, Third-Party Notices, Release Guide, Changelog, beide Installationsanleitungen und `.env.example` verwenden für aktuelle Produkt-, Installations- und Artefaktaussagen NativeDictate 4.2.0. Der öffentliche Kurztext und der geforderte sachliche Übergangshinweis stehen am Anfang des README.
- `docs/releases/RELEASE_NOTES_4.2.0.md` beschreibt die Umbenennung ohne neue Produktfunktion, den unveränderten Bundle-/Speichervertrag, den manuellen 4.1-zu-4.2-Wechsel, Datenschutz, nicht notarisierten Community-Build sowie die unverändert offenen Systemaudio- und Verifikationslücken. Der Release-Index verlinkt die neuen Notes und kennzeichnet 4.1.0 als letzte Veröffentlichung unter dem alten Namen.
- Das Changelog enthält einen eigenen 4.2.0-Release-Candidate-Eintrag. Der inzwischen veröffentlichte 4.1.0-Eintrag trägt das reale Veröffentlichungsdatum 30. September 2026; sein Inhalt und die historischen Release Notes wurden nicht umgeschrieben.
- Der aktuelle Release Guide erzeugt und prüft ausschließlich `NativeDictate-4.2.0-Community-macOS.zip` samt `.sha256`, verwendet Tag `v4.2.0`, installiert `NativeDictate.app` und dokumentiert ein separates 4.2-Rebranding-Gate. Frühere Phase-3.4-, 4.0- und 4.1-Gates stehen unverändert unter der ausdrücklichen Überschrift „Historical release gates and 4.1 evidence“.
- Alle aktuellen GitHub-Dokumentationslinks sind auf `Hank1210/NativeDictate` vorbereitet. Die im App-Code bis R6 absichtlich aktive alte Release-API wurde in R4 nicht vorzeitig geändert. Aktuelle Dokumente enthalten keine alte `Hank1210/FlowDictate`-URL und keine Anweisung zum Erzeugen oder Installieren eines neuen FlowDictate-4.2-Artefakts.
- Ein kontrollierter Restscan der aktuellen Dokumentationsdateien findet 70 Fundzeilen in 12 Dateien. Sie benennen ausschließlich den 4.1-Upgradeausgangspunkt, `FlowDictate.app`, geschützte Bundle-/Application-Support-Werte, interne Xcode-/Test-/Umgebungsnamen oder klar abgegrenzte Versionshistorie. Die präzisierte `REBRANDING_LEGACY_ALLOWLIST.tsv` erfasst diese Gruppen; jede Allowlist-Zeile wurde gegen die aktuelle Quelldatei geprüft.
- Alle lokalen Markdown-Ziele der bearbeiteten Dokumente existieren. `git diff --check`, TSV-Spaltenprüfung, Allowlist-Auflösungsprüfung und Scans auf alte Repository-URLs beziehungsweise falsche 4.2-Artefaktnamen sind grün. Es wurden keine App-Quellen oder Buildsettings nach der grünen R3-Suite verändert; die nächste vollständige Paket- und Testwiederholung gehört zum R5-Gate.

### 10.5 Exit

- [x] Neue Nutzer finden ausschließlich NativeDictate-Installations- und Buildbefehle; notwendige interne Xcode-Namen sind unmittelbar als technische Identifikatoren erklärt.
- [x] Bestehende Nutzer finden einen eindeutigen 4.1-→4.2-Upgradepfad.
- [x] Historische Dokumente bleiben als historische Dokumente erkennbar und wahrheitsgemäß.
- [x] Keine aktuelle Downloadanweisung verweist auf ein neues FlowDictate-Artefakt.

## 11. R5 – Automatisierte und manuelle Migrationstests

**Status:** `ERLEDIGT`

### 11.1 Automatisierte Gates

- vollständige Unit- und UI-Testtargets kompilieren,
- komplette bestehende Testsuite ausführen,
- neue Identitäts- und Persistenztests aus R1 ausführen,
- `git diff --check`,
- kontrollierter Brand-Scan mit Legacy-/Historien-Allowlist,
- Paketinhalt und Checksummen prüfen,
- `plutil`-Prüfung der gebauten `Info.plist`,
- `codesign --verify --deep --strict`,
- Entitlements prüfen,
- Architekturen `arm64` und `x86_64` prüfen,
- sicherstellen, dass keine Zugangsdaten, Aufnahmen, Transkripte oder lokalen Modelle im Paket liegen.

### 11.2 Manueller Upgrade-Test

Ausgangslage ist die akzeptierte FlowDictate-4.1.0-Community-App mit repräsentativem, nicht sensiblem Testzustand:

- abgeschlossene History-Einträge,
- persönliches Wörterbuch und Writing Style,
- App-Profil,
- ausgewählter Aufnahmeordner,
- heruntergeladenes lokales Modell,
- optionaler Test-API-Key,
- konfigurierte Hotkeys,
- aktiviertes oder deaktiviertes Launch-at-login.

Zu prüfen:

- NativeDictate sieht dieselben Einstellungen und Daten,
- vorhandene History lässt sich öffnen, abspielen, kopieren und exportieren,
- lokales Modell wird nicht erneut heruntergeladen,
- Recording-Folder-Bookmark funktioniert oder fordert kontrolliert zur Neuauswahl auf,
- Keychain-Zugriff funktioniert oder zeigt einen klaren, einmaligen Wiederherstellungspfad,
- Mikrofon-, Systemaudio- und Mixed-Aufnahme funktionieren,
- Accessibility-Insertion funktioniert,
- Updateprüfung zeigt keine falsche alte Produktmeldung,
- nur eine Instanz beziehungsweise ein Produktbundle läuft,
- Entfernung der alten App löscht keine Nutzerdaten.

### 11.3 Manueller Clean-Install-Test

- NativeDictate ohne vorhandenen FlowDictate-Container installieren,
- vollständiges Onboarding durchlaufen,
- lokale und optionale BYOK-Transkription prüfen,
- alle drei Aufnahmequellen prüfen,
- History, Export, Recovery und Neustart prüfen,
- Installationsanleitung gegen den tatsächlichen Gatekeeper- und TCC-Ablauf lesen.

### 11.4 Automatisierter Zwischenstand vom 4. Oktober 2026

- Die vollständige serielle macOS-Suite bestand auf dem R4-Stand mit 228/228 Tests, 0 Fehlern, 0 Skips, 0 erwarteten Fehlern und 0 Runtime-Warnungen auf macOS 26.7.1. App, Unit-Test- und UI-Testtarget wurden dabei gebaut; die optionalen UI-Tests bleiben entsprechend dem Scheme-Vertrag nicht Teil des automatischen Laufs.
- Der kontrollierte Scan aller von Git versionierten UTF-8-Dateien prüfte jede Fundzeile für `FlowDictate`, `flowdictate`, `de.mcc.FlowDictate` und `de.euler.FlowDictate` gegen die pfadbezogene Legacy-/Historien-Allowlist. Ergebnis: `unclassified=0`. Die für diesen vollständigen Scan präzisierte Allowlist löst weiterhin jede Zeile gegen eine vorhandene Quelldatei auf.
- Der nach R4 neu gebaute Community-Arbeitsstand `NativeDictate-4.2.0-Community-macOS.zip` besteht seine `.sha256`-Prüfung. SHA-256: `0d8e603341fab35c446037b14339799030626fffbb872f1367f1127a03f21b92`. Dieses R5-Artefakt ist wegen der noch folgenden R6-Änderungen kein finales Veröffentlichungsartefakt.
- Das unabhängig extrahierte Archiv enthält genau eine `NativeDictate.app` und kein `FlowDictate.app`. Die App meldet `NativeDictate` als Display-, Bundle- und Executable-Namen, Version `4.2.0`, Build `34` und Bundle-ID `de.mcc.FlowDictate`; das Executable enthält `arm64` und `x86_64`.
- `plutil -lint`, `codesign --verify --deep --strict` und die Entitlements-Prüfung sind grün. Die Sandbox-, Audioeingabe-, nutzergewählte Lese-/Schreibzugriffs- und Netzwerk-Entitlements entsprechen dem dokumentierten Community-Vertrag. Der Build ist ad hoc signiert und absichtlich nicht notarisiert.
- Changelog, Privacy, Third-Party Notices, beide Installationsanleitungen, MIT-Lizenz und FluidAudio-Lizenz im ZIP sind byteidentisch mit den geprüften Repository-Dateien. Der Inhalts- und Namensscan fand keine private Testdatei, `.env`, Zugangsdaten, Aufnahme, Transkript oder Modelldatei im Paket.
- Für den realen Upgrade-Test war `/Applications/FlowDictate.app` vorhanden und `/Applications/NativeDictate.app` noch nicht vorhanden. Eine erste UI-Inventur meldete FlowDictate irrtümlich als nicht aktiv; die spätere Prozessprüfung zeigte jedoch, dass `/Applications/FlowDictate.app` bereits seit dem 3. Oktober 2026 lief. Das exakt geprüfte NativeDictate-Bundle wurde ohne Überschreiben zusätzlich installiert. Verzeichnisvergleich und Executable-SHA-256 `c1a757528e1430e27b1510b55e44e84946c8cd282768b72d073809a1ccd2509c` bestätigen die Identität mit der aus dem R5-ZIP extrahierten App; die alte App und Nutzerdaten wurden nicht gelöscht oder verschoben.
- Der installierte neue Build wurde anschließend gestartet. Der Start blieb in der UI-Automation zunächst unsichtbar, die Prozessprüfung belegte jedoch eine laufende NativeDictate-Instanz. Wegen der erst später erkannten bereits laufenden FlowDictate-Instanz entstand damit entgegen der Anleitung vorübergehend Parallelbetrieb. NativeDictate war bei der Sicherheitsprüfung idle und hielt keine Aufnahme- oder Transkriptionsdatei offen; die Testinstanz wurde beendet. Danach lief wieder ausschließlich die zuvor vorhandene FlowDictate-Instanz.

### 11.5 Manueller Upgrade-Zwischenstand vom 4. bis 6. Oktober 2026

- NativeDictate verwendet aufgrund des unveränderten Bundle-Identifiers denselben Sandbox-Container und dieselben Legacy-Pfade wie die vorhandene 4.1-Installation. Die JSON-Dateien blieben valide; History, persönliches Wörterbuch, UserDefaults, Aufnahmeordner-Bookmark und das vorhandene lokale Modell wurden ohne Migration sichtbar. Der geheime Wert des vorhandenen API-Key-Eintrags im unveränderten Keychain-Service `de.mcc.FlowDictate` wurde weder gelesen noch ausgegeben.
- Nach dem manuellen Beenden von FlowDictate lief ausschließlich das exakt geprüfte NativeDictate-Bundle. Das History-Fenster zeigte 100 Einträge; Wiedergabe einer vorhandenen Aufnahme, `Copy Original`, `Copy Final`, UTF-8-Textexport und das Öffnen des gespeicherten Aufnahmeordners funktionierten. Die temporäre Exportdatei wurde nach der Prüfung gelöscht. Smart Dictation zeigte den vorhandenen Wörterbucheintrag und den Stil `Original`; App-Profile waren in diesem Konto nicht vorhanden.
- Transcription zeigte den geerbten lokalen Parakeet-Anbieter samt installiertem Modell ohne erneuten Download. Die geerbten Standard-Hotkeys waren sichtbar; Launch at Login blieb aktiv. Die Update-Oberfläche meldete `NativeDictate 4.2.0 (34) Community`. Das UI zeigte Mikrofon, Bedienungshilfen und Speech Recognition als erlaubt.
- Eine reale Mikrofonaufnahme per Halten von `Option+Leertaste` wurde lokal mit Parakeet transkribiert und per Accessibility erfolgreich in TextEdit eingefügt. Der gemeinsame Verlauf enthielt danach 111 Einträge: den erfolgreichen 4,469-Sekunden-Test sowie einen vorausgegangenen, 0,096 Sekunden kurzen Fehlversuch; beide WAV-Dateien existieren mit den zur Metadatei passenden Größen. Testeinträge und das möglicherweise automatisch in iCloud gesicherte TextEdit-Dokument bleiben bis zu einer ausdrücklichen Löschfreigabe erhalten.
- Die neue ScreenCaptureKit-Anfrage legte NativeDictate nach dem gezielten `tccutil reset ScreenCapture de.mcc.FlowDictate` wieder als zunächst deaktivierten Eintrag unter `Aufnahme von Bildschirm & Systemaudio` an. Nach dem ausdrücklich bestätigten Aktivieren und dem von macOS verlangten App-Neustart meldete die UI `Allowed`. Eine Fünf-Sekunden-Probe lieferte 5,1 Sekunden Audio, 255 Callbacks, monotone Zeitstempel, 0 Lücken und 0 Sample-Rate-Wechsel. Die separate Freigabe `Nur Aufnahme von Systemaudio` blieb aktiv.
- Zwei erste reale Systemaudio-Aufnahmen enthielten absichtlich beziehungsweise testbedingt nur Stille, weil die Wiedergabe aus dem NativeDictate-History-Fenster erfolgte und `excludesCurrentProcessAudio` den eigenen App-Ton vertragsgemäß ausschließt. Die Dateien waren technisch valide, aber mit konstant −91 dB still; die daraus folgenden `Transcription failed`-Einträge sind keine Capture-Regression und wurden nicht gelöscht. Der Wiederholungstest mit Sprache aus Google Chrome bestand: 11,805 Sekunden, 97.691 Byte, −29,5 dB Mittel, −8,8 dB Spitze, lokale Parakeet-Transkription und History-Status `completed`.
- Der reale Mixed-Test bestand mit getrennten Originalspuren und gelabeltem Transkript. Mikrofon und Systemaudio wurden als 48-kHz-Mono-CAF mit 1.099.776 beziehungsweise 1.112.064 Byte gespeichert; beide Spuren enthielten echten Pegel, wurden transkribiert und auf einer 29 Einträge umfassenden Timeline zusammengeführt. Der Session-Status ist `completed`, Synchronisationsqualität `good`, mit 0 Lücken, 0 verworfenen Puffern und 0 Clipping-Frames.
- NativeDictate erkannte den geerbten Keychain-Eintrag als `API key — Configured`. Nach ausdrücklicher Freigabe wurde eine 5,643 Sekunden lange, nicht sensible Mikrofon-Testphrase mit `gpt-4o-mini-transcribe` an OpenAI übertragen, im ersten Versuch korrekt transkribiert, als `completed` archiviert und per Accessibility in TextEdit eingefügt. Der geheime API-Key-Wert wurde dabei weder gelesen noch ausgegeben. Danach wurden `Fully offline`, der lokale Anbieter und die Mikrofonquelle wiederhergestellt; ein kontrollierter Neustart aktivierte diese Werte. Es lief anschließend genau eine NativeDictate-Instanz, der gemeinsame Verlauf enthielt 125 valide Einträge.
- Nach ausdrücklicher Bestätigung wurde die nicht laufende `/Applications/FlowDictate.app` als `FlowDictate 4.1.0 Build 33.app` wiederherstellbar in den Papierkorb verschoben; eine dort bereits vorhandene 3.3.0-App blieb unangetastet. Danach fehlte nur das alte Bundle unter `/Applications`, während genau eine NativeDictate-Instanz weiterlief. Der gemeinsame Container enthielt unverändert 125 valide History-Einträge, `Fully offline`, den lokalen Anbieter, die Mikrofonquelle sowie 23 nicht leere Modelldateien mit insgesamt 483.257.242 Byte. Die Bundle-Entfernung löschte damit keine Nutzerdaten.
- Ein Writing Style und App-Profil waren im vorgefundenen Ausgangskonto nicht vorhanden und konnten deshalb nicht als Bestandsmigration geprüft werden; diese Abweichung ist ausdrücklich dokumentiert und gefährdet keine vorhandenen Nutzerdaten. Der Upgrade-Test ist für den tatsächlich vorgefundenen Zustand abgeschlossen.

### 11.6 Manueller Clean-Install-Nachweis vom 6. Oktober 2026

- Der Nutzer legte ein neues macOS-Testkonto ohne vorhandenen FlowDictate-Container an und installierte NativeDictate dort neu. Installation und Ersteinrichtung funktionierten.
- Die sechs realen Aufnahmevarianten bestanden: Mikrofon, Systemaudio und Mikrofon plus Systemaudio jeweils mit vollständig lokaler Transkription sowie mit OpenAI.
- History, Wiedergabe, Export und Wiederherstellung nach einem Neustart funktionierten im frischen Konto ebenfalls. Der Nutzer gab den Clean-Install-Test daraufhin ausdrücklich als abgeschlossen frei.

### 11.7 Exit

- [x] Upgrade-Test bewahrt den dokumentierten Zustand oder jede notwendige Neufreigabe ist ausdrücklich dokumentiert.
- [x] Clean Install besteht den Kernablauf.
- [x] Keine zweite vollständige Neueinrichtung wird durch eine versehentliche Bundle-ID-Änderung ausgelöst.
- [x] Keine offene Abweichung gefährdet Nutzerdaten oder parallelen App-Betrieb.

## 12. R6 – GitHub-Umschaltung

**Status:** `ERLEDIGT`

### 12.1 Voraussetzungen

- R5 ist vollständig bestanden.
- Der Releasekandidat ist lokal reproduzierbar.
- Alle vorgesehenen Repository-URLs sind auf `Hank1210/NativeDictate` vorbereitet.
- Es existiert kein separates Ziel-Repository, das die Umbenennung blockiert.

### 12.2 Umschaltreihenfolge

1. Rebranding-Branch final reviewen und in `main` integrieren.
2. Bestehendes GitHub-Repository in den Settings von `FlowDictate` zu `NativeDictate` umbenennen.
3. Lokalen Remote aktualisieren:

   ```bash
   git remote set-url origin https://github.com/Hank1210/NativeDictate.git
   git remote -v
   ```

4. Push, Fetch und Webzugriff über die neue Adresse prüfen.
5. Weiterleitung von `https://github.com/Hank1210/FlowDictate` auf das neue Repository prüfen.
6. Hart codierte Release-API und aktuelle Links gegen das neue Repository testen.
7. Repository-Beschreibung und Topics auf NativeDictate aktualisieren.
8. Altes Repository nicht neu anlegen.

### 12.3 Besonders zu prüfen

- `NativeDictate/Productivity/ProductivityServices.swift` enthielt bis zur Umschaltung absichtlich die alte GitHub-Release-API.
- README, Release Guide und Installationsdokumente enthalten alte Repository-Links nur noch mit ausdrücklicher historischer oder Migrationsbedeutung.
- Externe Klone funktionieren zunächst über GitHubs Redirect, sollen aber die neue Remote-URL dokumentiert bekommen.
- GitHub Pages und ein veröffentlichtes GitHub-Marketplace-Action-Repository sind nicht im Scope. Falls sie wider Erwarten existieren, muss R6 vor der Umschaltung neu bewertet werden.

### 12.4 Nachweis vom 8. Oktober 2026

- Der vollständig geprüfte Rebranding-Branch wurde per Fast-forward in den lokalen `main` integriert. Vor der GitHub-Änderung war `Hank1210/FlowDictate` weiterhin das öffentliche Admin-Repository; ein kollidierendes `Hank1210/NativeDictate` existierte nicht.
- Das bestehende Repository wurde zu `Hank1210/NativeDictate` umbenannt. `origin` verwendet für Fetch und Push `https://github.com/Hank1210/NativeDictate.git`; der alte Webpfad antwortet mit HTTP 301 auf die neue Adresse. Beschreibung und Topics waren bereits markenneutral beziehungsweise NativeDictate-gerecht und benötigten keine weitere Änderung.
- `main` wurde erfolgreich an die neue Adresse gepusht und anschließend gefetcht. Nach dem URL-Umschaltcommit `0b21534` stimmten lokaler `HEAD`, `origin/main` und Remote-HEAD überein; der historische Tag `v4.1.0` sowie acht vorhandene Releases blieben erreichbar. Der vorliegende R6-Abschlussnachweis folgt als eigener Dokumentationscommit.
- Die produktive Releaseprüfung verwendet jetzt `https://api.github.com/repos/Hank1210/NativeDictate/releases/latest`. Der Live-Endpunkt antwortete mit HTTP 200 und lieferte den weiterhin stabilen Release `v4.1.0` unter der neuen Repository-Adresse. Die zeitlich begrenzte alte URL wurde aus der Legacy-Allowlist entfernt; der einzige verbleibende ungefilterte alte Repository-Verweis außerhalb der Rebranding-Dateien liegt in einem historischen Phase-3-PRD.
- Nach der URL-Änderung bestand die vollständige serielle macOS-Suite mit 228/228 Tests und `TEST SUCCEEDED`. Xcode meldete dabei die bereits im Testhelfer liegende Actor-Isolation-Warnung für den Standardwert `MockCredentialStore()`; dieser Lauf wird deshalb nicht als warnungsfrei bezeichnet.

### 12.5 Exit

- [x] Neue und alte Repository-URL führen erwartungsgemäß zum selben Projekt.
- [x] Lokale Fetch-/Push-Operationen verwenden die neue Remote-URL.
- [x] Releaseprüfung ruft das neue Repository auf.
- [x] Issues, Tags und bisherige Releases sind weiterhin vorhanden.

## 13. R7 – Release-Gate NativeDictate 4.2.0

**Status:** `ERLEDIGT`

### 13.1 Releaseinhalt

- NativeDictate 4.2.0 Community,
- Rebranding ohne absichtliche neue Produktfunktion,
- unveränderte technische App-Identität `de.mcc.FlowDictate`,
- dokumentierter manueller Wechsel von `FlowDictate.app` zu `NativeDictate.app`,
- vollständige deutsche und englische Installationsanleitung,
- Release Notes mit Begründung und Kompatibilitätsinformationen.

### 13.2 Freigabegates

- [x] alle R5-Tests und manuellen Matrizen bestanden,
- [x] Repository-Umschaltung R6 bestanden,
- [x] exakter Release-Commit dokumentiert,
- [x] exakte SHA-256 dokumentiert,
- [x] extrahiertes ZIP erneut unabhängig geprüft,
- [x] Appname, Version, Build und Bundle-ID stimmen,
- [x] keine private Datei oder Zugangsinformation enthalten,
- [x] Upgradehinweis ist im GitHub Release sichtbar,
- [x] Rollback auf 4.1.0 wurde hinsichtlich Datenformaten bewertet,
- [x] Veröffentlichung ausdrücklich autorisiert.

### 13.3 Statischer Kandidatennachweis vom 8. Oktober 2026

- Der exakte Artefakt-Quellstand ist `59032a1c33ed2a8d95d26a9af0f8d977bc266eb1` auf `main`. Seit dem vollständig real getesteten R5-Kandidaten `7795e0f` änderte sich im App-Code ausschließlich der Release-API-Endpunkt von der alten, weitergeleiteten Repository-Adresse auf `https://api.github.com/repos/Hank1210/NativeDictate/releases/latest`; die übrigen Änderungen dokumentieren R6 und bereinigen die zugehörige Allowlist.
- Aus diesem Stand wurde `dist/NativeDictate-4.2.0-Community-macOS.zip` neu erzeugt. Seine SHA-256 lautet `58fe298a41f9fd24c31d38f185bc8679a967f354e047c37ef0473f8a218666e2`; die daneben erzeugte Prüfsummendatei besteht `shasum -a 256 -c`.
- Der frühere R5-Kandidat bleibt lokal unter `dist/previous-candidates/r5-pre-github/` mit SHA-256 `0d8e603341fab35c446037b14339799030626fffbb872f1367f1127a03f21b92` erhalten und ist ausdrücklich nicht der R7-Veröffentlichungskandidat.
- Das R7-ZIP wurde in ein neues temporäres Verzeichnis extrahiert. Es enthält genau eine `NativeDictate.app`; deren Info.plist meldet Anzeigename, Bundle-Name und Executable `NativeDictate`, Version 4.2.0, Build 34 und die unveränderte Bundle-ID `de.mcc.FlowDictate`. Das Mach-O enthält `arm64` und `x86_64`; `codesign --verify --deep --strict` besteht. Die ausgelesenen Sandbox-, Audioeingabe-, benutzerausgewählten Datei- und Netzwerk-Entitlements entsprechen der inzwischen in R8.5 zu `config/NativeDictateCommunity.entitlements` umbenannten Quelldatei.
- Deutsche und englische Installationsanleitung, Changelog, Privacy-Hinweis, MIT-Lizenz, Third-Party Notices und FluidAudio-Lizenz sind byteidentisch mit den geprüften Repository-Dateien. Archivpfade und Dokumentinhalte enthalten keine private `TESTING_4_1.md`, `.env`, Zugangsdaten, Aufnahmen, Transkripte oder Modelldateien. `git diff --check` ist leer; der Arbeitsbaum war beim Build sauber.
- Der Build endete mit `BUILD SUCCEEDED`. Xcode meldete dabei die bereits bekannte Swift-Capture-Warnung in `DictationCoordinator.swift`; der Kandidat wird daher nicht als warnungsfrei bezeichnet. Die vollständige serielle Suite auf demselben Quellstand hatte unmittelbar vor dem Kandidatenbau 228/228 Tests und `TEST SUCCEEDED` erreicht; die bekannte Actor-Isolation-Warnung im Testhelfer bleibt ebenfalls dokumentiert.
- Die Datenformatprüfung gegen `v4.1.0` zeigt keine Änderung der History-, Record-, Job-, Profil-, Smart-Dictation-, Long-Form- oder Meeting-Schemaversionen. Änderungen an den Stores zentralisieren lediglich dieselben `Application Support/FlowDictate`-Pfade; 4.2 schreibt kein neues Format, das 4.1 grundsätzlich nicht lesen kann. Ein Rollback muss NativeDictate vollständig beenden, darf niemals beide Bundles parallel starten und kann anschließend FlowDictate 4.1.0 gegen den unveränderten gemeinsamen Datenbestand verwenden. Vor einem Rollback bleibt eine Sicherung der gemeinsamen Nutzerdaten sinnvoll; eine automatische Datenrückmigration oder Löschung ist weder nötig noch vorgesehen.
- Der zuvor installierte R5-Build wurde nach vollständigem Beenden wiederherstellbar in den Papierkorb verschoben. Die nach `/Applications` kopierte App war bei `diff -rq` bytegleich mit der aus dem R7-ZIP extrahierten App; ihre strikte Signatur und der Executable-Hash wurden nach der Installation erneut geprüft. Beim ersten Start blieben Einstellungen, History, lokales Modell, OpenAI-Key-Status und Aufnahmeordner vorhanden. Die macOS-Berechtigungen mussten für die neue Ad-hoc-Signatur erwartungsgemäß erneuert werden.
- Mit genau dieser installierten R7-App bestätigte der Nutzer sechs erfolgreiche Realtests: Mikrofon, Systemaudio und Mikrofon plus Systemaudio, jeweils mit lokalem Modell und OpenAI. Transkription und vorgesehenes Einfügen funktionierten in allen sechs Fällen. History, Wiedergabe, Export und Neustartwiederherstellung wurden anschließend ebenfalls erfolgreich geprüft.
- Für die separate Neuinstallation wurde dasselbe ZIP samt Prüfsummendatei nach `/Users/Shared/NativeDictate-R7-Test/` kopiert und dort erneut mit derselben SHA-256 geprüft. Der Nutzer installierte daraus `NativeDictate.app` in einem frischen macOS-Testkonto. Installation und Start waren erfolgreich; Onboarding, Aufnahmeordner, Berechtigungen, lokales Modell, OpenAI-Einrichtung, Mikrofon, Systemaudio, gemischte Aufnahme, Transkription, vorgesehenes Einfügen, History, Wiedergabe, Export und Neustartwiederherstellung wurden als positiv bestätigt. Damit bestehen Upgrade- und Clean-Install-Nachweis nun mit exakt demselben R7-Checksum.
- Die Veröffentlichung wurde am 8. Oktober 2026 ausdrücklich autorisiert. Tag, GitHub Release, Asset-Upload, Sichtprüfung des veröffentlichten Upgradehinweises und die abschließende Downloadprüfung sind im folgenden Abschnitt dokumentiert.

### 13.4 Veröffentlichung vom 8. Oktober 2026

- Der annotierte Tag `v4.2.0` wurde exakt auf dem Artefakt-Quellcommit `59032a1c33ed2a8d95d26a9af0f8d977bc266eb1` erstellt und zu `Hank1210/NativeDictate` gepusht. Die serverseitige Auflösung von `refs/tags/v4.2.0^{}` bestätigt denselben Commit.
- Der GitHub Release [NativeDictate 4.2.0 Community](https://github.com/Hank1210/NativeDictate/releases/tag/v4.2.0) wurde zunächst als Vorabversion erzeugt. Er enthält ausschließlich `NativeDictate-4.2.0-Community-macOS.zip` und die zugehörige `.sha256`-Datei; GitHubs zusätzliche Quellarchive werden automatisch bereitgestellt.
- Beide hochgeladenen Assets wurden aus dem Vorab-Release in ein neues temporäres Verzeichnis heruntergeladen und mit den lokal getesteten Dateien verglichen. ZIP und Prüfsummendatei waren byteidentisch; die heruntergeladene Prüfsummendatei bestand erneut, und GitHub meldet für das ZIP den Digest `sha256:58fe298a41f9fd24c31d38f185bc8679a967f354e047c37ef0473f8a218666e2`.
- Erst nach diesem Vergleich wurde die Vorab-Markierung entfernt und der Release ausdrücklich als `Latest` gesetzt. GitHubs `releases/latest`-Endpunkt liefert `v4.2.0` mit `draft: false` und `prerelease: false`.
- Der sichtbare Release-Text enthält den vollständigen Wechselpfad von `FlowDictate.app` zu `NativeDictate.app`, die unveränderte technische Identität, erneuerbare macOS-Berechtigungen, den Ad-hoc-/Nicht-notarisiert-Hinweis und die ausdrücklich fortbestehende 4.1-System-Audio-Abweichung.

### 13.5 Exit

NativeDictate 4.2.0 ist erst veröffentlichungsbereit, wenn sowohl eine Neuinstallation als auch der reale Wechsel von FlowDictate 4.1.0 ohne Verlust des dokumentierten Nutzerzustands nachgewiesen sind.

## 14. R8 – Optionale interne Namensbereinigung

**Status:** `IN ARBEIT`

Dieser Schritt ist kein Gate für 4.2. Er darf erst beginnen, nachdem NativeDictate 4.2 stabil ist.

Mögliche spätere Arbeiten:

- Swift-Typen und Quelldateien umbenennen,
- Source- und Testordner umbenennen,
- Xcode-Projekt, Targets und Schemes umbenennen,
- Entitlements- und Plist-Dateinamen bereinigen,
- interne Logger- und Queue-Namen aktualisieren,
- Build-Umgebungsvariablen wie `FLOWDICTATE_VERSION` durch neue Namen ersetzen und mit einer begrenzten Kompatibilitätsphase versehen.

Nicht Bestandteil dieser Bereinigung:

- Bundle-Identifier ändern,
- Legacy-Speicherpfade verschieben,
- alte Keychain-Einträge löschen,
- historische Dokumente umschreiben.

Jede interne Bereinigung wird mechanisch getrennt, mit kleinen Commits und vollständiger Testsuite durchgeführt.

### 14.1 Interner Versions-Typ

- Der rein interne Typ `FlowDictateVersion` und seine Quelldatei wurden zu `NativeDictateVersion` beziehungsweise `NativeDictateVersion.swift` umbenannt. Alle Verwendungen in App, History, Productivity-Ansicht und Tests wurden mechanisch angepasst.
- Die Schemawerte bleiben unverändert: Onboarding 2, History 7 und Dictation Record 7. Bundle-Identifier, Keychain-Service, Application-Support-Wurzel und sämtliche anderen Persistenzverträge wurden nicht geändert.
- Die fünf dadurch überflüssigen Ausnahmen wurden aus `REBRANDING_LEGACY_ALLOWLIST.tsv` entfernt; der kontrollierte Restscan findet im aktiven Code keinen Verweis auf `FlowDictateVersion` mehr. `git diff --check` ist leer.
- Zwei erste Teststarts im projektlokalen DerivedData-Verzeichnis erreichten wegen automatisch gesetzter Finder-/File-Provider-Attribute am generierten XCTest-Bundle nicht die Testausführung; Codesign lehnte diese Build-Metadaten ab. Mit unverändertem Quellstand und DerivedData unter `/private/tmp` bestand die vollständige serielle macOS-Suite anschließend mit 228/228 Tests und `TEST SUCCEEDED`.
- Der erfolgreiche Lauf meldete weiterhin die bekannte Actor-Isolation-Compilerwarnung am Defaultwert `MockCredentialStore()` des Testhelfers. Der Schritt wird deshalb nicht als warnungsfrei bezeichnet.

### 14.2 SwiftUI-Einstiegstypen

- Die internen Typen `FlowDictateApp`, `FlowDictateMenu` und `FlowDictateSettingsView` wurden mechanisch zu `NativeDictateApp`, `NativeDictateMenu` und `NativeDictateSettingsView` umbenannt. Die zugehörigen Swift-Dateinamen bleiben zunächst unverändert und werden nicht mit diesem Typ-Commit vermischt.
- Die beiden dadurch überflüssigen Typ-Ausnahmen wurden aus `REBRANDING_LEGACY_ALLOWLIST.tsv` entfernt. Verbleibende Treffer für `FlowDictateApp.swift` und `FlowDictateMenu.swift` sind ausschließlich die noch bestehenden Dateipfade, Dateiköpfe und die Pfadliste des Branding-Regressionstests.
- Die vollständige serielle macOS-Suite bestand erneut mit 228/228 Tests und `TEST SUCCEEDED`. Der Lauf verwendete dasselbe DerivedData-Verzeichnis unter `/private/tmp` und meldete weiterhin nur die bekannte Actor-Isolation-Compilerwarnung im Testhelfer.
- Bundle-Identifier, Persistenzpfade, Keychain-Service, Schemata und sichtbares App-Verhalten wurden nicht geändert.

### 14.3 SwiftUI-Einstiegsdateien

- `FlowDictateApp.swift` und `FlowDictateMenu.swift` wurden getrennt vom Typ-Commit zu `NativeDictateApp.swift` und `NativeDictateMenu.swift` umbenannt. Der Dateikopf der App-Einstiegsdatei verwendet nun ebenfalls NativeDictate.
- Der Branding-Regressionstest prüft die neuen Pfade; die letzte nur für den alten App-Dateikopf benötigte Allowlist-Ausnahme wurde entfernt. Xcodes dateisystemsynchronisierte Gruppen nahmen die neuen Pfade ohne Änderung an `project.pbxproj` auf.
- Der kontrollierte Restscan findet die beiden alten Dateinamen weder in aktivem Code noch in Tests, Allowlist oder Xcode-Projekt. `git diff --check` ist leer.
- Die vollständige serielle macOS-Suite bestand erneut mit 228/228 Tests und `TEST SUCCEEDED`; die bekannte Actor-Isolation-Compilerwarnung im Testhelfer bleibt bestehen.
- Xcode-Projekt, Scheme, Targets, Swift-Modul und Quellwurzel behalten in diesem Schritt ausdrücklich ihre bestehenden internen FlowDictate-Namen. Technische Identitäten und persistente Daten wurden nicht verändert.

### 14.4 Logger-, Queue- und temporäre Audio-Identifier

- Der interne Typ `FlowLogger` und seine Quelldatei wurden zu `NativeDictateLogger` beziehungsweise `NativeDictateLogger.swift` umbenannt. Der Fallback für Prozesse ohne Bundle-Identifier lautet nun ebenfalls `NativeDictate`; im normalen App-Prozess bleibt das Logger-Subsystem weiterhin die tatsächliche, absichtlich unveränderte Bundle-ID.
- Nicht persistierte Dispatch-Queue-, Timer- und serielle Datei-I/O-Labels verwenden nun `NativeDictate`. Dasselbe gilt für die nur während einer Aufnahme beziehungsweise Diagnose erzeugten temporären Core-Audio-Aggregate-UIDs. Bundle-Identifier, Keychain-Service, Application-Support-Wurzel, UserDefaults-Schlüssel und gespeicherte Daten wurden nicht geändert.
- Die zehn dadurch überflüssigen Ausnahmen wurden aus `REBRANDING_LEGACY_ALLOWLIST.tsv` entfernt. Der Branding-Regressionstest benötigt keine Sonderbehandlung für `FlowDictate.SystemAudioCapture` mehr; der kontrollierte Restscan findet die bereinigten alten Identifier nur noch im historischen R0-Inventar und in der dokumentierten früheren R2-Ausnahme.
- Die vollständige serielle macOS-Suite bestand mit 228/228 Tests und `TEST SUCCEEDED`. Der erfolgreiche Lauf verwendete den vorhandenen SwiftPM-Cache und DerivedData unter `/private/tmp`; die bekannte Actor-Isolation-Compilerwarnung im Testhelfer bleibt bestehen.
- Xcode-Projekt, Scheme, Targets, Swift-Modul, Quell- und Testwurzel sowie persistente Legacy-Verträge behalten in diesem Schritt ausdrücklich ihre bestehenden Namen.

### 14.5 Konfigurationsdateien

- `config/FlowDictateInfo.plist` und `config/FlowDictateCommunity.entitlements` wurden ohne Inhaltsänderung zu `config/NativeDictateInfo.plist` beziehungsweise `config/NativeDictateCommunity.entitlements` umbenannt.
- Alle drei App-Buildkonfigurationen im Xcode-Projekt, der Branding-Regressionstest und das Community-Release-Skript referenzieren die neuen Pfade. Die nicht mehr benötigte Entitlements-Dateinamen-Ausnahme wurde aus `REBRANDING_LEGACY_ALLOWLIST.tsv` entfernt.
- `plutil -lint` besteht für beide Dateien, `bash -n` besteht für das angepasste Community-Release-Skript, und der kontrollierte Restscan findet die alten Dateinamen außerhalb dieses R8-Nachweises nur noch im historischen R0-Inventar.
- Die vollständige serielle macOS-Suite bestand mit 228/228 Tests und `TEST SUCCEEDED`; der Build verarbeitete dabei nachweislich `config/NativeDictateInfo.plist`. Die bekannte Actor-Isolation-Compilerwarnung im Testhelfer bleibt bestehen.
- Bundle-Identifier, Entitlements-Inhalte, App-Produktname, Xcode-Projekt, Scheme, Targets, Swift-Modul und persistente Datenverträge wurden nicht geändert.

### 14.6 Build- und Entwicklungsvariablen

- Neue lokale Konfigurationen verwenden `NATIVEDICTATE_TRANSCRIPTION_MODEL` und `NATIVEDICTATE_UI_TESTING`. `.env.example`, README und UI-Test wurden auf diese Primärnamen umgestellt; der App-Code wertet die NativeDictate-Namen jeweils zuerst aus.
- Die bisherigen Laufzeit-Aliase `FLOWDICTATE_TRANSCRIPTION_MODEL` und `FLOWDICTATE_UI_TESTING` bleiben für vorhandene lokale Automatisierung kompatibel. Ebenso behalten beide Release-Skripte ihre bereits eingeführte Reihenfolge `NATIVEDICTATE_*` vor `FLOWDICTATE_*`. Diese Legacy-Fallbacks bleiben ausdrücklich während der gesamten 4.x-Releaselinie bestehen und können frühestens mit einer bewusst brechenden Hauptversion entfernt werden.
- Der Packaging-Regressionstest schützt die neuen Primärnamen, die definierten Fallbacks und die ausschließlich neue Benennung in `.env.example` sowie im UI-Test. Die überflüssige `.env.example`-Ausnahme wurde aus `REBRANDING_LEGACY_ALLOWLIST.tsv` entfernt; die README-Allowlist benennt den dokumentierten 4.x-Fallback nun ausdrücklich.
- Beide Release-Skripte bestehen `zsh -n`; `git diff --check` ist leer. Die vollständige serielle macOS-Suite bestand mit 228/228 Tests und `TEST SUCCEEDED`.
- Der Lauf meldete die bekannte Actor-Isolation-Compilerwarnung im Testhelfer sowie eine bereits im unveränderten Retry-Code vorhandene Capture-Warnung. Bundle-Identifier, Keychain-Service, Persistenzpfade, Xcode-Projekt, Scheme, Targets und Swift-Modul wurden nicht geändert.

### 14.7 Quellwurzel

- Der dateisystemsynchronisierte App-Quellordner `FlowDictate/` wurde zu `NativeDictate/` umbenannt. Die zugehörige Root Group in `project.pbxproj`, aktuelle Pfadprüfungen im Branding-Regressionstest, die Legacy-Allowlist und der README-Verweis auf das App-Icon verwenden den neuen Pfad.
- Xcode-Projekt, App-Target, Testtargets, Scheme und Swift-Modul heißen in diesem Schritt weiterhin `FlowDictate`. Ebenso bleiben Bundle-Identifier, Keychain-Service, `Application Support/FlowDictate`, UserDefaults-Schlüssel und alle gespeicherten Datenverträge unverändert.
- Der kontrollierte Restscan findet außerhalb historischer Nachweise keinen alten App-Quellpfad mehr. Der verbleibende aktive String `Library/Application Support/FlowDictate/Models` ist der ausdrücklich geschützte persistente Legacy-Pfad und keine Quellordnerreferenz. `git diff --check` ist leer.
- Ein erster Testlauf im dokumentbasierten Arbeitsverzeichnis kompilierte die App bereits vollständig aus `NativeDictate/`, blieb anschließend jedoch beim Öffnen von `project.pbxproj` durch einen Regressionstest im macOS-Dateisystem hängen und wurde abgebrochen. Derselbe unveränderte Quellstand wurde deshalb in eine temporäre lokale Kopie unter `/private/tmp` übertragen.
- Aus dieser Kopie bestand die vollständige serielle macOS-Suite mit 228/228 Tests und `TEST SUCCEEDED`. Der erfolgreiche Lauf meldete weiterhin die bekannte Actor-Isolation-Compilerwarnung am Defaultwert `MockCredentialStore()` des Testhelfers; der Schritt wird daher nicht als warnungsfrei bezeichnet.

### 14.8 Test-Quellwurzeln

- Die dateisystemsynchronisierten Ordner `FlowDictateTests/` und `FlowDictateUITests/` wurden zu `NativeDictateTests/` beziehungsweise `NativeDictateUITests/` umbenannt. Die beiden Root Groups in `project.pbxproj`, der interne UI-Test-Quellpfad, die Legacy-Allowlist und aktuelle Pfadangaben in diesem Plan verwenden die neuen Verzeichnisse.
- Die enthaltenen Dateien, Swift-Testtypen, Xcode-Testtargets, Testprodukte, Bundle-Identifier und Scheme-Einträge behalten in diesem mechanisch getrennten Schritt ihre bisherigen `FlowDictateTests`- beziehungsweise `FlowDictateUITests`-Namen. Ihre optionale Umbenennung wird nicht mit der Ordneränderung vermischt.
- Der kontrollierte Restscan findet die alten Testordnerpfade nur noch im historischen R0-Namensinventar und im abgeschlossenen Phase-4.1-Arbeitsplan. Git erkennt beide verschobenen Dateien als inhaltsgleiche Umbenennungen; `git diff --check` ist leer.
- Die vollständige serielle macOS-Suite wurde aus einer unveränderten temporären Kopie ausgeführt und bestand mit 228/228 Tests sowie `TEST SUCCEEDED`. Der Build bezog die Testquellen nachweislich aus `NativeDictateTests/` und `NativeDictateUITests/`.
- Die bekannte Actor-Isolation-Compilerwarnung am Defaultwert `MockCredentialStore()` des Testhelfers bleibt von dieser reinen Pfadänderung unberührt. Bundle-Identifier, Keychain-Service, Persistenzpfade und gespeicherte Datenverträge wurden nicht geändert.

### 14.9 Testdateien und Swift-Testtypen

- `FlowDictateTests.swift` und `FlowDictateUITests.swift` wurden zu `NativeDictateTests.swift` beziehungsweise `NativeDictateUITests.swift` umbenannt. Die Dateiköpfe, der interne UI-Test-Quellpfad, aktuelle Plandokumentation und die Legacy-Allowlist verwenden die neuen Dateinamen.
- Die Swift-Testtypen heißen nun `NativeDictateTests` und `NativeDictateUITests`. Xcode-Testtargets, Testprodukte, Bundle-Identifier, Projekt, Scheme und das per `@testable import` geladene App-Modul behalten in diesem Schritt ausdrücklich ihre bestehenden FlowDictate-Namen.
- Der kontrollierte Restscan findet die alten Testdatei- und Swift-Typnamen im aktiven Projekt nicht mehr; ihre verbleibenden Pfade liegen ausschließlich in historischen Inventaren und dem abgeschlossenen Phase-4.1-Arbeitsplan. `git diff --check` ist leer.
- Die vollständige serielle macOS-Suite wurde aus einer unveränderten temporären Kopie ausgeführt und bestand mit 228/228 Tests sowie `TEST SUCCEEDED`. Swift Testing weist die Suite im Ergebnis nun als `NativeDictateTests` aus.
- Die bekannte Actor-Isolation-Compilerwarnung am Defaultwert `MockCredentialStore()` bleibt von der mechanischen Typumbenennung unberührt. Technische App-Identität, Persistenzpfade und gespeicherte Datenverträge wurden nicht geändert.

## 15. Rollback-Strategie

### 15.1 Vor der GitHub-Umschaltung

- Rebranding-Branch nicht integrieren beziehungsweise den noch unveröffentlichten Commit regulär revertieren.
- Keine Tags oder Releaseartefakte umschreiben.
- 4.1.0 bleibt unveränderte Releasebasis.

### 15.2 Nach GitHub-Umschaltung, vor Veröffentlichung

- Keine 4.2-Tags oder Releases erzeugen, solange die neue Adresse oder Updateprüfung nicht funktioniert.
- Repository nur bei einem echten Blocker zurückbenennen; zunächst Links und Releasechecker korrigieren.
- Weiterleitungen nach jeder Namensänderung erneut prüfen.

### 15.3 Nach Veröffentlichung

- Fehler durch einen neuen Patch-Release korrigieren; veröffentlichte Tags und Archive nicht ersetzen.
- Bei kritischem Migrationsfehler 4.2 als problematisch kennzeichnen und 4.1.0 als dokumentierten Rollback anbieten.
- Keine automatische Datenrückmigration ausführen.
- Da 4.2 keine Schemaänderung enthalten soll, muss ein kontrollierter Start von 4.1.0 mit unveränderten Daten vorab bewertet werden.

## 16. Definition of Done

Das Rebranding ist abgeschlossen, wenn:

- [x] das Projekt auf GitHub unter `Hank1210/NativeDictate` erreichbar ist,
- [x] alte GitHub-Links weiterhin weitergeleitet werden,
- [x] die gebaute und verteilte App `NativeDictate.app` heißt,
- [x] alle aktuellen Benutzertexte NativeDictate verwenden,
- [x] aktuelle Dokumentation, Paketnamen und Releaseprüfung auf NativeDictate zeigen,
- [x] der Bundle-Identifier weiterhin `de.mcc.FlowDictate` lautet,
- [x] bestehende 4.1-Nutzerdaten in 4.2 sichtbar und funktionsfähig sind,
- [x] keine parallele alte und neue App-Instanz erforderlich oder empfohlen ist,
- [x] verbleibende FlowDictate-Vorkommen ausschließlich Legacy-, Migrations- oder historische Bedeutung besitzen,
- [x] vollständige Testsuite, Upgrade-Test, Clean-Install-Test und Paketprüfung bestanden sind,
- [x] NativeDictate 4.2.0 mit unveränderlicher SHA-256 und dokumentiertem Release-Commit veröffentlicht ist.

## 17. Unmittelbar nächster Schritt

R0 bis R7 und damit das verbindliche Rebranding sind abgeschlossen. NativeDictate 4.2.0 ist als neueste stabile Version veröffentlicht, und die von GitHub erneut heruntergeladenen Assets sind byteidentisch mit dem getesteten Kandidaten. Es gibt keinen verpflichtenden Folgeschritt. R8 bleibt eine optionale, separat zu planende interne Namensbereinigung und ist kein Nachlauf-Gate für 4.2.0.
