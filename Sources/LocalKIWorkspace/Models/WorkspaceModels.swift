import Foundation

enum WorkspaceKind: String, Codable, CaseIterable, Identifiable {
    case document
    case table

    var id: String { rawValue }
    var title: String { self == .document ? "Dokument" : "Tabelle" }
    var symbol: String { self == .document ? "doc.text" : "tablecells" }
}

struct AudioAsset: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var fileName: String
    var relativePath: String
    var addedAt: Date = Date()
}

struct WorkspaceProject: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var kind: WorkspaceKind
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var documentText: String = ""
    var documentRTF: Data?
    var chatMessages: [WorkspaceMessage]?
    var tableRows: [[String]] = []
    var systemPrompt: String = WorkspaceDefaults.systemPrompt
    var audioAssets: [AudioAsset] = []
    var files: [WorkspaceFile]?
    var primaryFileName: String?
    var memory: [ProjectMemoryItem]?

    var detail: String {
        kind == .document ? "Dokument" : "\(max(tableRows.count - 1, 0)) Zeilen"
    }
}

struct WorkspaceMessage: Codable, Identifiable, Hashable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    enum Status: String, Codable, Sendable { case complete, incomplete }
    var id = UUID()
    var role: Role
    var text: String
    var status: Status = .complete
    var createdAt = Date()
    var attachmentIDs: [UUID]?
    var sources: [WorkspaceSource]?
}

struct WorkspaceTemplate: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var kind: WorkspaceKind
    var body: String
    var systemPrompt: String
}

struct WorkspaceSettings: Codable {
    var localModelEndpoint: String = "http://127.0.0.1:11434/v1"
    var localModelName: String = "openbmb/minicpm-v4.7:35b-a3b"
    var runtime: InferenceRuntime = .mlx
    var offlineMode: Bool = true
    var selectedMLXModelID: String = "mlx-community/Qwen3-1.7B-4bit"

    init() { }

    private enum CodingKeys: String, CodingKey { case localModelEndpoint, localModelName, runtime, selectedMLXModelID, offlineMode }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        localModelEndpoint = try values.decodeIfPresent(String.self, forKey: .localModelEndpoint) ?? "http://127.0.0.1:11434/v1"
        localModelName = try values.decodeIfPresent(String.self, forKey: .localModelName) ?? "openbmb/minicpm-v4.7:35b-a3b"
        offlineMode = try values.decodeIfPresent(Bool.self, forKey: .offlineMode) ?? true
        // Preserve an existing installation's server choice when migrating legacy settings.
        runtime = try values.decodeIfPresent(InferenceRuntime.self, forKey: .runtime) ?? .localServer
        selectedMLXModelID = try values.decodeIfPresent(String.self, forKey: .selectedMLXModelID) ?? "mlx-community/Qwen3-1.7B-4bit"
    }
}

enum WorkspaceDefaults {
    static let systemPrompt = """
    Du unterstützt beim Schreiben, Lernen und Arbeiten mit Unterlagen. Beantworte Fragen zu Projektunterlagen ausschließlich anhand der bereitgestellten Quellen und nenne fehlende Angaben ausdrücklich. Erfinde keine Projektfakten, Diagnosen, Zitate oder Transkriptinhalte. Allgemeine Fragen und kreative Aufgaben darfst du beantworten; kennzeichne neue Textvorschläge als solche. Die fachliche Prüfung bleibt bei der nutzenden Person.
    """

    static let templates: [WorkspaceTemplate] = [
        WorkspaceTemplate(
            name: "Freier Bericht",
            kind: .document,
            body: "Bericht\n\nAnlass\n[Manuelle Eingabe]\n\nBeobachtungen\n[Manuelle Eingabe]\n\nZusammenfassung\n[Manuelle Eingabe]\n\nOffene Punkte\n[Manuelle Eingabe]\n",
            systemPrompt: systemPrompt
        ),
        WorkspaceTemplate(
            name: "Verlaufsnotiz",
            kind: .document,
            body: "Verlaufsnotiz\n\nDatum: [Manuelle Eingabe]\nThema: [Manuelle Eingabe]\n\nInhalt\n[Manuelle Eingabe]\n\nVereinbarungen / nächste Schritte\n[Manuelle Eingabe]\n",
            systemPrompt: systemPrompt
        ),
        WorkspaceTemplate(
            name: "Erstgespräch",
            kind: .document,
            body: "Erstgespräch\n\nAnliegen\n[Manuelle Eingabe]\n\nRahmen und Kontext\n[Manuelle Eingabe]\n\nZiele und nächste Schritte\n[Manuelle Eingabe]\n",
            systemPrompt: systemPrompt
        ),
        WorkspaceTemplate(
            name: "Verlaufsübersicht",
            kind: .table,
            body: "",
            systemPrompt: systemPrompt
        )
    ]
}


enum WorkspaceFileKind: String, Codable, Sendable {
    case document, table, reference
    var symbol: String { self == .document ? "doc.text" : self == .table ? "tablecells" : "paperclip" }
}

struct WorkspaceFile: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var kind: WorkspaceFileKind
    var text: String = ""
    var rtf: Data?
    var rows: [[String]] = []
    var relativePath: String?
    var importNote: String?
    var addedAt = Date()
}

struct ProjectMemoryItem: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var text: String
    var createdAt = Date()
}

struct WorkspaceSource: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var fileID: UUID
    var title: String
    var excerpt: String
}

extension WorkspaceProject {
    var primaryName: String { primaryFileName ?? (kind == .document ? "Dokument" : "Tabellenblatt 1") }
    var allFiles: [WorkspaceFile] {
        [WorkspaceFile(id: id, name: primaryName, kind: kind == .document ? .document : .table,
                       text: documentText, rtf: documentRTF, rows: tableRows)] + (files ?? [])
    }
    func content(for fileID: UUID) -> WorkspaceProject {
        guard fileID != id, let file = files?.first(where: { $0.id == fileID }) else {
            var primary = self; primary.title = primaryName; return primary
        }
        var copy = self
        copy.title = file.name; copy.kind = file.kind == .table ? .table : .document
        copy.documentText = file.text; copy.documentRTF = file.rtf; copy.tableRows = file.rows
        return copy
    }
    mutating func updateContent(_ edited: WorkspaceProject, fileID: UUID) {
        if fileID == id {
            primaryFileName = edited.title; documentText = edited.documentText
            documentRTF = edited.documentRTF; tableRows = edited.tableRows
        } else if let index = files?.firstIndex(where: { $0.id == fileID }) {
            files?[index].name = edited.title; files?[index].text = edited.documentText
            files?[index].rtf = edited.documentRTF; files?[index].rows = edited.tableRows
        }
    }
}
