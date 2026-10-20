import SwiftUI

struct TemplateLibraryView: View {
    @ObservedObject var store: WorkspaceStore
    @State private var selectedID: UUID?
    @State private var searchText = ""
    @State private var kindFilter: KindFilter = .all
    @State private var editorSection: EditorSection = .content
    @State private var pendingDeletion: WorkspaceTemplate?

    private enum KindFilter: String, CaseIterable, Identifiable {
        case all, document, table
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "Alle"
            case .document: "Dokumente"
            case .table: "Tabellen"
            }
        }
        func includes(_ kind: WorkspaceKind) -> Bool {
            self == .all || (self == .document && kind == .document) || (self == .table && kind == .table)
        }
    }

    private enum EditorSection: String, CaseIterable, Identifiable {
        case content, instructions
        var id: String { rawValue }
        var title: String { self == .content ? "Inhalt" : "Chat-Anweisungen" }
    }

    private var filteredTemplates: [WorkspaceTemplate] {
        store.templates.filter { template in
            kindFilter.includes(template.kind) &&
            (searchText.isEmpty || template.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 280)
            Divider()
            editor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if selectedID == nil { selectedID = filteredTemplates.first?.id }
        }
        .onChange(of: filteredTemplates.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = ids.first }
            else if selectedID == nil { selectedID = ids.first }
        }
        .confirmationDialog(
            "Vorlage löschen?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { template in
            Button("„\(template.name)“ löschen", role: .destructive) { deleteTemplate(id: template.id) }
            Button("Abbrechen", role: .cancel) { pendingDeletion = nil }
        } message: { template in
            Text("Die Vorlage wird dauerhaft aus deiner lokalen Vorlagenliste entfernt.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Vorlagen")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Gerüste und Arbeitsanweisungen")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Menu {
                    Button { addTemplate(kind: .document) } label: { Label("Dokumentvorlage", systemImage: WorkspaceKind.document.symbol) }
                    Button { addTemplate(kind: .table) } label: { Label("Tabellenvorlage", systemImage: WorkspaceKind.table.symbol) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(.quaternary, in: Circle())
                }
                .menuStyle(.borderlessButton)
                .help("Vorlage anlegen")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Vorlagen suchen", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))

            Picker("Vorlagentyp", selection: $kindFilter) {
                ForEach(KindFilter.allCases) { filter in Text(filter.title).tag(filter) }
            }
            .pickerStyle(.segmented).labelsHidden()

            if filteredTemplates.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Keine Vorlagen" : "Nichts gefunden",
                    systemImage: searchText.isEmpty ? "doc.on.doc" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Lege eine Vorlage an, um zu beginnen." : "Passe den Suchbegriff oder den Typfilter an.")
                )
                .font(.system(size: 12))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredTemplates) { template in
                            templateRow(template)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.visible)
            }

            if let template = selectedTemplate {
                Divider()
                HStack(spacing: 8) {
                    Button { duplicateTemplate(id: template.id) } label: {
                        Label("Duplizieren", systemImage: "plus.square.on.square")
                    }
                    .help("Eine Kopie mit Inhalt und Chat-Anweisungen anlegen")
                    Spacer()
                    Button(role: .destructive) { pendingDeletion = template } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Vorlage löschen")
                }
                .font(.system(size: 12))
            }
        }
        .padding(16)
    }

    private func templateRow(_ template: WorkspaceTemplate) -> some View {
        let isSelected = selectedID == template.id
        return Button {
            selectedID = template.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: template.kind.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 3) {
                    Text(template.name.isEmpty ? "Unbenannte Vorlage" : template.name)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                    Text(template.kind.title)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(isSelected ? Color.accentColor.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var editor: some View {
        if let template = selectedTemplate {
            VStack(spacing: 0) {
                editorHeader(template)
                Divider()
                Picker("Bereich", selection: $editorSection) {
                    ForEach(EditorSection.allCases) { section in Text(section.title).tag(section) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .frame(maxWidth: 360)
                .padding(.vertical, 14)
                Divider()
                if editorSection == .content {
                    contentEditor(template)
                } else {
                    promptEditor(template)
                }
            }
        } else {
            ContentUnavailableView("Vorlage auswählen", systemImage: "doc.text", description: Text("Wähle links eine Vorlage aus oder lege eine neue an."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func editorHeader(_ template: WorkspaceTemplate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name der Vorlage", text: binding(for: template.id, keyPath: \.name, fallback: template.name))
                .font(.system(size: 20, weight: .semibold))
                .textFieldStyle(.plain)
                .accessibilityLabel("Name der Vorlage")
            HStack(spacing: 8) {
                Image(systemName: template.kind.symbol).foregroundStyle(.secondary)
                Picker("Vorlagentyp", selection: binding(for: template.id, keyPath: \.kind, fallback: template.kind)) {
                    ForEach(WorkspaceKind.allCases) { kind in Text(kind.title).tag(kind) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
                Spacer()
                Text("Änderungen werden lokal gespeichert")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private func contentEditor(_ template: WorkspaceTemplate) -> some View {
        if template.kind == .document {
            VStack(alignment: .leading, spacing: 10) {
                Text("Dokumentinhalt")
                    .font(.system(size: 14, weight: .semibold))
                Text("Dieses Gerüst wird in ein neu angelegtes Dokument übernommen. Nutze Überschriften und neutrale Platzhalter für Angaben, die später manuell ergänzt werden.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: binding(for: template.id, keyPath: \.body, fallback: template.body))
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
                    .accessibilityLabel("Dokumentgerüst der Vorlage")
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tabelleninhalt")
                    .font(.system(size: 14, weight: .semibold))
                Text("Spalten mit Tabulator trennen, Zeilen mit Zeilenumbruch; wird beim Anlegen übernommen.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: binding(for: template.id, keyPath: \.body, fallback: template.body))
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
                    .accessibilityLabel("Tabelleninhalt als tabulatorgetrennter Text")
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func promptEditor(_ template: WorkspaceTemplate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chat-Anweisungen für diese Vorlage")
                .font(.system(size: 14, weight: .semibold))
            Text("Diese Anweisungen steuern, wie der Chat zu neuen Projekten aus dieser Vorlage antwortet. Sie sind getrennt vom sichtbaren Dokumentgerüst. Formuliere den gewünschten Arbeitsstil und Grenzen; verwende keine echten oder erfundenen Patientendaten.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: binding(for: template.id, keyPath: \.systemPrompt, fallback: template.systemPrompt))
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
                .accessibilityLabel("Chat-Anweisungen dieser Vorlage")
            Text("Gilt für neue Projekte aus dieser Vorlage. Bestehende Projekte behalten ihre eigenen Chat-Anweisungen.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var selectedTemplate: WorkspaceTemplate? {
        guard let selectedID else { return nil }
        return store.templates.first { $0.id == selectedID }
    }

    private func binding<Value>(for id: UUID, keyPath: WritableKeyPath<WorkspaceTemplate, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: {
                store.templates.first(where: { $0.id == id })?[keyPath: keyPath] ?? fallback
            },
            set: { value in
                guard let index = store.templates.firstIndex(where: { $0.id == id }) else { return }
                var updated = store.templates
                updated[index][keyPath: keyPath] = value
                store.saveTemplates(updated)
            }
        )
    }

    private func addTemplate(kind: WorkspaceKind) {
        let template = WorkspaceTemplate(
            name: kind == .document ? "Neue Dokumentvorlage" : "Neue Tabellenvorlage",
            kind: kind,
            body: "",
            systemPrompt: WorkspaceDefaults.systemPrompt
        )
        store.saveTemplates(store.templates + [template])
        selectedID = template.id
        editorSection = .content
    }

    private func duplicateTemplate(id: UUID) {
        guard let original = store.templates.first(where: { $0.id == id }) else { return }
        var copy = original
        copy.id = UUID()
        copy.name = original.name.isEmpty ? "Kopie" : "\(original.name) – Kopie"
        store.saveTemplates(store.templates + [copy])
        selectedID = copy.id
        editorSection = .content
    }

    private func deleteTemplate(id: UUID) {
        let remaining = store.templates.filter { $0.id != id }
        store.saveTemplates(remaining)
        if selectedID == id { selectedID = remaining.first?.id }
        pendingDeletion = nil
    }
}
