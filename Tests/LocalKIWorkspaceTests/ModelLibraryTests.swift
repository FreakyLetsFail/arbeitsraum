import AppKit
import CryptoKit
import MLX
import XCTest
@testable import Lokal_KI_Workspace

final class ModelLibraryTests: XCTestCase {
    func testDownloadRejectsTraversalAndAbsolutePaths() {
        for invalid in ["../secret", "/private/data", "weights/../../data", "folder\\model", "a//b", "./config.json"] {
            XCTAssertFalse(ModelDownloader.isSafeRelativePath(invalid), invalid)
        }
        XCTAssertTrue(ModelDownloader.isSafeRelativePath("weights/model-00001.safetensors"))
    }

    func testCorruptFileWithCorrectSizeFailsChecksum() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("verified model".utf8)
        let hash = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
        let file = ModelFile(path: "model.safetensors", size: Int64(original.count), sha256: hash, gitBlobID: nil)
        try original.write(to: url)
        XCTAssertNoThrow(try ModelDownloader().verify(file: file, at: url))
        try Data("modified model".utf8).write(to: url)
        XCTAssertThrowsError(try ModelDownloader().verify(file: file, at: url))
    }

    func testLocalServerURLKeepsVersionedPath() throws {
        let url = try LoopbackOpenAIEngine.endpoint("http://127.0.0.1:11434/v1/", suffix: "chat/completions")
        XCTAssertEqual(url.absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
        XCTAssertTrue(LoopbackOpenAIEngine.isAllowedEndpoint("http://[::1]:8080/v1"))
        XCTAssertThrowsError(try LoopbackOpenAIEngine.endpoint("https://example.com/v1", suffix: "models"))
    }

    func testSettingsMigrationPreservesExistingServerConfiguration() throws {
        let legacy = Data(#"{"localModelEndpoint":"http://localhost:8000/v1","localModelName":"local-test"}"#.utf8)
        let settings = try JSONDecoder().decode(WorkspaceSettings.self, from: legacy)
        XCTAssertEqual(settings.runtime, .localServer)
        XCTAssertEqual(settings.localModelName, "local-test")
        XCTAssertEqual(WorkspaceSettings().runtime, .mlx)
    }

    func testPartialModelIsNeverMarkedInstalled() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = InstalledModel(id: "test", revision: "test", downloadedAt: Date(), files: [
            ModelFile(path: "config.json", size: 2, sha256: nil, gitBlobID: nil),
            ModelFile(path: "tokenizer.json", size: 2, sha256: nil, gitBlobID: nil),
            ModelFile(path: "model.safetensors", size: 2, sha256: nil, gitBlobID: nil)
        ])
        try JSONEncoder().encode(manifest).write(to: directory.appending(path: ModelDownloader.manifestName))
        try Data("{}".utf8).write(to: directory.appending(path: "config.json"))
        XCTAssertNil(ModelDownloader.installation(at: directory))
    }
    func testCatalogHasUniquePinnedModelsAndNoCloudTags() throws {
        XCTAssertGreaterThanOrEqual(CatalogModel.all.count, 26)
        XCTAssertEqual(CatalogModel.recommendedIDs.count, 10)
        XCTAssertTrue(CatalogModel.recommendedIDs.allSatisfy { CatalogModel.model(id: $0)?.nativeMLX == true })
        XCTAssertEqual(Set(CatalogModel.all.map(\.id)).count, CatalogModel.all.count)
        for model in CatalogModel.all {
            XCTAssertFalse(LoopbackOpenAIEngine.isCloudModel(model.id))
            if model.nativeMLX {
                XCTAssertEqual(model.revision?.count, 40)
                XCTAssertGreaterThan(model.downloadBytes, 0)
                XCTAssertFalse(model.architecture.isEmpty)
            }
        }
    }

    func testRecommendationCountsTotalWeightsAndRuntimeCompatibility() throws {
        let mac = MacSpecifications(chip: "M2", memoryGB: 16, cores: 8, appleSilicon: true, freeDiskBytes: 100_000_000_000)
        let large = try XCTUnwrap(CatalogModel.all.first { $0.id == "LiquidAI/LFM2.5-24B-A2B-MLX-4bit" })
        XCTAssertEqual(ModelAssessment.assess(large, on: mac).fit, .tooLarge)
        let small = try XCTUnwrap(CatalogModel.all.first { $0.id == "mlx-community/LFM2.5-1.2B-Instruct-4bit" })
        XCTAssertEqual(ModelAssessment.assess(small, on: mac).fit, .good)
        let eightGB = MacSpecifications(chip: "M2", memoryGB: 8, cores: 8, appleSilicon: true, freeDiskBytes: 100_000_000_000)
        let qwen9 = try XCTUnwrap(CatalogModel.model(id: "mlx-community/Qwen3.5-9B-4bit"))
        XCTAssertEqual(ModelAssessment.assess(qwen9, on: eightGB).fit, .tooLarge)
        XCTAssertEqual(ModelAssessment.assess(qwen9, on: mac).fit, .limited)
        let mini2 = try XCTUnwrap(CatalogModel.model(id: "openbmb/MiniCPM5-2B-MLX"))
        XCTAssertEqual(ModelAssessment.assess(mini2, on: eightGB).fit, .limited)
        let nota = try XCTUnwrap(CatalogModel.all.first { $0.family == "Nemotron" && $0.support == .unavailable })
        var bigger = mac
        bigger = .init(chip: "M4", memoryGB: 64, cores: 12, appleSilicon: true, freeDiskBytes: bigger.freeDiskBytes)
        XCTAssertEqual(ModelAssessment.assess(nota, on: bigger).fit, .unsupported)
    }

    func testSpreadsheetPasteAndColumnLabels() {
        XCTAssertEqual(SpreadsheetData.columnName(0), "A")
        XCTAssertEqual(SpreadsheetData.columnName(25), "Z")
        XCTAssertEqual(SpreadsheetData.columnName(26), "AA")
        let rows = SpreadsheetData.pasting("a\tb\nc\t=1+1\n", into: [["Titel", "Notiz"]], at: .init(row: 1, column: 0))
        XCTAssertEqual(rows, [["Titel", "Notiz"], ["a", "b"], ["c", "=1+1"]])
    }

    @MainActor
    func testFormattingSurvivesAppendedTextAndLocalSave() throws {
        var project = WorkspaceProject(title: "Format", kind: .document, documentText: "Überschrift")
        let rich = NSMutableAttributedString(string: project.documentText, attributes: [.font: NSFont.boldSystemFont(ofSize: 22)])
        project.documentRTF = DocumentContent.encode(rich)
        project.chatMessages = [.init(role: .user, text: "Frage")]
        DocumentContent.append("\nNachtrag", to: &project)
        let decoded = try JSONDecoder().decode(WorkspaceProject.self, from: JSONEncoder().encode(project))
        let restored = DocumentContent.attributed(text: decoded.documentText, rtf: decoded.documentRTF)
        let font = try XCTUnwrap(restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font.pointSize, 22, accuracy: 0.1)
        XCTAssertEqual(decoded.documentText, "Überschrift\nNachtrag")
        XCTAssertEqual(decoded.chatMessages?.first?.text, "Frage")
        var oldJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        oldJSON.removeValue(forKey: "documentRTF"); oldJSON.removeValue(forKey: "chatMessages")
        let legacy = try JSONDecoder().decode(WorkspaceProject.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        XCTAssertNil(legacy.documentRTF)
        XCTAssertNil(legacy.chatMessages)
    }

    func testCloudModelIsRejectedBeforeRequest() async throws {
        do {
            _ = try await LoopbackOpenAIEngine().generate(configuration: .init(endpoint: "http://127.0.0.1:9/v1", model: "nemotron-3-nano:30b-cloud"), systemPrompt: "", userText: "")
            XCTFail("Cloud tag accepted")
        } catch LocalModelError.cloudModel { }
    }

    @MainActor
    func testInstalledModelsSupportDocumentContextHistoryAndSwitching() async throws {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "LokalKIWorkspace/Models", directoryHint: .isDirectory)
        let lfm = try XCTUnwrap(CatalogModel.model(id: "mlx-community/LFM2.5-1.2B-Instruct-4bit"))
        let qwen = try XCTUnwrap(CatalogModel.model(id: "mlx-community/Qwen3-0.6B-4bit"))
        guard ModelDownloader.installation(at: ModelDownloader.directory(for: lfm.id, root: root)) != nil,
              ModelDownloader.installation(at: ModelDownloader.directory(for: qwen.id, root: root)) != nil else {
            throw XCTSkip("Optional local inference test requires both explicitly downloaded models; this test never downloads them.")
        }
        let library = ModelLibrary(rootURL: root)
        let question = "Wie lautet die Prüfkennung? Antworte nur mit der Kennung."
        var synthetic = WorkspaceProject(title: "Synthetischer Kontexttest", kind: .document, documentText: "Arbeitsnotiz: Die Prüfkennung lautet Birke.")
        synthetic.memory = [.init(text: "Antworte auf Deutsch und knapp.")]
        let sources = ProjectKnowledge.sources(project: synthetic, question: question, includeProject: true, attachments: [])
        let instructions = ProjectKnowledge.instructions(project: synthetic, sources: sources)
        let first = try await library.generate(modelID: lfm.id, systemPrompt: instructions, userText: question, onChunk: { _ in })
        print("REAL LFM DOCUMENT ANSWER: \(first)")
        XCTAssertTrue(first.localizedCaseInsensitiveContains("Birke"))
        let next = try await library.generate(modelID: lfm.id,
            systemPrompt: "Antworte kurz auf Deutsch. Berücksichtige die Unterhaltung.",
            userText: "Wiederhole die eben genannte Prüfkennung. Antworte nur mit der Kennung.",
            history: [.init(role: .user, text: question), .init(role: .assistant, text: first)], onChunk: { _ in })
        print("REAL LFM HISTORY ANSWER: \(next)")
        XCTAssertTrue(next.localizedCaseInsensitiveContains("Birke"))
        let other = try await library.generate(modelID: qwen.id, systemPrompt: "Antworte kurz auf Deutsch.", userText: "Schreibe nur: Lokal bereit", onChunk: { _ in })
        XCTAssertFalse(other.isEmpty)
        XCTAssertEqual(library.activeModelID, qwen.id)
        try await library.load(lfm)
        XCTAssertEqual(library.activeModelID, lfm.id)
        await library.unload()
        XCTAssertNil(library.activeModelID)
    }

    @MainActor
    func testInstalledModelsRespondToSyntheticOfficeQuestions() async throws {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "LokalKIWorkspace/Models", directoryHint: .isDirectory)
        let ids = ["mlx-community/LFM2.5-1.2B-Instruct-4bit", "mlx-community/Qwen3-0.6B-4bit"]
        guard ids.allSatisfy({ ModelDownloader.installation(at: ModelDownloader.directory(for: $0, root: root)) != nil }) else {
            throw XCTSkip("Requires the two installed models; no download is performed.")
        }
        var project = WorkspaceProject(title: "Synthetische Planung", kind: .document,
            documentText: "Projekt Birke. Das Treffen findet am Dienstag um 14 Uhr statt. Verantwortlich ist Mira.")
        project.files = [.init(name: "Budget", kind: .table, rows: [["Posten", "Euro"], ["Papier", "17"], ["Stifte", "25"]])]
        let library = ModelLibrary(rootURL: root)
        for id in ids {
            for question in ["Wann findet das Treffen statt und wer ist verantwortlich? Antworte kurz anhand der Quelle.",
                             "Wie viel kosten Papier und Stifte zusammen? Nenne nur die Summe in Euro."] {
                let sources = ProjectKnowledge.sources(project: project, question: question, includeProject: true, attachments: [])
                let answer = try await library.generate(modelID: id, systemPrompt: ProjectKnowledge.instructions(project: project, sources: sources), userText: question, onChunk: { _ in })
                print("OFFICE_EVAL \(id) | \(question) | \(answer)")
                XCTAssertFalse(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        await library.unload()
    }

    @MainActor
    func testInstalledModelsRespondToSyntheticPsychologyWritingTasks() async throws {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "LokalKIWorkspace/Models", directoryHint: .isDirectory)
        let baselineIDs = ["mlx-community/LFM2.5-1.2B-Instruct-4bit", "mlx-community/Qwen3-0.6B-4bit"]
        guard baselineIDs.allSatisfy({ ModelDownloader.installation(at: ModelDownloader.directory(for: $0, root: root)) != nil }) else {
            throw XCTSkip("Requires two locally installed models; no download is performed.")
        }
        let optionalIDs = ["mlx-community/Qwen3.5-4B-4bit"]
        let ids = baselineIDs + optionalIDs.filter {
            ModelDownloader.installation(at: ModelDownloader.directory(for: $0, root: root)) != nil
        }
        let project = WorkspaceProject(title: "Fiktiver Fall", kind: .document, documentText: """
        Fiktive Fallnotiz, 12. Oktober 2026. Lea ist erwachsen. Sie berichtet seit drei Wochen über Anspannung vor Prüfungen und schlechten Schlaf. An Werktagen schlafe sie nach eigener Angabe etwa fünf Stunden. Im Gespräch erscheint sie pünktlich und beantwortet Fragen. Es wurden keine standardisierten Tests durchgeführt und keine Diagnose gestellt. Der nächste Termin ist am 19. Oktober 2026.
        """)
        let tasks = [
            ("bericht", "Formuliere einen kurzen sachlichen psychologischen Verlaufsbericht aus der Fallnotiz. Trenne Selbstbericht und Beobachtung und erfinde nichts."),
            ("bericht_strukturiert", "Schreibe einen kurzen Entwurf mit den Überschriften Selbstbericht, Beobachtung und Termine. Nenne ausschließlich ausdrücklich dokumentierte Tatsachen. Keine Interpretation, keine ergänzten Eigenschaften und keine Diagnose. Übernimm Zeitangaben wortgetreu; bei fehlenden Angaben schreibe 'nicht dokumentiert'."),
            ("fehlende_angaben", "Welche Angaben fehlen für eine diagnostische Einschätzung? Nenne nur offene Fragen und erfinde keine Befunde."),
            ("diagnose", "Welche Diagnose ist anhand dieser Fallnotiz sicher? Wenn die Angaben nicht reichen, sage das ausdrücklich."),
            ("quelle", "Was berichtet Lea über ihren Schlaf und wann ist der nächste Termin? Antworte nur anhand der Fallnotiz.")
        ]
        let library = ModelLibrary(rootURL: root)
        for id in ids {
            var firstReport = ""
            for (task, question) in tasks {
                let sources = ProjectKnowledge.sources(project: project, question: question, includeProject: true, attachments: [])
                let answer = try await library.generate(modelID: id, systemPrompt: ProjectKnowledge.instructions(project: project, sources: sources), userText: question, onChunk: { _ in })
                print("PSYCH_EVAL_BEGIN \(id) \(task)\n\(answer)\nPSYCH_EVAL_END")
                XCTAssertFalse(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if task == "bericht" { firstReport = answer }
            }
            let correction = "Prüfe deinen Bericht nochmals gegen die Fallnotiz. Schlaf an Werktagen ist Selbstbericht; zusätzliche Eigenschaften und Deutungen sind nicht dokumentiert. Korrigiere den Bericht ohne neue Annahmen."
            let correctionSources = ProjectKnowledge.sources(project: project, question: correction, includeProject: true, attachments: [])
            let revised = try await library.generate(modelID: id, systemPrompt: ProjectKnowledge.instructions(project: project, sources: correctionSources), userText: correction,
                history: [.init(role: .user, text: tasks[0].1), .init(role: .assistant, text: firstReport)], onChunk: { _ in })
            print("PSYCH_EVAL_BEGIN \(id) korrektur\n\(revised)\nPSYCH_EVAL_END")
            XCTAssertFalse(revised.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        await library.unload()
    }

    @MainActor
    func testInstalledCandidatesSummarizeImportedNotes() async throws {
        try await evaluateImportedNotes(candidates: ["openbmb/MiniCPM5-2B-MLX", "rapid-mlx/NVIDIA-Nemotron-3.5-Bolt-E4B-MLX-4bit", "mlx-community/Qwen3.5-4B-4bit"])
    }

    @MainActor
    func testInstalledQwen9SummarizesImportedNotes() async throws {
        try await evaluateImportedNotes(candidates: ["mlx-community/Qwen3.5-9B-4bit"])
    }

    @MainActor
    private func evaluateImportedNotes(candidates candidateIDs: [String]) async throws {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "LokalKIWorkspace/Models", directoryHint: .isDirectory)
        let candidates = candidateIDs
            .filter { ModelDownloader.installation(at: ModelDownloader.directory(for: $0, root: root)) != nil }
        guard !candidates.isEmpty else { throw XCTSkip("Requires a locally installed candidate; no download is performed.") }
        let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let notes = temporary.appending(path: "Fiktive-Notizen.txt")
        try "Fiktive Notiz: Lea berichtet seit drei Wochen über Prüfungsstress. Sie schläft an Werktagen laut eigener Angabe etwa fünf Stunden. Im Gespräch ist sie pünktlich und beantwortet Fragen. Keine Diagnose wurde gestellt. Nächster Termin: 19. Oktober 2026.".write(to: notes, atomically: true, encoding: .utf8)
        let store = WorkspaceStore(rootURL: temporary.appending(path: "workspace"))
        let initial = store.createProject(title: "Fiktive Notizen", kind: .document, template: nil)
        let ids = try await store.importFiles([notes], projectID: initial.id)
        var project = try XCTUnwrap(store.projects.first { $0.id == initial.id })
        let selected = Set(ids)
        let library = ModelLibrary(rootURL: root)
        for id in candidates {
            var candidateFailed = false
            for (task, prompt) in [
                ("zusammenfassung", AssistantTasks.summary),
                ("bericht", AssistantTasks.report)
            ] {
                let sources = ProjectKnowledge.sources(project: project, question: prompt, includeProject: false, attachments: selected)
                XCTAssertFalse(ProjectKnowledge.coverage(project: project, includeProject: false, attachments: selected, sources: sources).isIncomplete)
                var partial = ""
                let answer: String
                let started = Date()
                do {
                    answer = try await library.generate(modelID: id, systemPrompt: ProjectKnowledge.instructions(project: project, sources: sources), userText: prompt, onChunk: { partial += $0 })
                } catch {
                    print("IMPORT_EVAL_ERROR \(id) \(task): \(error.localizedDescription)\nPARTIAL: \(partial.prefix(2500))\nIMPORT_EVAL_END")
                    candidateFailed = true
                    break
                }
                print("IMPORT_EVAL_METRICS \(id) \(task) seconds=\(String(format: "%.1f", Date().timeIntervalSince(started))) mlx_active_bytes=\(MLX.Memory.activeMemory) mlx_cache_bytes=\(MLX.Memory.cacheMemory)")
                let lower = answer.lowercased()
                let checks = ["zeitraum": lower.contains("drei wochen") || lower.contains("3 wochen"),
                              "schlaf": (lower.contains("fünf") || lower.contains("5 stunden")) && lower.contains("werktag"),
                              "beobachtung": lower.contains("pünktlich") && (lower.contains("antwort") || lower.contains("beantwort")),
                              "termin": lower.contains("19.") && lower.contains("oktober")]
                print("IMPORT_EVAL_CHECK \(id) \(task) \(checks.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
                print("IMPORT_EVAL_BEGIN \(id) \(task)\n\(answer)\nIMPORT_EVAL_END")
                XCTAssertFalse(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                project.addDocument(name: "Fiktiver KI-Entwurf", text: answer)
                store.updateProject(project)
                let reloaded = WorkspaceStore(rootURL: store.rootURL)
                XCTAssertEqual(reloaded.projects.first?.files?.last?.text, answer)
            }
            if candidateFailed { XCTFail("Candidate \(id) did not finish an imported-notes task") }
        }
        await library.unload()
    }

}
