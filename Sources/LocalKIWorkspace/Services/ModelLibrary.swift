import Combine
import Foundation
import MLXLMCommon

@MainActor
final class ModelLibrary: ObservableObject {
    @Published private(set) var installed: [String: InstalledModel] = [:]
    @Published private(set) var activeModelID: String?
    @Published private(set) var lastInputTokenCount: Int?
    @Published private(set) var isLoading = false
    @Published private(set) var isGenerating = false
    @Published private(set) var downloadingID: String?
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var downloadDetail = ""
    @Published private(set) var status = "Kein Modell im Arbeitsspeicher"
    @Published private(set) var errorMessage: String?
    @Published private(set) var testResult: String?
    @Published private(set) var testResultModelID: String?

    var networkAllowed = false
    let rootURL: URL
    private let runtime = MLXRuntime()
    private var downloadTask: Task<Void, Never>?

    init(rootURL: URL) {
        self.rootURL = rootURL
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch { errorMessage = "Modellspeicher konnte nicht angelegt werden: \(error.localizedDescription)" }
        refresh()
    }

    var isBusy: Bool { isLoading || isGenerating }
    var installedCatalog: [CatalogModel] { CatalogModel.all.filter { installed[$0.id] != nil } }

    func refresh() {
        var found: [String: InstalledModel] = [:]
        for model in CatalogModel.all where model.nativeMLX {
            let path = ModelDownloader.directory(for: model.id, root: rootURL)
            if let installation = ModelDownloader.installation(at: path), installation.id == model.id {
                found[model.id] = installation
            }
        }
        installed = found
    }

    func startDownload(_ model: CatalogModel) {
        guard networkAllowed else { errorMessage = "Offline-Modus aktiv. Downloads können unter Datenschutz freigegeben werden."; return }
        guard downloadingID == nil, installed[model.id] == nil else { return }
        errorMessage = nil
        downloadingID = model.id
        downloadProgress = 0
        downloadDetail = "Modellversion wird geprüft …"
        downloadTask = Task {
            defer { downloadingID = nil; downloadTask = nil }
            do {
                let installation = try await ModelDownloader().download(model, root: rootURL) { [weak library = self] fraction, detail in
                    Task { @MainActor in
                        guard let library, library.downloadingID == model.id else { return }
                        library.downloadProgress = fraction
                        library.downloadDetail = detail
                    }
                }
                installed[model.id] = installation
                downloadProgress = 1
                downloadDetail = "Heruntergeladen und geprüft"
            } catch {
                if Task.isCancelled { downloadDetail = "Download abgebrochen" }
                else { errorMessage = error.localizedDescription }
            }
        }
    }

    func cancelDownload() { downloadTask?.cancel() }
    func clearError() { errorMessage = nil }

    func load(_ model: CatalogModel) async throws {
        guard !isBusy else { throw ModelLibraryError.message("Das Modell wird gerade verwendet. Bitte den laufenden Vorgang beenden.") }
        guard model.nativeMLX else { throw ModelLibraryError.message("Dieses Modell benötigt einen kompatiblen lokalen Server.") }
        guard model.fitsThisMac else { throw ModelLibraryError.message("Für dieses Modell empfiehlt der Katalog mindestens \(model.recommendedRAMGB) GB RAM.") }
        let directory = ModelDownloader.directory(for: model.id, root: rootURL)
        guard ModelDownloader.installation(at: directory) != nil else {
            throw ModelLibraryError.message("Das Modell ist noch nicht vollständig installiert. Bitte unter Einstellungen → Modelle herunterladen.")
        }
        isLoading = true
        activeModelID = nil
        errorMessage = nil
        status = "\(model.title) wird geladen …"
        defer { isLoading = false }
        do {
            try Task.checkCancellation()
            try await runtime.load(directory: directory)
            try Task.checkCancellation()
            activeModelID = model.id
            status = "\(model.title) · bereit · lokal in der App"
        } catch {
            await runtime.unload()
            status = "Kein Modell im Arbeitsspeicher"
            throw error
        }
    }

    func activate(_ model: CatalogModel) async {
        do { try await load(model) }
        catch { errorMessage = error.localizedDescription }
    }

    func unload() async {
        guard !isBusy else { return }
        isLoading = true
        defer { isLoading = false }
        await runtime.unload()
        activeModelID = nil
        status = "Kein Modell im Arbeitsspeicher"
    }

    func remove(_ model: CatalogModel) async {
        guard !isBusy, downloadingID != model.id else { return }
        if activeModelID == model.id { await unload() }
        do {
            try FileManager.default.trashItem(at: ModelDownloader.directory(for: model.id, root: rootURL), resultingItemURL: nil)
            refresh()
        } catch { errorMessage = "Das Modell konnte nicht in den Papierkorb verschoben werden: \(error.localizedDescription)" }
    }

    func generate(modelID: String, systemPrompt: String, userText: String, history: [WorkspaceMessage] = [], onContextTokens: @MainActor (Int) -> Void = { _ in }, onChunk: @MainActor (String) -> Void) async throws -> String {
        guard !isBusy else { throw ModelLibraryError.message("Es läuft bereits eine Modellaktion.") }
        guard let model = CatalogModel.model(id: modelID) else { throw ModelLibraryError.message("Bitte ein Modell aus der Modellbibliothek auswählen.") }
        if activeModelID != modelID { try await load(model) }
        isGenerating = true
        status = "\(model.title) erzeugt eine Antwort …"
        defer {
            isGenerating = false
            status = "\(model.title) · bereit · lokal in der App"
        }
        let stream: AsyncThrowingStream<Generation, Error>
        do {
            stream = try await runtime.response(systemPrompt: systemPrompt, userText: userText, history: history)
        } catch {
            if let count = await runtime.measuredInputTokens() {
                lastInputTokenCount = count
                onContextTokens(count)
            }
            throw error
        }
        if let count = await runtime.measuredInputTokens() {
            lastInputTokenCount = count
            onContextTokens(count)
        }
        var answer = ""
        var completed = false
        for try await event in stream {
            try Task.checkCancellation()
            switch event {
            case .chunk(let text):
                answer += text
                onChunk(text)
            case .info(let info):
                let promptTokens = info.totalPromptTokenCount
                lastInputTokenCount = promptTokens
                onContextTokens(promptTokens)
                switch info.stopReason {
                case .stop: completed = true
                case .length: throw ModelLibraryError.message("Das Ausgabelimit wurde erreicht. Die sichtbare Teilantwort ist unvollständig; bitte eine kürzere Aufgabe stellen.")
                case .cancelled: throw CancellationError()
                }
            case .toolCall, .rejectedToolCall:
                throw ModelLibraryError.message("Das Modell hat einen Werkzeugaufruf statt einer Textantwort erzeugt. Diese Version führt keine Modellwerkzeuge aus.")
            }
        }
        try Task.checkCancellation()
        guard completed else { throw ModelLibraryError.message("Die Modellantwort wurde ohne Abschluss beendet.") }
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LocalModelError.emptyResponse }
        return answer
    }

    func runSelfTest(_ model: CatalogModel) async {
        testResult = nil
        testResultModelID = model.id
        errorMessage = nil
        let start = Date()
        do {
            let output = try await generate(modelID: model.id,
                systemPrompt: "Du antwortest kurz auf Deutsch. Befolge die Aufgabe exakt.",
                userText: "Schreibe nur die zwei Wörter: Lokal bereit", onChunk: { _ in })
            testResult = "Echte lokale Modellantwort nach \(String(format: "%.1f", Date().timeIntervalSince(start))) s: \(output)"
        } catch { errorMessage = error.localizedDescription }
    }
}
