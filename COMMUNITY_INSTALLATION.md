# NativeDictate Community installieren

Diese Ausgabe ist kostenlos und ad hoc signiert. Sie wurde nicht von Apple notarisiert. macOS zeigt deshalb beim ersten Start eine Sicherheitswarnung an.

Diese Anleitung gilt für NativeDictate 4.2.0 Community.

## Download prüfen

Lade die ZIP-Datei und die gleichnamige `.sha256`-Datei aus demselben GitHub Release. Öffne anschließend Terminal, wechsle in den Download-Ordner und prüfe das Archiv:

```sh
shasum -a 256 -c NativeDictate-4.2.0-Community-macOS.zip.sha256
```

Terminal muss `OK` melden. Installiere die App nicht, wenn die Prüfung fehlschlägt.

## Installation

1. Entpacke die ZIP-Datei.
2. Ziehe `NativeDictate.app` in den Ordner `Programme`.
3. Klicke in `Programme` mit der rechten Maustaste auf NativeDictate und wähle `Öffnen`.
4. Bestätige im nächsten Dialog erneut mit `Öffnen`.
5. Falls macOS nur `Abbrechen` anbietet, öffne `Systemeinstellungen → Datenschutz & Sicherheit` und klicke bei NativeDictate auf `Dennoch öffnen`.

Gib NativeDictate nur frei, wenn du die ZIP-Datei direkt von einer Person erhalten hast, der du vertraust.

## Ersteinrichtung

1. Wähle den Aufnahmeordner. Empfohlen wird `Dokumente/Recordings`.
2. Wähle die Transkription: Auf einem Apple-Silicon-Mac kannst du das lokale Parakeet-Modell herunterladen und ohne API-Key arbeiten. Alternativ trägst du deinen eigenen OpenAI API-Key ein; er wird ausschließlich im macOS-Schlüsselbund gespeichert. Auf Intel-Macs bleibt OpenAI der verfügbare finale Transkriptionsweg.
3. Erlaube Mikrofonzugriff und Bedienungshilfen.
4. Erlaube Spracherkennung nur, wenn du die optionale lokale Live Preview verwenden möchtest. Wenn die Preview trotz Freigabe `Siri and Dictation are disabled` meldet, aktiviere zusätzlich die macOS-Diktierfunktion unter `Systemeinstellungen → Tastatur → Diktierfunktion`. Die finale Transkription funktioniert auch ohne Live Preview.
5. Für einzelne Systemaudio-Diktate benötigt NativeDictate die Freigabe unter `Bildschirm- & Systemaudioaufnahme`. Für kombinierte Mikrofon- und Systemaudioaufnahmen auf macOS 14.2 oder neuer verwende den getrennten Schalter `Nur Systemaudioaufnahme`/`System Audio Recording Only`; auf macOS 14.0/14.1 wird der ScreenCaptureKit-Pfad verwendet. NativeDictate nimmt dabei nur Audio und kein Video auf.
6. Beende und öffne NativeDictate erneut, wenn macOS nach einer neuen Berechtigung dazu auffordert.
7. Lege die gewünschten Tastenkürzel fest.

Die ZIP-Datei enthält weder einen API-Key noch ein Sprachmodell oder Zugangsdaten des Erstellers. Der optionale Modelldownload wird in den Transkriptions-Einstellungen mit Quelle, Größe und Lizenz angezeigt.

Für `Microphone + System Audio` musst du die Quelle ausdrücklich auswählen und vor der ersten Aufnahme einen gesonderten Hinweis zu Information und nötiger Zustimmung aller Beteiligten bestätigen. Die Bestätigung startet noch keine Aufnahme. Im gewählten Aufnahmeordner legt NativeDictate pro Meeting zwei getrennte Originalspuren sowie Arbeits- und Transkriptdateien im Unterordner `MeetingSessions` ab. Bei 48 kHz benötigen allein die Originale ungefähr 1,4 GB pro Stunde; plane für Arbeitsdateien zusätzlichen Platz ein. Kurze Systemaudio-Lücken sind möglich und werden in History als Qualitätswarnung angezeigt. `You` bezeichnet die Mikrofonspur, nicht eine Sprechererkennung.

## Aktualisierung

**Wichtig beim Wechsel von FlowDictate 4.1.0 auf NativeDictate 4.2.0:** Die Bundle-ID bleibt `de.mcc.FlowDictate`. Dadurch verwendet NativeDictate weiterhin dieselben Einstellungen, dieselbe History, dasselbe lokale Modell, dieselbe Aufnahmeordner-Freigabe und denselben Keychain-Service. Die App-Datei heißt jedoch neu `NativeDictate.app`; Finder ersetzt `FlowDictate.app` deshalb nicht automatisch. Starte beide Apps niemals parallel.

Community-Ausgaben sind ad hoc signiert. Da sich ihre Code-Identität mit einem neuen Build ändern kann, behandelt macOS eine Aktualisierung gelegentlich wie eine neue App. Dadurch können insbesondere **Bedienungshilfen** sowie **Bildschirm- & Systemaudioaufnahme** erneut freigegeben werden müssen. Das lässt sich bei einer kostenlosen, nicht notarisierten Community-Ausgabe nicht zuverlässig vermeiden.

Verwende zum Testen immer genau die Community-ZIP, die später veröffentlicht werden soll. Ein separat gebauter oder anders signierter Test-Build ist nicht identisch mit dem Release-Artefakt.

### Empfohlener Update-Ablauf

1. Beende FlowDictate vollständig über das Menüleistensymbol. Prüfe bei Bedarf in der Aktivitätsanzeige, dass kein FlowDictate-Prozess mehr läuft.
2. Entpacke die neue Community-ZIP.
3. Ziehe `NativeDictate.app` nach `Programme`. Entferne `FlowDictate.app` noch nicht.
4. Öffne NativeDictate mit Rechtsklick und `Öffnen`. Prüfe Einstellungen, History, lokales Modell, API-Key-Status und Aufnahmeordner.
5. Teste mindestens eine Mikrofonaufnahme und Texteinfügung sowie – falls verwendet – Systemaudio. Starte FlowDictate währenddessen nicht.
6. Erneuere nur eine Berechtigung, deren Funktion tatsächlich nicht arbeitet. macOS kann wegen des neuen App-Dateinamens oder der geänderten Ad-hoc-Signatur erneut nach Mikrofon, Bedienungshilfen, Spracherkennung oder Systemaudio fragen.
7. Falls `Beim Anmelden öffnen` zuvor aktiv war, deaktiviere und aktiviere es in NativeDictate einmal erneut.
8. Entferne erst nach erfolgreicher Prüfung die alte `FlowDictate.app`. Das Löschen der alten App-Datei löscht nicht die gemeinsamen Einstellungen oder `Application Support/FlowDictate`-Daten.

Live Preview ist optional und nutzt ausschließlich Apples lokale Spracherkennung. Lokale finale Transkription, gesprochene Korrekturen, Formatierung und das persönliche Wörterbuch arbeiten auf dem Mac. Im Modus `Fully offline` blockiert NativeDictate Transkriptions-, Enhancement- und Update-Netzwerkzugriffe. Nur ein bewusst gewählter Cloudpfad sendet Audio oder Text an OpenAI; ein lokaler Fehler löst niemals automatisch einen Cloud-Upload aus.

### Schlüsselbund nach einem Update

NativeDictate 4.2.0 verwendet denselben Keychain-Service `de.mcc.FlowDictate` wie FlowDictate 4.1.0. Bei einer geänderten Ad-hoc-Signatur kann macOS einmal nach dem Anmeldepasswort fragen. Falls die Abfrage wiederholt erscheint, öffne `Settings → Transcription`, entferne dort den bisherigen API-Key und speichere ihn anschließend erneut. Dadurch wird der bestehende Schlüsselbund-Eintrag für die aktuell installierte Ausgabe neu angelegt. NativeDictate lädt ihn danach nur einmal pro App-Sitzung.

### Berechtigungen reparieren

Gehe nur für die nicht funktionierende Funktion wie folgt vor:

1. Öffne `Systemeinstellungen → Datenschutz & Sicherheit`.
2. Öffne den betroffenen Bereich: **Mikrofon**, **Bedienungshilfen**, **Spracherkennung** oder **Bildschirm- & Systemaudioaufnahme**.
3. Falls NativeDictate dort vorhanden ist, schalte die Freigabe zunächst aus und wieder ein. Starte NativeDictate danach neu und teste erneut.
4. Funktioniert es weiterhin nicht, beende NativeDictate, markiere den alten Eintrag und entferne ihn mit der Minustaste. Falls keine Minustaste angezeigt wird, deaktiviere den Eintrag.
5. Füge über die Plustaste exakt `/Applications/NativeDictate.app` hinzu und aktiviere die Freigabe. Alternativ starte die entsprechende NativeDictate-Funktion erneut und bestätige die neue macOS-Abfrage.
6. Beende NativeDictate vollständig und öffne es erneut. Wenn macOS `Beenden & erneut öffnen` anbietet, verwende diese Schaltfläche.

Zuordnung der Funktionen:

- Keine Mikrofonaufnahme: **Mikrofon**
- Aufnahme startet, aber Tastenkürzel oder Texteinfügung funktionieren nicht: **Bedienungshilfen**
- Keine lokale Live Preview: **Spracherkennung** prüfen; bei `Siri and Dictation are disabled` zusätzlich `Tastatur → Diktierfunktion` aktivieren.
- Keine einzelne Systemaudioaufnahme: **Bildschirm- & Systemaudioaufnahme**
- Keine kombinierte Systemaudiospur: unter macOS 14.2+ **Nur Systemaudioaufnahme**; unter 14.0/14.1 **Bildschirm- & Systemaudioaufnahme**

Bei einer **einzelnen Systemaudioaufnahme** zeigt macOS gegebenenfalls eine Abfrage für Bildschirm- & Systemaudioaufnahme, obwohl NativeDictate nur Audio verarbeitet. Der Schalter kann nach einem neuen ad-hoc signierten Build noch eingeschaltet aussehen, obwohl macOS die alte Code-Identität nicht mehr akzeptiert. Entferne in diesem Fall NativeDictate aus **Bildschirm- & Systemaudioaufnahme**, füge exakt `/Applications/NativeDictate.app` wieder hinzu und starte die App vollständig neu. Dies ist eine andere Freigabe als **Bedienungshilfen**.

Setze nicht alle Datenschutzrechte gleichzeitig zurück. So bleiben bereits funktionierende Freigaben erhalten und der Update-Aufwand bleibt möglichst gering.
