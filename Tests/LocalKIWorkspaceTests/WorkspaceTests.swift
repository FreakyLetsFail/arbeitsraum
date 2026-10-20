import XCTest
@testable import Lokal_KI_Workspace

final class WorkspaceTests: XCTestCase {
    func testLocalModelEndpointRejectsNonLoopbackHosts() {
        XCTAssertTrue(LoopbackOpenAIEngine.isAllowedEndpoint("http://127.0.0.1:11434/v1"))
        XCTAssertTrue(LoopbackOpenAIEngine.isAllowedEndpoint("http://localhost:8000/v1"))
        XCTAssertFalse(LoopbackOpenAIEngine.isAllowedEndpoint("https://example.com/v1"))
        XCTAssertFalse(LoopbackOpenAIEngine.isAllowedEndpoint("http://192.168.1.10:8000/v1"))
        XCTAssertFalse(LoopbackOpenAIEngine.isAllowedEndpoint("http://example.com/v1"))
    }

    @MainActor
    func testProjectsPersistLocallyAndReload() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let store = WorkspaceStore(rootURL: temporaryRoot)
        let project = store.createProject(title: "Testbericht", kind: .document, template: WorkspaceDefaults.templates.first)
        var edited = project
        edited.documentText += "\nNotiz"
        store.updateProject(edited)

        let reloadedStore = WorkspaceStore(rootURL: temporaryRoot)
        XCTAssertEqual(reloadedStore.projects.first?.title, "Testbericht")
        XCTAssertTrue(reloadedStore.projects.first?.documentText.contains("Notiz") == true)
        XCTAssertEqual(reloadedStore.projects.first?.systemPrompt, WorkspaceDefaults.systemPrompt)
    }

    func testNewTableStartsWithEditableHeadersAndNoSampleRows() {
        let project = WorkspaceProject(title: "Übersicht", kind: .table, tableRows: [["Datum", "Bereich", "Notiz", "Status"]])
        XCTAssertEqual(project.tableRows.count, 1)
        XCTAssertEqual(project.tableRows[0].count, 4)
    }
}
