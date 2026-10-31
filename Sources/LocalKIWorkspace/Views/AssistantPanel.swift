import AppKit
import SwiftUI

struct AssistantPanel: View {
    @Binding var project: WorkspaceProject
    @ObservedObject var store: WorkspaceStore
    var activeFileID: UUID? = nil
    @EnvironmentObject private var library: ModelLibrary
    @State private var question = ""
    @State private var messages: [WorkspaceMessage] = []
    @State private var errorMessage: String?
    @State private var isGenerating = false
    @State private var generationTask: Task<Void, Never>?
    @State private var showingModels = false
    @State private var includeDocument = true
    @State private var attachments: Set<UUID> = []
    @State private var showingImport = false
    @State private var importing = false
    @State private var memoryDraft: String?
    @State private var templateDraft: WorkspaceTemplate?
    @State private var exactContextTokens: Int?

    @State private var editingMessageID: UUID?
    private let engine = LoopbackOpenAIEngine()

    private var modelTitle: String {
        if store.settings.runtime == .mlx { return CatalogModel.model(id: store.settings.selectedMLXModelID)?.title ?? "Modell auswählen" }
        return store.settings.localModelName
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chat").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    messages = []; errorMessage = nil; persist()
                } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.plain).disabled(isGenerating).help("Neue Unterhaltung").accessibilityLabel("Neue Unterhaltung")
            }.padding(.horizontal, 18).frame(height: 42)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if messages.isEmpty {
                            VStack(alignment: .leading, spacing: 13) {
                                Text("Wobei soll ich helfen?").font(.system(size: 18, weight: .medium))
                                Text("Fragen stellen oder den aktuellen Inhalt überarbeiten.").font(.system(size: 12)).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 8) {
                                    suggestion("Text überarbeiten", prompt: "Überarbeite Rechtschreibung und Satzbau. Behalte alle Fakten unverändert.")
                                    suggestion("Offene Angaben finden", prompt: "Welche Angaben fehlen im aktuellen Inhalt? Ergänze keine Antworten.")
                                }.padding(.top, 8)
                            }.padding(.top, 26)
                        }
                        ForEach(messages) { message in
                            messageView(message)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }.padding(18)
                }
                .onChange(of: messages.last?.text) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: messages.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
            if let errorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.circle")
                    Text(errorMessage).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button { self.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 12)
            }
            composer
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear { messages = project.chatMessages ?? [] }
        .onChange(of: question) { _, _ in exactContextTokens = nil }
        .onChange(of: includeDocument) { _, _ in exactContextTokens = nil }
        .onChange(of: attachments) { _, _ in exactContextTokens = nil }
        .onChange(of: messages.count) { _, _ in exactContextTokens = nil }
        .onChange(of: store.settings.selectedMLXModelID) { _, _ in exactContextTokens = nil }
        .onDisappear { generationTask?.cancel() }
        .sheet(isPresented: $showingModels) { WorkspaceSettingsView(store: store) }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: WorkspaceImportTypes.all, allowsMultipleSelection: true) { result in
            Task {
                importing = true; defer { importing = false }
                do { let ids = try await store.importFiles(result.get(), projectID: project.id); attachments.formUnion(ids) }
                catch { errorMessage = error.localizedDescription }
            }
        }
        .sheet(isPresented: Binding(get: { memoryDraft != nil }, set: { if !$0 { memoryDraft = nil } })) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Als Projektnotiz merken").font(.title2)
                Text("Prüfe die Notiz. Sie wird bei künftigen Fragen berücksichtigt.").foregroundStyle(.secondary)
                TextEditor(text: Binding(get: { memoryDraft ?? "" }, set: { memoryDraft = String($0.prefix(1_000)) }))
                HStack {
                    Button("Abbrechen") { memoryDraft = nil }; Spacer()
                    Button("Merken") {
                        let text = memoryDraft?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if !text.isEmpty { project.memory = (project.memory ?? []) + [.init(text: text)] }
                        memoryDraft = nil
                    }.buttonStyle(.borderedProminent).disabled((project.memory?.count ?? 0) >= 20 || (memoryDraft ?? "").isEmpty)
                }
            }.padding(24).frame(width: 540, height: 360)
        }
        .sheet(isPresented: Binding(get: { editingMessageID != nil }, set: { if !$0 { editingMessageID = nil } })) {
            if let id = editingMessageID, let index = messages.firstIndex(where: { $0.id == id }) {
                ReplyEditor(text: Binding(get: { messages[index].text }, set: { messages[index].text = $0; persist() }))
            }
        }
        .sheet(item: $templateDraft) { template in
            SaveTemplateSheet(template: template) { saved in
                store.saveTemplates(store.templates + [saved])
                templateDraft = nil
            }
        }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $includeDocument) {
                Label("Projektdateien durchsuchen", systemImage: "doc.text.magnifyingglass")
            }.toggleStyle(.checkbox).font(.system(size: 11)).disabled(isGenerating)
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(project.allFiles.filter { attachments.contains($0.id) }) { file in
                            Button { attachments.remove(file.id) } label: { Label(file.name, systemImage: "xmark.circle") }.font(.caption).buttonStyle(.bordered)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if question.isEmpty { Text("Nachricht schreiben …").foregroundStyle(.tertiary).font(.system(size: 13)).padding(.top, 5).allowsHitTesting(false) }
                    ChatInput(text: $question, canSend: !isGenerating && !importing && !library.isBusy, onSend: send).frame(height: 64)
                }
                HStack(spacing: 8) {
                    Menu {
                        Button("Dateien hinzufügen …") { showingImport = true }
                        Divider()
                        ForEach(project.allFiles) { file in
                            Button { if attachments.contains(file.id) { attachments.remove(file.id) } else { attachments.insert(file.id) } } label: {
                                Label(file.name, systemImage: attachments.contains(file.id) ? "checkmark" : file.kind.symbol)
                            }
                        }
                    } label: { Image(systemName: "paperclip") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Dateien an Chat anhängen").disabled(isGenerating || importing)
                    if importing { ProgressView().controlSize(.small) }
                    if store.settings.runtime == .mlx {
                        ContextUsageIndicator(tokens: exactContextTokens ?? estimatedContextTokens,
                                              isEstimated: exactContextTokens == nil)
                    } else {
                        Image(systemName: "circle.dashed")
                            .font(.system(size: 13)).foregroundStyle(.tertiary)
                            .help("Das Kontextlimit dieses lokalen Servers wird nicht gemeldet.")
                            .accessibilityLabel("Kontextauslastung nicht verfügbar")
                    }
                    Menu {
                        ForEach(library.installedCatalog) { model in
                            Button(model.title) {
                                store.settings.runtime = .mlx; store.settings.selectedMLXModelID = model.id; store.saveSettings()
                            }
                        }
                        Divider()
                        Button("Modelle verwalten …") { showingModels = true }
                    } label: {
                        HStack(spacing: 4) { Text(modelTitle).lineLimit(1); Image(systemName: "chevron.down").font(.system(size: 8)) }
                    }.menuStyle(.borderlessButton).disabled(isGenerating).font(.system(size: 10)).foregroundStyle(.secondary)
                        .accessibilityLabel("Chat-Modell")
                    Spacer(minLength: 0)
                    if isGenerating {
                        Button { generationTask?.cancel() } label: { Image(systemName: "stop.fill").frame(width: 24, height: 24) }
                            .help("Antwort abbrechen").accessibilityLabel("Antwort abbrechen")
                    } else {
                        Button { send() } label: { Image(systemName: "arrow.up").font(.system(size: 12, weight: .semibold)).frame(width: 24, height: 24) }
                            .keyboardShortcut(.return, modifiers: .command).help("Enter senden · Umschalt Enter neue Zeile").accessibilityLabel("Nachricht senden")
                            .disabled(importing || library.isBusy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }.buttonStyle(.borderless)
            }
            .padding(12).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.13)))
            HStack {
                Text(store.settings.runtime == .mlx ? "Auf diesem Mac" : "Lokaler Server")
                Spacer()
                Text("Enter ↵ · neue Zeile ⇧↵").help("Das Modell kann Fehler machen. Inhalte werden nur auf Wunsch eingefügt.")
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
            if tableContextIncluded {
                Text("Der Chat kann Tabellenwerte vorschlagen, aber noch nicht selbst in Zellen ändern.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(14)
    }
    private func suggestion(_ title: String, prompt: String) -> some View {
        Button { question = prompt } label: {
            HStack { Text(title); Spacer(); Image(systemName: "arrow.up.left").font(.system(size: 9)) }
                .font(.system(size: 12)).padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }
    @ViewBuilder private func messageView(_ message: WorkspaceMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 20)
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.text).font(.system(size: 13)).textSelection(.enabled)
                    if let ids = message.attachmentIDs, !ids.isEmpty {
                        Text(project.allFiles.filter { ids.contains($0.id) }.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(12).background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if message.text.isEmpty && isGenerating { ProgressView().controlSize(.small).accessibilityLabel("Antwort wird vorbereitet") }
                else if !message.text.isEmpty { Text(message.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                if message.contextTrimmed == true {
                    Label("Der Modellkontext wurde für diese Anfrage begrenzt. Ältere Chatbeiträge oder Quellenauszüge können fehlen; der vollständige Chat und die Projektdateien bleiben gespeichert.", systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if !isGenerating {
                    if message.status == .incomplete {
                        Text("Unvollständig").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if !message.text.isEmpty {
                        HStack(spacing: 12) {
                            Button("Kopieren") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) }
                            Button("Bearbeiten") { editingMessageID = message.id }
                            Button("Merken") { memoryDraft = String(message.text.prefix(1_000)) }
                            Button("Als Vorlage speichern") { prepareTemplate(from: message) }
                                .disabled(message.status != .complete)
                                .help("Antwort als lokale, wiederverwendbare Vorlage speichern")
                            if project.allFiles.first(where: { $0.id == (activeFileID ?? project.id) })?.kind == .document {
                                Button("Einfügen") {
                                    let id = activeFileID ?? project.id
                                    var edited = project.content(for: id)
                                    DocumentContent.append("\n\n" + message.text, to: &edited)
                                    project.updateContent(edited, fileID: id)
                                }
                                    .disabled(message.status != .complete).help("Am Dokumentende einfügen")
                            }
                        }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                if let sources = message.sources, !sources.isEmpty {
                    DisclosureGroup("\(sources.count) bereitgestellte Quellenauszüge") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("[\(index + 1)] \(source.title)").font(.caption.bold())
                                    Text(source.excerpt).font(.caption).textSelection(.enabled)
                                }
                            }
                        }.padding(.top, 8)
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func persist() { project.chatMessages = messages }
    private var estimatedContextTokens: Int {
        let selected = attachments.intersection(Set(project.allFiles.map(\.id)))
        let sources = ProjectKnowledge.sources(project: project, question: question, includeProject: includeDocument, attachments: selected)
        let instructions = chatInstructions(sources: sources, request: question, includeTableCaution: tableContextIncluded)
        let history = messages.filter { $0.status == .complete }.suffix(6).map { String($0.text.prefix(1_500)) }
        let characters = instructions.unicodeScalars.count + history.reduce(0) { $0 + $1.unicodeScalars.count } + question.unicodeScalars.count
        return Int((Double(characters) / 3.6).rounded(.up))
    }
    private var tableContextIncluded: Bool {
        project.allFiles.contains { $0.kind == .table && (includeDocument || attachments.contains($0.id)) }
    }
    private func send() {
        guard !isGenerating, !library.isBusy, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        exactContextTokens = nil
        generationTask = Task { await generate() }
    }
    @MainActor private func generate() async {
        let clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let completeHistory = messages.filter { $0.status == .complete }
        let recentHistory = completeHistory.suffix(6)
        let historyTrimmed = completeHistory.count > recentHistory.count || recentHistory.contains { $0.text.count > 1_500 }
        let history = recentHistory.map { message in
            var shortened = message; shortened.text = String(message.text.prefix(1_500)); return shortened
        }
        let selected = attachments.intersection(Set(project.allFiles.map(\.id)))
        let hasTableContext = project.allFiles.contains { $0.kind == .table && (includeDocument || selected.contains($0.id)) }
        let sources = ProjectKnowledge.sources(project: project, question: clean, includeProject: includeDocument, attachments: selected)
        let instructions = chatInstructions(sources: sources, request: clean, includeTableCaution: hasTableContext)
        messages.append(.init(role: .user, text: clean, attachmentIDs: Array(selected)))
        let response = WorkspaceMessage(role: .assistant, text: "", status: .incomplete, sources: sources, contextTrimmed: historyTrimmed ? true : nil)
        messages.append(response); persist()
        question = ""; attachments = []; errorMessage = nil; isGenerating = true
        defer { isGenerating = false; generationTask = nil; persist() }
        do {
            let result: String
            if store.settings.runtime == .mlx {
                do {
                    result = try await generateLocally(instructions: instructions, userText: clean, history: history, responseID: response.id)
                } catch {
                    guard error.localizedDescription.contains("maximal 6.000"),
                          let index = messages.firstIndex(where: { $0.id == response.id }), messages[index].text.isEmpty else { throw error }
                    // Only shrink the request sent to the model. The persisted chat and project files remain intact.
                    let shorterHistory = Array(history.suffix(2))
                    let shorterSources = ProjectKnowledge.sources(project: project, question: clean, includeProject: includeDocument, attachments: selected, budget: 3_000)
                    let shorterInstructions = chatInstructions(sources: shorterSources, request: clean, includeTableCaution: hasTableContext)
                    messages[index].sources = shorterSources
                    messages[index].contextTrimmed = true
                    result = try await generateLocally(instructions: shorterInstructions, userText: clean, history: shorterHistory, responseID: response.id)
                }
            } else {
                guard !store.settings.offlineMode else { throw ModelLibraryError.message("Offline-Modus aktiv. Verwende ein installiertes MLX-Modell direkt in der App.") }
                result = try await engine.generate(configuration: .init(endpoint: store.settings.localModelEndpoint, model: store.settings.localModelName), systemPrompt: instructions, userText: clean, history: history)
            }
            try Task.checkCancellation()
            if let index = messages.firstIndex(where: { $0.id == response.id }) { messages[index].text = result; messages[index].status = .complete }
        } catch { errorMessage = Task.isCancelled ? "Antwort abgebrochen." : error.localizedDescription }
    }

    @MainActor private func generateLocally(instructions: String, userText: String, history: [WorkspaceMessage], responseID: UUID) async throws -> String {
        try await library.generate(modelID: store.settings.selectedMLXModelID, systemPrompt: instructions, userText: userText, history: history, onContextTokens: { count in
            exactContextTokens = count
        }) { chunk in
            if let index = messages.firstIndex(where: { $0.id == responseID }) { messages[index].text += chunk }
        }
    }
    private func chatInstructions(sources: [WorkspaceSource], request: String, includeTableCaution: Bool) -> String {
        var instructions = ProjectKnowledge.instructions(project: project, sources: sources)
        if isTemplateRequest(request) {
            let examples = store.templates.prefix(6).map { template in
                let body = String(template.body.prefix(1_400))
                let prompt = String(template.systemPrompt.prefix(500))
                return """
                Vorlage: \(template.name) · \(template.kind.title)
                Gerüst:
                \(body)
                Chat-Anweisungen:
                \(prompt)
                """
            }.joined(separator: "\n\n")
            instructions += """


            <einstellungen_vorlagen>
            Die nutzende Person bittet um einen Vorlagenentwurf. Verwende die gespeicherten Vorlagen als Beispiele für Struktur und Format. Erstelle ein passendes Gerüst mit neutralen Platzhaltern; übernimm keine ausgefüllten Beispielwerte und erfinde keine Projekt- oder Personendaten. Bei einer Tabellenvorlage gib Spalten und Zeilen tabulatorgetrennt aus, ohne Codeblock.
            \(examples)
            </einstellungen_vorlagen>
            """
        }
        if includeTableCaution {
            instructions += "\n\nDu kannst Tabellenzellen in dieser App nicht bearbeiten. Behaupte niemals, Zeilen, Spalten oder Zellwerte verändert zu haben. Kennzeichne Tabelleninhalte als Vorschläge."
        }
        return instructions
    }
    private func isTemplateRequest(_ request: String) -> Bool {
        let normalized = request.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        return ["vorlage", "muster", "template", "schema"].contains { normalized.localizedCaseInsensitiveContains($0) }
    }
    private func prepareTemplate(from message: WorkspaceMessage) {
        let fileKind = project.allFiles.first(where: { $0.id == (activeFileID ?? project.id) })?.kind
        let kind: WorkspaceKind = fileKind == .table ? .table : .document
        let firstLine = message.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let suggestedName = firstLine
            .trimmingCharacters(in: CharacterSet(charactersIn: "#* \t"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = suggestedName.isEmpty || suggestedName.count > 72
            ? (kind == .document ? "Neue Dokumentvorlage" : "Neue Tabellenvorlage")
            : suggestedName
        templateDraft = WorkspaceTemplate(name: name, kind: kind, body: message.text, systemPrompt: project.systemPrompt)
    }
}

private struct SaveTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: WorkspaceKind
    @State private var bodyText: String
    @State private var systemPrompt: String
    let onSave: (WorkspaceTemplate) -> Void

    init(template: WorkspaceTemplate, onSave: @escaping (WorkspaceTemplate) -> Void) {
        _name = State(initialValue: template.name)
        _kind = State(initialValue: template.kind)
        _bodyText = State(initialValue: template.body)
        _systemPrompt = State(initialValue: template.systemPrompt)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Vorlage aus Chatantwort speichern").font(.system(size: 19, weight: .semibold))
                Text("Prüfe Gerüst und Anweisungen. Die Vorlage wird lokal gespeichert und kann später weiter bearbeitet werden.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            TextField("Name der Vorlage", text: $name).textFieldStyle(.roundedBorder)
            Picker("Vorlagentyp", selection: $kind) {
                ForEach(WorkspaceKind.allCases) { type in Text(type.title).tag(type) }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 6) {
                Text(kind == .document ? "Dokumentgerüst" : "Tabellengerüst")
                    .font(.system(size: 12, weight: .semibold))
                TextEditor(text: $bodyText).font(.system(size: 12, design: .monospaced))
                    .padding(8).background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12)))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Chat-Anweisungen für neue Projekte").font(.system(size: 12, weight: .semibold))
                TextEditor(text: $systemPrompt).font(.system(size: 12))
                    .padding(8).background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12)))
                    .frame(height: 100)
            }
            HStack {
                Button("Abbrechen", role: .cancel) { dismiss() }
                Spacer()
                Button("Vorlage speichern") {
                    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanName.isEmpty else { return }
                    onSave(WorkspaceTemplate(name: cleanName, kind: kind, body: bodyText, systemPrompt: systemPrompt))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 600, height: 650)
    }
}

private struct ContextUsageIndicator: View {
    let tokens: Int
    let isEstimated: Bool
    private var limit: Int { MLXRuntime.maxInputTokens }
    private var fraction: Double { min(1, max(0, Double(tokens) / Double(limit))) }
    private var color: Color { fraction >= 0.9 ? .orange : .accentColor }
    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.14), lineWidth: 2.5)
            Circle().trim(from: 0, to: fraction).stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(isEstimated ? "≈" : "")\(Int((fraction * 100).rounded()))")
                .font(.system(size: 7, weight: .semibold, design: .rounded))
        }
        .frame(width: 22, height: 22)
        .help("\(isEstimated ? "Grobe Vorschau aus der Zeichenanzahl" : "Mit dem aktiven Modell und seiner Chatvorlage gezählt"): \(tokens) von \(limit) Eingabetokens (\(Int((fraction * 100).rounded())) %). Das ist das App-Limit, nicht zwingend das gesamte Modellfenster. Es gibt keine automatische Zusammenfassung oder Änderung von Projektdateien. Bei Überschreitung wird der für diese Anfrage verwendete Chatverlauf oder die Quellenauswahl sichtbar begrenzt; der vollständige Chat und die Originaldateien bleiben gespeichert.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kontext \(isEstimated ? "grob geschätzt" : "mit aktivem Modell gezählt") \(Int((fraction * 100).rounded())) Prozent vom App-Limit von \(limit) Eingabetokens")
    }
}

private struct ReplyEditor: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 16) {
            HStack { Text("Antwort bearbeiten").font(.headline); Spacer(); Button("Fertig") { dismiss() } }
            TextEditor(text: $text).font(.system(size: 14)).padding(8).border(.quaternary)
        }.padding(20).frame(width: 540, height: 440)
    }
}
