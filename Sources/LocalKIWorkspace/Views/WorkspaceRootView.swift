import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceRootView: View {
    @ObservedObject var store: WorkspaceStore
    @State private var selectedProjectID: UUID?
    @State private var showingNewProject = false
    @State private var showingSettings = false
    @State private var newKind: WorkspaceKind = .document
    @State private var search = ""

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Arbeitsraum").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Button { create(.document) } label: { Image(systemName: "square.and.pencil") }
                        .buttonStyle(.plain).help("Neues Projekt · ⌘N").accessibilityLabel("Neues Projekt")
                        .keyboardShortcut("n", modifiers: .command)
                }.padding(18)
                TextField("Projekte suchen", text: $search).textFieldStyle(.roundedBorder).padding(.horizontal, 12).padding(.bottom, 12)
                Button { selectedProjectID = nil } label: {
                    HStack { Label("Alle Projekte", systemImage: "folder"); Spacer() }
                        .padding(10).contentShape(Rectangle())
                        .background(selectedProjectID == nil ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).padding(.horizontal, 10).accessibilityIdentifier("all-projects")
                List(selection: $selectedProjectID) {
                    Section("Projekte") {
                        ForEach(store.projects.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { project in
                            Label(project.title, systemImage: project.kind.symbol)
                                .lineLimit(1).tag(Optional(project.id))
                                .contextMenu {
                                    Button("In Papierkorb", role: .destructive) {
                                        if selectedProjectID == project.id { selectedProjectID = nil }
                                        store.deleteProject(project)
                                    }
                                }
                        }
                    }
                }.listStyle(.sidebar)
                Divider()
                Button { showingSettings = true } label: {
                    HStack { Image(systemName: "slider.horizontal.3"); Text("Modelle & Einstellungen"); Spacer() }
                        .font(.system(size: 12)).padding(15).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            if let project = store.projects.first(where: { $0.id == selectedProjectID }) {
                WorkspaceEditor(project: binding(for: project), store: store, onCreated: { selectedProjectID = $0 })
                    .id(project.id)
            } else {
                WorkspaceOverview(store: store, onCreate: create, onSelect: { selectedProjectID = $0 })
            }
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet(store: store, onCreate: { selectedProjectID = $0.id }, initialKind: newKind)
        }
        .sheet(isPresented: $showingSettings) { WorkspaceSettingsView(store: store) }
        .alert("Speichern fehlgeschlagen", isPresented: Binding(get: { store.persistenceError != nil }, set: { if !$0 { store.clearPersistenceError() } })) {
            Button("OK", role: .cancel) { store.clearPersistenceError() }
        } message: { Text(store.persistenceError ?? "") }
    }
    private func create(_ kind: WorkspaceKind) { newKind = kind; showingNewProject = true }
    private func binding(for project: WorkspaceProject) -> Binding<WorkspaceProject> {
        Binding(get: { store.projects.first { $0.id == project.id } ?? project }, set: { changed in
            guard store.projects.contains(where: { $0.id == project.id }) else { return }
            store.updateProject(changed)
        })
    }
}

struct WorkspaceOverview: View {
    @ObservedObject var store: WorkspaceStore
    let onCreate: (WorkspaceKind) -> Void
    let onSelect: (UUID) -> Void
    @State private var filter: WorkspaceKind?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Projekte").font(.system(size: 30, weight: .semibold))
                    Text("Dokumente und Tabellen").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Dokument") { onCreate(.document) }
                    Button("Tabelle") { onCreate(.table) }
                } label: { Label("Neu", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize()
            }
            HStack(spacing: 8) {
                filterButton("Alle", value: nil)
                filterButton("Dokumente", value: .document)
                filterButton("Tabellen", value: .table)
                Spacer()
                Text("Auf diesem Mac gespeichert").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            if store.projects.isEmpty {
                ContentUnavailableView {
                    Label("Ein neues Projekt beginnen", systemImage: "doc")
                } description: { Text("Mit einem leeren Dokument oder einer Vorlage starten.") }
                actions: {
                    HStack {
                        Button("Dokument erstellen") { onCreate(.document) }
                        Button("Tabelle erstellen") { onCreate(.table) }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.projects.filter { filter == nil || $0.kind == filter }) { project in
                            Button { onSelect(project.id) } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: project.kind.symbol).font(.system(size: 21, weight: .light)).foregroundStyle(.secondary).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(project.title).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                                        Text("\(project.allFiles.count) Dateien").font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(project.modifiedAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                                }.padding(.vertical, 18).padding(.horizontal, 8).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }
    private func filterButton(_ title: String, value: WorkspaceKind?) -> some View {
        Button { filter = value } label: {
            Text(title).font(.system(size: 12, weight: filter == value ? .medium : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(filter == value ? Color.primary.opacity(0.07) : .clear, in: Capsule())
        }.buttonStyle(.plain).foregroundStyle(filter == value ? .primary : .secondary)
    }
}

struct NewProjectSheet: View {
    @ObservedObject var store: WorkspaceStore
    let onCreate: (WorkspaceProject) -> Void
    var initialKind: WorkspaceKind = .document
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind: WorkspaceKind = .document
    @State private var selectedTemplateID: UUID?

    private var matchingTemplates: [WorkspaceTemplate] { store.templates.filter { $0.kind == kind } }
    private var selectedTemplate: WorkspaceTemplate? { matchingTemplates.first { $0.id == selectedTemplateID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Neues Projekt").font(.system(size: 22, weight: .semibold))
                Text("Wähle einen Arbeitsbereich und optional eine Vorlage.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            TextField("Projektname", text: $title)
                .textFieldStyle(.roundedBorder)
            Picker("Arbeitsbereich", selection: $kind) {
                ForEach(WorkspaceKind.allCases) { value in
                    Label(value.title, systemImage: value.symbol).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: kind) { _, _ in selectedTemplateID = matchingTemplates.first?.id }
            if !matchingTemplates.isEmpty {
                Picker("Vorlage", selection: $selectedTemplateID) {
                    Text("Leer starten").tag(Optional<UUID>.none)
                    ForEach(matchingTemplates) { template in Text(template.name).tag(Optional(template.id)) }
                }
            }
            if let selectedTemplate {
                Text(selectedTemplate.body.isEmpty ? "Tabelle mit bearbeitbaren Spalten wird angelegt." : "Die Vorlage fügt eine bearbeitbare Gliederung ein.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            HStack {
                Button("Abbrechen", role: .cancel) { dismiss() }
                Spacer()
                Button("Erstellen") {
                    let project = store.createProject(title: title, kind: kind, template: selectedTemplate)
                    onCreate(project)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420, height: 330)
        .onAppear { kind = initialKind; selectedTemplateID = matchingTemplates.first?.id }
    }
}


struct WorkspaceEditor: View {
    @Binding var project: WorkspaceProject
    @ObservedObject var store: WorkspaceStore
    let onCreated: (UUID) -> Void
    @State private var showingChat = true
    @State private var showingAudio = false
    @State private var showingPrompt = false
    @State private var showingMemory = false
    @State private var showingImport = false
    @State private var importing = false
    @State private var activeID: UUID?
    @State private var deletingID: UUID?
    private var fileID: UUID { activeID ?? project.id }
    private var activeFile: WorkspaceFile { project.allFiles.first { $0.id == fileID } ?? project.allFiles[0] }
    private var content: Binding<WorkspaceProject> {
        Binding(get: { project.content(for: fileID) }, set: { project.updateContent($0, fileID: fileID) })
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                TextField("Projektname", text: $project.title).font(.system(size: 14, weight: .medium)).textFieldStyle(.plain)
                Spacer(minLength: 6)
                Button { showingAudio = true } label: { Label("Audio", systemImage: "waveform") }
                Button { showingMemory = true } label: { Label("Gedächtnis", systemImage: "bookmark") }
                Menu {
                    if activeFile.kind == .document {
                        Button("Word-Dokument (.docx)") { export("docx") }
                        Button("Rich Text (.rtf)") { export("rtf") }
                        Button("Text (.txt)") { export("txt") }
                    }
                    if activeFile.kind == .table {
                        Button("Excel-Arbeitsmappe – alle Tabellen (.xlsx)") { export("xlsx") }
                        Button("Dieses Blatt (.csv)") { export("csv") }
                    }
                    Divider()
                    Button("Chat-Anweisungen bearbeiten") { showingPrompt = true }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Export und Projekteinstellungen")
                Divider().frame(height: 18)
                Button { showingChat.toggle() } label: { Image(systemName: "sidebar.right") }
                    .help(showingChat ? "Chat ausblenden" : "Chat einblenden")
                    .accessibilityLabel(showingChat ? "Chat ausblenden" : "Chat einblenden")
            }.buttonStyle(.borderless).font(.system(size: 12)).padding(.horizontal, 18).frame(height: 50)
            Divider()
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(project.allFiles) { file in
                            Button { activeID = file.id } label: {
                                Label(file.name, systemImage: file.kind.symbol).lineLimit(1).padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(file.id == fileID ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain).contextMenu {
                                if file.id != project.id { Button("Aus Projekt entfernen", role: .destructive) { deletingID = file.id } }
                            }
                        }
                    }
                }
                if importing { ProgressView().controlSize(.small) }
                Menu {
                    Button("Neues Dokument") { add(.document) }
                    Button("Neues Tabellenblatt") { add(.table) }
                    Divider()
                    Button("Dateien hinzufügen …") { showingImport = true }
                } label: { Image(systemName: "plus") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Datei hinzufügen").disabled(importing)
            }.font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 5)
            Divider()
            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        TextField("Dateiname", text: content.title).textFieldStyle(.plain).font(.system(size: 12, weight: .medium))
                        Spacer()
                        if activeFile.importNote != nil { Image(systemName: "info.circle").help(activeFile.importNote ?? "") }
                    }.padding(.horizontal, 18).frame(height: 30)
                    Divider()
                    Group {
                        if activeFile.kind == .reference { ReferenceFileView(file: activeFile, url: store.originalFileURL(activeFile)) }
                        else if activeFile.kind == .document { DocumentEditor(project: content) }
                        else { SpreadsheetEditor(project: content) }
                    }.id(fileID)
                }.frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                if showingChat {
                    AssistantPanel(project: $project, store: store, activeFileID: fileID)
                        .frame(minWidth: 300, idealWidth: 370, maxWidth: 540, maxHeight: .infinity)
                }
            }
        }
        .sheet(isPresented: $showingAudio) { AudioImportView(project: $project, store: store, onCreated: onCreated, destinationFileID: activeFile.kind == .document ? fileID : nil) }
        .sheet(isPresented: $showingPrompt) { PromptEditorSheet(prompt: $project.systemPrompt, onSave: { store.updateProject(project) }) }
        .sheet(isPresented: $showingMemory) { ProjectMemoryView(project: $project) }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: WorkspaceImportTypes.all, allowsMultipleSelection: true) { result in
            Task {
                importing = true; defer { importing = false }
                do { let ids = try await store.importFiles(result.get(), projectID: project.id); activeID = ids.first }
                catch { store.report(error: error.localizedDescription) }
            }
        }
        .confirmationDialog("Datei aus dem Projekt entfernen?", isPresented: Binding(get: { deletingID != nil }, set: { if !$0 { deletingID = nil } })) {
            Button("Entfernen", role: .destructive) {
                project.files?.removeAll { $0.id == deletingID }
                if activeID == deletingID { activeID = nil }; deletingID = nil
            }
        } message: { Text("Das importierte Original bleibt bis zum Löschen des Projekts im lokalen Speicher. Frühere Chatquellen bleiben im Verlauf.") }
    }
    private func add(_ kind: WorkspaceFileKind) {
        let file = WorkspaceFile(name: kind == .document ? "Neues Dokument" : "Neues Tabellenblatt", kind: kind, rows: kind == .table ? Array(repeating: Array(repeating: "", count: 5), count: 12) : [])
        project.files = (project.files ?? []) + [file]; activeID = file.id
    }
    private func export(_ ext: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = activeFile.name + "." + ext
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch ext {
            case "docx": try OfficeFiles.writeDOCX(activeFile, to: url)
            case "xlsx": try OfficeFiles.writeXLSX(project.allFiles.filter { $0.kind == .table }, to: url)
            case "rtf": try DocumentContent.encode(DocumentContent.attributed(text: activeFile.text, rtf: activeFile.rtf))?.write(to: url, options: .atomic)
            case "csv":
                let csv = activeFile.rows.map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }.joined(separator: "\n")
                try csv.write(to: url, atomically: true, encoding: .utf8)
            default: try activeFile.text.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch { store.report(error: "Export fehlgeschlagen: \(error.localizedDescription)") }
    }
}

struct PromptEditorSheet: View {
    @Binding var prompt: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Anweisungen für den Chat").font(.system(size: 19, weight: .semibold))
            Text("Diese Anweisungen gelten nur für dieses Projekt.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            TextEditor(text: $prompt).font(.system(size: 12, design: .monospaced))
                .padding(8).background(.background, in: RoundedRectangle(cornerRadius: 9))
            HStack {
                Button("Standard wiederherstellen") { prompt = WorkspaceDefaults.systemPrompt }
                Spacer()
                Button("Fertig") { onSave(); dismiss() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(22).frame(width: 560, height: 430)
    }
}
