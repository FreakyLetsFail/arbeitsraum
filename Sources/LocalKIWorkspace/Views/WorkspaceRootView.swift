import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum WorkspacePalette {
    static let canvas = color(light: 0xF6F0E7, dark: 0x2D2924)
    static let sidebar = color(light: 0xEEE7DA, dark: 0x332E28)
    static let paperNS = nativeColor(light: 0xFFFCF6, dark: 0x3C352E)
    static let paper = Color(nsColor: paperNS)
    static let toolbar = color(light: 0xF0E9DE, dark: 0x342F29)
    static let border = color(light: 0xDED5C7, dark: 0x51483E)
    static let ink = color(light: 0x49423B, dark: 0xF0E5D8)
    static let muted = color(light: 0x766E64, dark: 0xC4B5A4)
    static let sage = color(light: 0x68795F, dark: 0xA9B99E)
    static let sageWash = color(light: 0xE1E8DA, dark: 0x444C3F)
    static let clay = color(light: 0xA96750, dark: 0xD09379)
    static let warmWash = color(light: 0xF3E4D7, dark: 0x4A3B31)

    private static func color(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: nativeColor(light: light, dark: dark))
    }

    private static func nativeColor(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }
    }
}

struct WorkspaceRootView: View {
    @ObservedObject var store: WorkspaceStore
    @State private var selectedProjectID: UUID?
    @State private var expandedProjectIDs: Set<UUID> = []
    @State private var selectedFileIDs: [UUID: UUID] = [:]
    @State private var showingNewProject = false
    @State private var showingSettings = false
    @State private var newKind: WorkspaceKind = .document
    @State private var search = ""

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    if let icon = AuroraBrand.icon {
                        Image(nsImage: icon).resizable().interpolation(.high)
                            .aspectRatio(contentMode: .fit).frame(width: 34, height: 34)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "sun.max.fill").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white).frame(width: 30, height: 30)
                            .background(WorkspacePalette.clay, in: Circle()).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Aurora").font(.system(size: 16, weight: .medium, design: .serif))
                        Text("Dein lokaler Arbeitsbereich").font(.system(size: 10))
                            .foregroundStyle(WorkspacePalette.muted)
                    }
                    Spacer()
                    Button { create(.document) } label: { Image(systemName: "square.and.pencil") }
                        .buttonStyle(.plain).help("Neues Projekt · ⌘N").accessibilityLabel("Neues Projekt")
                        .keyboardShortcut("n", modifiers: .command)
                }.padding(.horizontal, 16).padding(.top, 19).padding(.bottom, 17)
                TextField("Projekte suchen", text: $search)
                    .textFieldStyle(.plain)
                    .padding(9)
                    .background(WorkspacePalette.paper, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(WorkspacePalette.border))
                    .padding(.horizontal, 12).padding(.bottom, 14)
                Button { selectedProjectID = nil } label: {
                    HStack { Label("Alle Projekte", systemImage: "square.grid.2x2"); Spacer() }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selectedProjectID == nil ? WorkspacePalette.ink : WorkspacePalette.muted)
                        .padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
                        .background(selectedProjectID == nil ? WorkspacePalette.sageWash : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 8).accessibilityIdentifier("all-projects")
                List {
                    Section("Projekte") {
                        ForEach(visibleProjects) { project in
                            projectRow(project)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(.clear)
                Rectangle().fill(WorkspacePalette.border).frame(height: 1)
                Button { showingSettings = true } label: {
                    HStack { Image(systemName: "slider.horizontal.3").foregroundStyle(WorkspacePalette.sage); Text("Modelle & Einstellungen"); Spacer() }
                        .font(.system(size: 11, weight: .medium)).padding(.horizontal, 15).padding(.vertical, 14).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(WorkspacePalette.ink)
            }
            .background(WorkspacePalette.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 240, max: 300)
        } detail: {
            if let project = store.projects.first(where: { $0.id == selectedProjectID }) {
                WorkspaceEditor(project: binding(for: project), activeID: fileSelection(for: project.id), store: store, onCreated: { selectedProjectID = $0 })
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
        .tint(WorkspacePalette.sage)
        .background(WorkspacePalette.canvas)
    }
    private func create(_ kind: WorkspaceKind) { newKind = kind; showingNewProject = true }
    private var visibleProjects: [WorkspaceProject] {
        store.projects.filter { project in
            search.isEmpty || project.title.localizedCaseInsensitiveContains(search) ||
                project.allFiles.contains { $0.name.localizedCaseInsensitiveContains(search) }
        }
    }
    private func projectRow(_ project: WorkspaceProject) -> some View {
        let expanded = expandedProjectIDs.contains(project.id)
        let selectedProject = selectedProjectID == project.id && (selectedFileIDs[project.id] == nil || selectedFileIDs[project.id] == project.id)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                Button {
                    if expanded { expandedProjectIDs.remove(project.id) }
                    else { expandedProjectIDs.insert(project.id) }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 18, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? "Dateien einklappen" : "Dateien anzeigen")
                .accessibilityLabel(expanded ? "Dateien von \(project.title) einklappen" : "Dateien von \(project.title) anzeigen")

                Button { selectProject(project) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: project.kind.symbol)
                        Text(project.title).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                    .font(.system(size: 12, weight: selectedProject ? .medium : .regular))
                    .foregroundStyle(WorkspacePalette.ink)
                    .background(selectedProject ? WorkspacePalette.sageWash : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Projekt \(project.title)")
            }

            if expanded {
                ForEach(project.allFiles) { file in
                    let selectedFile = selectedProjectID == project.id && selectedFileIDs[project.id] == file.id
                    Button { selectFile(file, in: project) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: file.kind.symbol).frame(width: 14)
                            Text(file.name).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 11))
                        .padding(.leading, 30)
                        .padding(.trailing, 8)
                        .frame(height: 27)
                        .contentShape(Rectangle())
                        .foregroundStyle(selectedFile ? WorkspacePalette.ink : WorkspacePalette.muted)
                        .background(selectedFile ? WorkspacePalette.warmWash : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Datei \(file.name) in \(project.title) öffnen")
                }
            }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .contextMenu {
            Button("In Papierkorb", role: .destructive) {
                if selectedProjectID == project.id {
                    selectedProjectID = nil
                    selectedFileIDs[project.id] = nil
                }
                expandedProjectIDs.remove(project.id)
                store.deleteProject(project)
            }
        }
    }
    private func selectProject(_ project: WorkspaceProject) {
        selectedProjectID = project.id
        selectedFileIDs[project.id] = nil
    }
    private func selectFile(_ file: WorkspaceFile, in project: WorkspaceProject) {
        selectedProjectID = project.id
        selectedFileIDs[project.id] = file.id
        expandedProjectIDs.insert(project.id)
    }
    private func fileSelection(for projectID: UUID) -> Binding<UUID?> {
        Binding(get: { selectedFileIDs[projectID] }, set: { selectedFileIDs[projectID] = $0 })
    }
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
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("DEIN LOKALER ARBEITSPLATZ", systemImage: "leaf")
                        .font(.system(size: 9, weight: .semibold)).tracking(1.1)
                        .foregroundStyle(WorkspacePalette.sage)
                    Text("Deine Projekte")
                        .font(.system(size: 30, weight: .regular, design: .serif))
                        .foregroundStyle(WorkspacePalette.ink)
                    Text("Dokumente, Tabellen und Chat an einem Ort.")
                        .font(.system(size: 13)).foregroundStyle(WorkspacePalette.muted)
                }
                Spacer()
                Menu {
                    Button("Dokument") { onCreate(.document) }
                    Button("Tabelle") { onCreate(.table) }
                } label: { Label("Neues Projekt", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize().buttonStyle(.borderedProminent)
            }
            HStack(spacing: 8) {
                filterButton("Alle", value: nil)
                filterButton("Dokumente", value: .document)
                filterButton("Tabellen", value: .table)
                Spacer()
                Label("Auf diesem Mac gespeichert", systemImage: "internaldrive")
                    .font(.system(size: 10)).foregroundStyle(WorkspacePalette.muted)
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
                    LazyVStack(spacing: 9) {
                        ForEach(store.projects.filter { filter == nil || $0.kind == filter }) { project in
                            Button { onSelect(project.id) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: project.kind.symbol).font(.system(size: 17, weight: .regular))
                                        .foregroundStyle(WorkspacePalette.sage).frame(width: 42, height: 42)
                                        .background(WorkspacePalette.sageWash, in: RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(project.title).font(.system(size: 14, weight: .medium)).foregroundStyle(WorkspacePalette.ink)
                                        Text(project.allFiles.count == 1 ? "1 Datei" : "\(project.allFiles.count) Dateien")
                                            .font(.system(size: 11)).foregroundStyle(WorkspacePalette.muted)
                                    }
                                    Spacer()
                                    Text(project.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 10)).foregroundStyle(WorkspacePalette.muted)
                                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(WorkspacePalette.muted.opacity(0.7))
                                }
                                .padding(.vertical, 13).padding(.horizontal, 14).contentShape(Rectangle())
                                .background(WorkspacePalette.paper, in: RoundedRectangle(cornerRadius: 13))
                                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(WorkspacePalette.border.opacity(0.8)))
                                .shadow(color: WorkspacePalette.ink.opacity(0.035), radius: 9, x: 0, y: 3)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }.padding(34).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WorkspacePalette.canvas)
    }
    private func filterButton(_ title: String, value: WorkspaceKind?) -> some View {
        Button { filter = value } label: {
            Text(title).font(.system(size: 12, weight: filter == value ? .medium : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(filter == value ? WorkspacePalette.sageWash : .clear, in: Capsule())
        }.buttonStyle(.plain).foregroundStyle(filter == value ? WorkspacePalette.ink : WorkspacePalette.muted)
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
    @Binding var activeID: UUID?
    @ObservedObject var store: WorkspaceStore
    let onCreated: (UUID) -> Void
    @State private var showingChat = true
    @State private var showingAudio = false
    @State private var showingPrompt = false
    @State private var showingMemory = false
    @State private var showingImport = false
    @State private var importing = false
    @State private var deletingID: UUID?
    private var fileID: UUID { activeID ?? project.id }
    private var activeFile: WorkspaceFile { project.allFiles.first { $0.id == fileID } ?? project.allFiles[0] }
    private var content: Binding<WorkspaceProject> {
        Binding(get: { project.content(for: fileID) }, set: { project.updateContent($0, fileID: fileID) })
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(project.allFiles) { file in
                            Button { activeID = file.id } label: {
                                Label(file.name, systemImage: file.kind.symbol).lineLimit(1).padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(file.id == fileID ? WorkspacePalette.sageWash : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(file.id == fileID ? WorkspacePalette.ink : WorkspacePalette.muted)
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
            }.font(.system(size: 12)).padding(.horizontal, 14).padding(.vertical, 7)
                .background(WorkspacePalette.toolbar)
            Rectangle().fill(WorkspacePalette.border).frame(height: 1)
            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: activeFile.kind.symbol).foregroundStyle(WorkspacePalette.sage)
                        TextField("Dateiname", text: content.title).textFieldStyle(.plain).font(.system(size: 12, weight: .medium))
                        Spacer()
                        if activeFile.importNote != nil { Image(systemName: "info.circle").help(activeFile.importNote ?? "") }
                    }.padding(.horizontal, 18).frame(height: 38).background(WorkspacePalette.toolbar)
                    Rectangle().fill(WorkspacePalette.border).frame(height: 1)
                    Group {
                        if activeFile.kind == .reference { ReferenceFileView(file: activeFile, url: store.originalFileURL(activeFile)) }
                        else if activeFile.kind == .document { DocumentEditor(project: content) }
                        else { SpreadsheetEditor(project: content) }
                    }.id(fileID)
                }.frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity).background(WorkspacePalette.canvas)
                if showingChat {
                    AssistantPanel(project: $project, store: store, activeFileID: fileID)
                        .frame(minWidth: 300, idealWidth: 370, maxWidth: 540, maxHeight: .infinity)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                TextField("Projektname", text: $project.title)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .font(.system(size: 14, weight: .medium))
                    .accessibilityLabel("Projektname")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showingAudio = true } label: { Label("Audio", systemImage: "waveform").labelStyle(.titleAndIcon) }
                Button { showingMemory = true } label: { Label("Gedächtnis", systemImage: "bookmark").labelStyle(.titleAndIcon) }
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
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Export und Projekteinstellungen")
                Button { showingChat.toggle() } label: { Image(systemName: "sidebar.right") }
                    .help(showingChat ? "Chat ausblenden" : "Chat einblenden")
                    .accessibilityLabel(showingChat ? "Chat ausblenden" : "Chat einblenden")
            }
        }
        .tint(WorkspacePalette.sage)
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
            case "rtf":
                if let data = DocumentContent.encode(DocumentContent.attributed(text: activeFile.text, rtf: activeFile.rtf)) {
                    try ExportFileWriter.write(data, to: url)
                }
            case "csv":
                let csv = activeFile.rows.map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }.joined(separator: "\n")
                try ExportFileWriter.write(Data(csv.utf8), to: url)
            default: try ExportFileWriter.write(Data(activeFile.text.utf8), to: url)
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
