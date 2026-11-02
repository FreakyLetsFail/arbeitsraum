import AppKit
import XCTest
@testable import Lokal_KI_Workspace

final class ProjectFilesTests: XCTestCase {
    @MainActor
    func testMultipleFilesMemorySourcesPersistAndEditingKeepsProjectChat() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(rootURL: root)
        var project = store.createProject(title: "Synthetisches Testprojekt", kind: .document, template: nil)
        let file = WorkspaceFile(name: "Notiz", kind: .document, text: "Vorher")
        project.files = [file]; project.memory = [.init(text: "Nur synthetische Testdaten")]
        project.chatMessages = [.init(role: .user, text: "Testfrage", attachmentIDs: [file.id])]
        var edit = project.content(for: file.id); edit.documentText = "Nachher"; edit.title = "Umbenannt"
        project.updateContent(edit, fileID: file.id)
        XCTAssertEqual(project.title, "Synthetisches Testprojekt")
        XCTAssertEqual(project.files?.first?.text, "Nachher")
        XCTAssertEqual(project.chatMessages?.first?.attachmentIDs, [file.id])
        store.updateProject(project)
        let loaded = try XCTUnwrap(WorkspaceStore(rootURL: root).projects.first)
        XCTAssertEqual(loaded, store.projects.first)
        XCTAssertEqual(loaded.memory?.first?.text, "Nur synthetische Testdaten")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        for key in ["files", "primaryFileName", "memory"] { json.removeValue(forKey: key) }
        let legacy = try JSONDecoder().decode(WorkspaceProject.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.allFiles.count, 1)
        XCTAssertEqual(legacy.documentText, project.documentText)
    }
    func testRetrievalIsPerProjectBoundedAndSupportsExplicitAttachments() {
        var first = WorkspaceProject(title: "Eins", kind: .document, documentText: "Die Prüfkennung lautet Birke.")
        let table = WorkspaceFile(name: "Punkte", kind: .table, rows: [["Fach", "Punkte"], ["Mathe", "12"]])
        first.files = [table]; first.memory = [.init(text: "Antworte auf Deutsch.")]
        let second = WorkspaceProject(title: "Zwei", kind: .document, documentText: "VERTRAULICHE-FREMDE-KENNUNG")
        let sources = ProjectKnowledge.sources(project: first, question: "Wie viele Punkte Mathe?", includeProject: false, attachments: [table.id])
        XCTAssertEqual(Set(sources.map(\.fileID)), [table.id])
        XCTAssertTrue(sources.map(\.excerpt).joined().contains("12"))
        let instructions = ProjectKnowledge.instructions(project: first, sources: sources)
        XCTAssertFalse(instructions.contains(second.documentText))
        XCTAssertTrue(instructions.contains("Antworte auf Deutsch."))
        XCTAssertTrue(ProjectKnowledge.sources(project: first, question: "", includeProject: false, attachments: []).isEmpty)
        let bounded = ProjectKnowledge.sources(project: first, question: "Prüfkennung", includeProject: true, attachments: [], budget: 25)
        XCTAssertLessThanOrEqual(bounded.reduce(0) { $0 + $1.excerpt.count }, 25)
    }
    func testRetrievalLimitsEvenManyExplicitAttachments() {
        var project = WorkspaceProject(title: "Test", kind: .document)
        let files = (0..<12).map { WorkspaceFile(name: "Datei \($0)", kind: .document, text: "Inhalt \($0)") }
        project.files = files
        let sources = ProjectKnowledge.sources(project: project, question: "Inhalt", includeProject: false, attachments: Set(files.map(\.id)))
        XCTAssertEqual(sources.count, 8)
        XCTAssertEqual(Set(sources.map(\.fileID)).count, 8)
    }
    @MainActor
    func testDOCXRoundTripKeepsTextAndBold() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rich = NSAttributedString(string: "Übung & Bericht\nEine Zeile", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)])
        let file = WorkspaceFile(name: "Test", kind: .document, text: rich.string, rtf: DocumentContent.encode(rich))
        let url = root.appendingPathComponent("test.docx")
        try OfficeFiles.writeDOCX(file, to: url)
        let attachment = XCTAttachment(data: try Data(contentsOf: url), uniformTypeIdentifier: "org.openxmlformats.wordprocessingml.document")
        attachment.name = "synthetic-export.docx"; attachment.lifetime = .keepAlways; add(attachment)
        let imported = try XCTUnwrap(OfficeFiles.read(url, originalName: "test.docx").first)
        XCTAssertEqual(imported.text.trimmingCharacters(in: .newlines), rich.string)
        let decoded = DocumentContent.attributed(text: imported.text, rtf: imported.rtf)
        let font = try XCTUnwrap(decoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        // Safe replacement of an existing export.
        try OfficeFiles.writeDOCX(file, to: url)
        XCTAssertNoThrow(try OfficeFiles.read(url, originalName: "test.docx"))
    }
    func testXLSXRoundTripMultipleSheetsAndFormulas() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files: [WorkspaceFile] = [.init(name: "Blatt/1", kind: .table, rows: [["Fach", "Punkte"], ["Mathe & Sprache", "12"], ["Summe", "=SUM(B2:B2)"]]), .init(name: "Blatt 2", kind: .table, rows: [["Text", "0012"]])]
        let url = root.appendingPathComponent("test.xlsx")
        try Data("previous export".utf8).write(to: url)
        try OfficeFiles.writeXLSX(files, to: url)
        let attachment = XCTAttachment(data: try Data(contentsOf: url), uniformTypeIdentifier: "org.openxmlformats.spreadsheetml.sheet")
        attachment.name = "synthetic-export.xlsx"; attachment.lifetime = .keepAlways; add(attachment)
        let imported = try OfficeFiles.read(url, originalName: "test.xlsx")
        XCTAssertEqual(imported.count, 2)
        XCTAssertEqual(imported[0].rows, files[0].rows)
        XCTAssertEqual(imported[1].rows, files[1].rows)
        XCTAssertEqual(imported[0].rows[2][1], "=SUM(B2:B2)")
        XCTAssertEqual(SpreadsheetFormula.displayValue(atRow: 2, column: 1, in: imported[0].rows), "12")
    }
    func testCSVQuotedDelimitersNewlinesAndUnclosedQuote() throws {
        XCTAssertEqual(try OfficeFiles.delimited("A,B\r\n\"a,b\",\"line1\nline2\"\r\n", separator: ","), [["A", "B"], ["a,b", "line1\nline2"]])
        XCTAssertThrowsError(try OfficeFiles.delimited("\"offen", separator: ","))
    }
    func testExportFileWriterWritesAndReplacesSelectedOutput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("bericht.txt")
        try ExportFileWriter.write(Data("erste Fassung".utf8), to: output)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "erste Fassung")
        try ExportFileWriter.write(Data("zweite Fassung".utf8), to: output)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "zweite Fassung")
    }
    @MainActor
    func testOfflineModeDefaultsToBlockingDownloads() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(rootURL: root)
        XCTAssertTrue(store.settings.offlineMode)
        XCTAssertFalse(store.modelLibrary.networkAllowed)
        store.modelLibrary.startDownload(CatalogModel.all.first { $0.nativeMLX }!)
        XCTAssertNil(store.modelLibrary.downloadingID)
        XCTAssertTrue(store.modelLibrary.errorMessage?.contains("Offline") == true)
    }
    @MainActor
    func testImportCopiesOriginalAndPersistsExtractedFileInProject() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("synthetic.txt")
        try "Prüfkennung: Buche".write(to: source, atomically: true, encoding: .utf8)
        let store = WorkspaceStore(rootURL: root.appendingPathComponent("store"))
        let project = store.createProject(title: "Import", kind: .document, template: nil)
        let ids = try await store.importFiles([source], projectID: project.id)
        XCTAssertEqual(ids.count, 1)
        let saved = try XCTUnwrap(store.projects.first?.files?.first)
        XCTAssertEqual(saved.text, "Prüfkennung: Buche")
        let original = try XCTUnwrap(store.originalFileURL(saved))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertNotEqual(original, source)
    }
    func testSummaryCoverageReportsOmissionsAndPreservesDocumentOrder() {
        let text = (0..<12).map { "Abschnitt \($0): " + String(repeating: "Notiz ", count: 150) }.joined(separator: "\n")
        let project = WorkspaceProject(title: "Fiktive Notizen", kind: .document, documentText: text)
        let sources = ProjectKnowledge.sources(project: project, question: "Bitte zusammenfassen", includeProject: true, attachments: [])
        let coverage = ProjectKnowledge.coverage(project: project, includeProject: true, attachments: [], sources: sources)
        XCTAssertTrue(coverage.isIncomplete)
        XCTAssertEqual(coverage.incompleteFiles, [project.primaryName])
        XCTAssertEqual(sources.first?.id, "\(project.id.uuidString)-0")
        XCTAssertEqual(sources.dropFirst().first?.id, "\(project.id.uuidString)-1")

        let short = WorkspaceProject(title: "Kurz", kind: .document, documentText: "Eine vollständige Notiz.")
        let complete = ProjectKnowledge.sources(project: short, question: "Zusammenfassen", includeProject: true, attachments: [])
        XCTAssertFalse(ProjectKnowledge.coverage(project: short, includeProject: true, attachments: [], sources: complete).isIncomplete)
    }

    func testUnreadableAttachedReferenceIsFlagged() {
        var project = WorkspaceProject(title: "Import", kind: .document)
        let image = WorkspaceFile(name: "Scan ohne Text", kind: .reference, text: "")
        project.files = [image]
        let selected: Set<UUID> = [image.id]
        let coverage = ProjectKnowledge.coverage(project: project, includeProject: false, attachments: selected, sources: [])
        XCTAssertEqual(coverage.unreadableFiles, ["Scan ohne Text"])
    }
}
