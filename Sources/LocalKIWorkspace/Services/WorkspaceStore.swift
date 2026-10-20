import Foundation
import Combine

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var projects: [WorkspaceProject] = []
    @Published private(set) var templates: [WorkspaceTemplate] = []
    @Published var settings: WorkspaceSettings
    @Published private(set) var persistenceError: String?

    let rootURL: URL
    let modelLibrary: ModelLibrary
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(rootURL: URL? = nil) {
        let base = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "LokalKIWorkspace", directoryHint: .isDirectory)
        self.rootURL = base
        self.modelLibrary = ModelLibrary(rootURL: base.appending(path: "Models", directoryHint: .isDirectory))
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.settings = WorkspaceSettings()
        prepareFolders()
        loadProjects()
        loadTemplates()
        loadSettings()
        modelLibrary.networkAllowed = !settings.offlineMode
    }

    var projectsURL: URL { rootURL.appending(path: "Projects", directoryHint: .isDirectory) }
    var filesURL: URL { rootURL.appending(path: "Files", directoryHint: .isDirectory) }
    var audioURL: URL { rootURL.appending(path: "Audio", directoryHint: .isDirectory) }

    func createProject(title: String, kind: WorkspaceKind, template: WorkspaceTemplate?) -> WorkspaceProject {
        let templateRows = template.flatMap { try? OfficeFiles.delimited($0.body, separator: "\t") }
        let rows = kind == .table ? (templateRows?.isEmpty == false ? templateRows! : [["Datum", "Bereich", "Notiz", "Status"]]) : []
        let project = WorkspaceProject(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unbenannt" : title,
            kind: kind,
            documentText: kind == .document ? (template?.body ?? "") : "",
            tableRows: rows,
            systemPrompt: template?.systemPrompt ?? WorkspaceDefaults.systemPrompt
        )
        projects.insert(project, at: 0)
        persistProject(project)
        return project
    }

    func updateProject(_ project: WorkspaceProject) {
        var updated = project
        updated.modifiedAt = Date()
        if let index = projects.firstIndex(where: { $0.id == updated.id }) {
            projects[index] = updated
        } else {
            projects.insert(updated, at: 0)
        }
        persistProject(updated)
    }

    func deleteProject(_ project: WorkspaceProject) {
        do {
            let file = projectFileURL(project.id)
            try FileManager.default.trashItem(at: file, resultingItemURL: nil)
            let projectAudio = audioURL.appending(path: project.id.uuidString, directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: projectAudio.path) {
                try FileManager.default.trashItem(at: projectAudio, resultingItemURL: nil)
            }
            let projectFiles = filesURL.appending(path: project.id.uuidString, directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: projectFiles.path) { try FileManager.default.trashItem(at: projectFiles, resultingItemURL: nil) }
            projects.removeAll { $0.id == project.id }
            persistenceError = nil
        } catch {
            loadProjects()
            persistenceError = "Projekt konnte nicht in den Papierkorb verschoben werden: \(error.localizedDescription)"
        }
    }

    func saveTemplates(_ newTemplates: [WorkspaceTemplate]) {
        templates = newTemplates
        write(newTemplates, to: rootURL.appending(path: "templates.json"))
    }

    func saveSettings() {
        modelLibrary.networkAllowed = !settings.offlineMode
        if settings.offlineMode { modelLibrary.cancelDownload() }
        write(settings, to: rootURL.appending(path: "settings.json"))
    }

    func clearPersistenceError() {
        persistenceError = nil
    }

    func report(error: String) {
        persistenceError = error
    }

    func addAudioAsset(from sourceURL: URL, to project: WorkspaceProject) throws -> (WorkspaceProject, URL) {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        let directory = audioURL.appending(path: project.id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.isEmpty ? "audio" : sourceURL.pathExtension.lowercased()
        let safeName = "\(UUID().uuidString).\(ext)"
        let destination = directory.appending(path: safeName)
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        var changed = project
        let relativePath = "Audio/\(project.id.uuidString)/\(safeName)"
        changed.audioAssets.insert(AudioAsset(fileName: sourceURL.lastPathComponent, relativePath: relativePath), at: 0)
        updateProject(changed)
        return (changed, destination)
    }

    func registerRecordedAudio(at fileURL: URL, fileName: String, for project: WorkspaceProject) -> WorkspaceProject {
        var changed = project
        changed.audioAssets.insert(
            AudioAsset(fileName: fileName, relativePath: "Audio/\(project.id.uuidString)/\(fileName)"),
            at: 0
        )
        updateProject(changed)
        return changed
    }

    func audioFileURL(for asset: AudioAsset) -> URL {
        rootURL.appending(path: asset.relativePath)
    }

    func importFiles(_ urls: [URL], projectID: UUID) async throws -> [UUID] {
        var importedIDs: [UUID] = []
        for source in urls {
            let accessed = source.startAccessingSecurityScopedResource()
            defer { if accessed { source.stopAccessingSecurityScopedResource() } }
            let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 50_000_000 else { throw OfficeFileError.message("Dateien bis 50 MB sind unterstützt.") }
            let directory = filesURL.appending(path: projectID.uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let name = UUID().uuidString + "." + source.pathExtension.lowercased()
            let destination = directory.appending(path: name)
            try FileManager.default.copyItem(at: source, to: destination)
            do {
                var items = try await Task.detached { try OfficeFiles.read(destination, originalName: source.lastPathComponent) }.value
                guard var project = projects.first(where: { $0.id == projectID }) else { throw OfficeFileError.message("Projekt nicht mehr vorhanden.") }
                for index in items.indices { items[index].relativePath = "Files/\(projectID.uuidString)/\(name)" }
                importedIDs += items.map(\.id)
                project.files = (project.files ?? []) + items
                updateProject(project)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }
        return importedIDs
    }

    func originalFileURL(_ file: WorkspaceFile) -> URL? {
        guard let relative = file.relativePath, ModelDownloader.isSafeRelativePath(relative) else { return nil }
        return rootURL.appending(path: relative)
    }

    private func prepareFolders() {
        do {
            try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.createDirectory(at: audioURL, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootURL.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: projectsURL.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: audioURL.path)
        } catch {
            persistenceError = "Lokaler Speicher konnte nicht vorbereitet werden: \(error.localizedDescription)"
        }
    }

    private func loadProjects() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: projectsURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
            projects = try files.compactMap { try decoder.decode(WorkspaceProject.self, from: Data(contentsOf: $0)) }
                .sorted { $0.modifiedAt > $1.modifiedAt }
        } catch {
            persistenceError = "Projekte konnten nicht geladen werden: \(error.localizedDescription)"
        }
    }

    private func loadTemplates() {
        let url = rootURL.appending(path: "templates.json")
        if let data = try? Data(contentsOf: url), let decoded = try? decoder.decode([WorkspaceTemplate].self, from: data) {
            templates = decoded
        } else {
            templates = WorkspaceDefaults.templates
            write(templates, to: url)
        }
    }

    private func loadSettings() {
        let url = rootURL.appending(path: "settings.json")
        if let data = try? Data(contentsOf: url), let decoded = try? decoder.decode(WorkspaceSettings.self, from: data) {
            settings = decoded
        }
    }

    private func persistProject(_ project: WorkspaceProject) {
        write(project, to: projectFileURL(project.id))
    }

    private func projectFileURL(_ id: UUID) -> URL {
        projectsURL.appending(path: "\(id.uuidString).json")
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            persistenceError = nil
        } catch {
            persistenceError = "Lokal speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
