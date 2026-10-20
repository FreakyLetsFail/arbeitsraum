# Arbeitsraum

Native macOS-App für Dokumente, Tabellen und einen Chat mit lokalen Sprachmodellen. Projekte können mehrere Dateien, einen gespeicherten Chatverlauf und ein bearbeitbares Projektgedächtnis enthalten.

**Entwicklungsstand:** nutzbare Office-Grundfunktionen, noch kein vollständiger Word-/Excel-Ersatz. Apple Silicon, macOS 14 oder neuer. Keine geprüfte Gesundheitssoftware und keine behauptete DSGVO-Konformität.

## Funktionen

- **Projekte:** Übersicht, Suche, Neuanlage mit optionaler Vorlage, mehrere Dokumente und Tabellenblätter. Die Schaltfläche „Alle Projekte“ führt zur Übersicht zurück. Projektname und Dateinamen sind getrennt bearbeitbar.
- **Dokumente:** nativer Rich-Text-Editor mit Undo, Überschriften, Schriftfamilie, Schriftgröße, Fett/Kursiv/Unterstrichen, Absatzausrichtung, einfachem Aufzählungspunkt, Zoom und macOS-Druckdialog einschließlich PDF-Ausgabe. RTF und Klartext werden gemeinsam gespeichert.
- **Tabellen:** Zeilen-/Spaltenköpfe, verstellbare Spaltenbreiten, Bearbeitungszeile, Doppelklick, Tab/Shift-Tab/Enter und TSV-Einfügen. Grundformeln mit Zellbezügen, Bereichen, `+ - * / ^`, SUM/SUMME, AVERAGE/MITTELWERT, MIN, MAX und COUNT/ANZAHL. Dezimalpunkt; Komma oder Semikolon trennt Funktionsargumente. Formelrohtext bleibt erhalten. Die Statussumme bezieht sich auf das ganze Blatt und zählt enthaltene Zwischensummen mit.
- **Dateien:** TXT/Markdown/RTF/DOCX, UTF-8 CSV/TSV, XLSX, PDF und PNG/JPEG hinzufügen. Originale werden ins Projekt kopiert. Mehrere XLSX-Blätter werden getrennte Projektdateien. PDF-Text und Bild-OCR werden auf dem Mac ausgelesen. Gescannte PDFs ohne Textschicht werden ausdrücklich als nicht auslesbar angezeigt; PDF-OCR ist noch nicht eingebaut.
- **Export:** DOCX mit einfacher Zeichenformatierung, RTF, TXT, CSV sowie alle Tabellen eines Projekts als XLSX-Arbeitsmappe. Komplexe Office-Dokumente werden nicht verlustfrei roundtrip-fähig verarbeitet; Originale bleiben erhalten.
- **Chat rechts:** **Enter sendet**, **Shift+Enter** fügt eine Zeile ein. Dateien per Büroklammer auswählen oder hinzufügen. Die Checkbox aktiviert die Suche über die Projektdateien. Vollständige Antworten können kopiert, bearbeitet oder in das aktive Dokument eingefügt werden. Der Chat verändert Tabellen nicht automatisch.
- **Gedächtnis:** explizite Notizen pro Projekt; ändern/löschen über „Gedächtnis“, aus einer Antwort mit „Merken“ und anschließender Prüfung übernehmen. Bis 20 Notizen; die ersten 3.000 Zeichen werden übergeben. Kein automatisches Training und keine automatische Übernahme von Modellbehauptungen.
- **Vorlagen und Anweisungen:** Such-/Typfilter, Duplizieren und getrennte Inhalts-/Anweisungsbereiche. Tabellenvorlagen verwenden TSV. Bestehende Projekte behalten ihre eigenen Chat-Anweisungen.
- **Audio:** Import oder Mikrofonaufnahme, anschließend auf Wunsch Apple Speech mit verpflichtender On-Device-Erkennung. Ohne verfügbares deutsches Offline-Sprachmodell wird abgebrochen. Transkripte müssen geprüft werden und können in ein Dokument übernommen werden. LLM und Spracherkennung sind getrennt.

## Projektwissen: lokale Suche statt Training

Die App zerlegt ausgelesenen Text in überlappende Abschnitte und bewertet Treffer anhand gemeinsamer Suchwörter. Explizite Anhänge erhalten Vorrang. Bis acht Auszüge mit insgesamt höchstens 8.000 Zeichen werden als Quellen übergeben und bei der Antwort aufklappbar gespeichert. Die Notizen und die letzten sechs vollständigen Chatnachrichten (je bis 1.500 Zeichen) ergänzen den Kontext.

Das ist eine einfache lokale RAG-Grundlage mit Wortsuche, noch keine semantische Suche mit Embeddings. Nicht alle Seiten einer großen Datei werden bei jeder Frage geprüft. Die angezeigten Auszüge zeigen, was dem Modell gegeben wurde; sie bestätigen nicht die Richtigkeit einer Modellantwort. Neue Modellsitzungen pro Anfrage verhindern einen versteckten Modellcache zwischen Projekten.

Für wechselnde Projektunterlagen ist Retrieval der erste Schritt. Fine-Tuning kann später Stil oder wiederkehrende Aufgaben verbessern, benötigt dafür geeignete, geprüfte Trainingsbeispiele und vergrößert das Kontextfenster nicht. Grundlage: [Retrieval-Augmented Generation, Lewis et al.](https://arxiv.org/abs/2005.11401).

## Offline-Nutzung und Modelle

Der **Offline-Modus ist standardmäßig aktiv**. Er sperrt Modelldownloads und Verbindungen zu optionalen Modellservern. Installierte MLX-Modelle, Dokumente, Tabellen, Dateiauslesen, Gedächtnis und verfügbare On-Device-Spracherkennung benötigen keine Internetverbindung.

Für die einmalige Einrichtung: unter **Modelle & Einstellungen → Datenschutz** Downloads freigeben, ein Modell herunterladen und danach Offline-Modus wieder aktivieren. Der öffentliche Modellkatalog ist in der App enthalten und wird nicht automatisch online aktualisiert. Downloads enthalten keine Projekttexte, Prompts oder Audiodateien. Gewichte sind kein Bestandteil dieses Repositorys.

Der Katalog enthält 26 Einträge: 17 native MLX-Textmodelle, acht Optionen für einen separaten lokalen Server und eine hier inkompatible Nota-Variante. Die Empfehlung berücksichtigt Hardware, sämtliche Modellgewichte und eine geschätzte Kontext-/Systemreserve. Sie ist kein Qualitätsbenchmark und keine fachliche Eignungsbewertung. Bei MoE müssen auch die nicht aktiven Gewichte in den Speicher passen.

Qwen3 0,6B und LFM2.5 1,2B Instruct wurden auf einem M2 mit 16 GB tatsächlich geladen und zur Textgenerierung verwendet. Größere Modelle, MiniCPM und Ollama wurden hier nicht praktisch geprüft. MiniCPM-V 4.7 35B-A3B ist als lokale Serveroption erfasst; native Bild-/Video-Inferenz mit MiniCPM ist nicht eingebaut. Importierte Bilder liefern derzeit lokal erkannten Text an den Chat.

Details: [MODELS.md](MODELS.md). Grenzen dieser Version: **6.000 Eingabetokens**, **1.536 Ausgabetokens**, **8K KV-Cache**. Zu lange Eingaben werden mit einer Fehlermeldung abgewiesen. Thinking-Modelle können das Ausgabelimit früh erreichen.

## Entwicklung mit Xcode

```sh
# Optional neu erzeugen; das generierte Xcode-Projekt ist enthalten.
xcodegen generate
./build.sh build
./build.sh test
```

`LokalKIWorkspace.xcodeproj` öffnen, Scheme **LokalKIWorkspace**, Ziel **My Mac**. Xcode mit Swift 6.4 und installiertem Metal-Compiler wurde verwendet. Pakete sind per Version und `Package.resolved` festgelegt: MLX Swift LM 3.32.3, MLX Swift 0.32.3, Swift Transformers 1.3.5 und ZIPFoundation 0.9.20.

Falls Xcode nur einen Metal-Platzhalter enthält, den offiziellen Compiler unter **Xcode → Settings → Components** installieren. `build.sh` unterstützt auch eine bereits vorhandene offizielle Metal-Toolchain unter `~/Library/Developer/Toolchains/`. Das gebaute Programm benötigt Xcode nicht. Lokale Entwicklungsbauten sind ad hoc signiert und nicht notarisiert.

## Prüfstand

Stand 20.10.2026, M2 / 16 GB / Xcode 27.1: **28 XCTest-Fälle erfolgreich**, einschließlich echter lokaler MLX-Inferenz mit synthetischen Projektquellen, Chatverlauf, Modellwechsel und Entladen. Weitere Tests decken Persistenz/Migration, Importkopien, Projektisolation, Quellenbudgets, DOCX- und XLSX-Roundtrips, CSV, Formeln/Fehlerfälle, begrenzte Referenzauswertung und gesperrte Downloads im Offline-Modus ab.

Der Modelltest lädt niemals Gewichte nach und wird auf einem Mac ohne die beiden benötigten Installationen übersprungen. Audioaufnahme/Transkription wurde in dieser Erweiterung nicht mit echten Aufnahmen erneut geprüft. Es wurden keine Transkripte simuliert. Manuell geprüft wurden die Rückkehr über „Alle Projekte“, mehrere Dateien pro Projekt, Dokumentformatierung, Gedächtnisnotiz, Enter/Shift+Enter, eine echte Antwort aus Dokument und Gedächtnis, Quellenanzeige, TSV-Einfügen, Formelbearbeitung mit Tab-Navigation, sofortige Aktualisierung abhängiger Zellwerte und die Vorlagenoberfläche. Projekte und zusätzliche Dateien blieben nach Neustart erhalten. Die Bedienverbindung und native Dateidialoge waren zeitweise durch macOS-Aufnahmefehler gestört; die Dialogprüfung war deshalb eingeschränkt. DOCX- und XLSX-Testexporte wurden zusätzlich mit unabhängigen Bibliotheken (python-docx und openpyxl) erfolgreich gelesen, einschließlich Fettformatierung, mehreren Blättern, Formeln und Text mit führenden Nullen.

## Speicherung und Grenzen

Lokaler Speicher: `~/Library/Containers/de.justuswaechter.LokalKIWorkspace/Data/Library/Application Support/LokalKIWorkspace`.

`Projects/` enthält JSON mit Text, RTF, Chat, Gedächtnis und ausgelesenen Inhalten; `Files/` die importierten Originale, `Audio/` die Aufnahmen und `Models/` die Gewichte. Projektlöschung verwendet den macOS-Papierkorb. Entfernen einer einzelnen Projektdatei blendet sie aus dem Projekt aus; ihr Original bleibt bis zur Projektlöschung erhalten. Frühere Chatquellen bleiben als Auszug im Verlauf.

Keine Cloud-Inferenz, Synchronisation, Telemetrie oder automatische Fehlerübertragung ist implementiert. Native MLX-Inferenz und Tokenizer laden ausschließlich lokale Dateien. Optionale Server sind auf HTTP-Loopback beschränkt; Cloud-Tags und Weiterleitungen werden abgelehnt. Das Verhalten eines separat installierten Servers kann die App nicht garantieren.

Dateirechte sind eingeschränkt. Es gibt **keine zusätzliche anwendungsseitige Verschlüsselung**, Benutzerverwaltung oder zertifizierte Lösch-/Aufbewahrungsfunktion. Geräteschutz, Backups und andere Prozesse desselben Benutzerkontos liegen außerhalb dieser App. Fachliche Inhalte und Modellantworten müssen geprüft werden.

## Rückmeldungen und Weiterentwicklung

[Fehler, Erweiterungen oder Verbesserungen melden](https://github.com/FreakyLetsFail/arbeitsraum/issues/new/choose). Die App bietet denselben Link in **Hilfe** und **Datenschutz**. Er öffnet nur auf ausdrücklichen Klick den Browser und benötigt Internet; der Arbeitsbereich bleibt unabhängig davon offline nutzbar. Es werden keine Inhalte oder Logs vorausgefüllt oder hochgeladen.

**Keine Patienten-, Schüler-, Klienten- oder sonstigen vertraulichen Daten in öffentlichen Issues veröffentlichen.** Sicherheitslücken: [SECURITY.md](SECURITY.md). Beiträge: [CONTRIBUTING.md](CONTRIBUTING.md). Funktionsgrenzen und nächste Schritte: [ROADMAP.md](ROADMAP.md).

## Lizenz

MIT für den App-Quellcode und das originale App-Symbol. [Abhängigkeiten](THIRD_PARTY_NOTICES.md) und Modellgewichte haben eigene Lizenzen; die MIT-Lizenz der App umfasst diese nicht.
