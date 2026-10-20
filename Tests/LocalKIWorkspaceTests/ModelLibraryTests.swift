import AppKit
import CryptoKit
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

}
