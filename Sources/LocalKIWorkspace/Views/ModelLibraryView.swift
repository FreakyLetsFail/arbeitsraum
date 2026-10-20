import SwiftUI

struct ModelLibraryView: View {
    @ObservedObject var store: WorkspaceStore
    @EnvironmentObject private var library: ModelLibrary
    @State private var search = ""
    @State private var filter = "Alle"
    @State private var family = "Alle Familien"
    @State private var selection: String?
    @State private var showingServer = false
    @State private var specs: MacSpecifications?

    private var mac: MacSpecifications { specs ?? .current(storage: library.rootURL) }
    private var models: [CatalogModel] {
        CatalogModel.all.filter { model in
            let assessment = ModelAssessment.assess(model, on: mac)
            return (search.isEmpty || "\(model.title) \(model.id) \(model.family)".localizedCaseInsensitiveContains(search)) &&
                (family == "Alle Familien" || family == model.family) &&
                (filter != "Installiert" || library.installed[model.id] != nil) &&
                (filter != "Passend" || (model.nativeMLX && assessment.fit == .good))
        }.sorted { a, b in
            let left = ModelAssessment.assess(a, on: mac).score
            let right = ModelAssessment.assess(b, on: mac).score
            return left == right ? a.downloadBytes < b.downloadBytes : left > right
        }
    }
    private var selected: CatalogModel? { CatalogModel.model(id: selection ?? "") }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "desktopcomputer").font(.system(size: 19)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(mac.chip) · \(Int(mac.memoryGB)) GB Arbeitsspeicher").font(.system(size: 13, weight: .medium))
                    Text("\(mac.cores) CPU-Kerne · \(freeDisk) frei · Empfehlungen für diesen Mac")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Server …") { showingServer = true }.disabled(library.isBusy || store.settings.offlineMode)
                Button { specs = .current(storage: library.rootURL); library.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Speicher und Installationen aktualisieren")
            }.padding(16)
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 10) {
                    TextField("Modell suchen", text: $search).textFieldStyle(.roundedBorder)
                    Picker("Ansicht", selection: $filter) { ForEach(["Alle", "Passend", "Installiert"], id: \.self) { Text($0) } }
                        .pickerStyle(.segmented).labelsHidden()
                    Picker("Familie", selection: $family) {
                        Text("Alle Familien").tag("Alle Familien")
                        ForEach(Array(Set(CatalogModel.all.map(\.family))).sorted(), id: \.self) { Text($0).tag($0) }
                    }.labelsHidden()
                    List(selection: $selection) {
                        ForEach(models) { model in
                            modelRow(model).tag(Optional(model.id))
                        }
                    }.listStyle(.plain)
                    HStack { Text("\(models.count) Modelle"); Spacer(); Text("Nach Eignung sortiert") }
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(12).frame(width: 320)
                Divider()
                if let selected {
                    modelDetail(selected)
                } else {
                    ContentUnavailableView("Modell auswählen", systemImage: "cpu", description: Text("Größe, Laufzeit und Eignung vergleichen."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onChange(of: search) { _, _ in updateSelection() }
        .onChange(of: filter) { _, _ in updateSelection() }
        .onChange(of: family) { _, _ in updateSelection() }
        .onAppear {
            specs = .current(storage: library.rootURL)
            selection = models.first?.id
        }
        .sheet(isPresented: $showingServer) {
            VStack {
                HStack { Text("Lokaler Server").font(.headline); Spacer(); Button("Fertig") { showingServer = false } }.padding(18)
                LocalServerSettingsView(store: store)
            }.frame(width: 700, height: 470)
        }
    }
    private func updateSelection() {
        if !models.contains(where: { $0.id == selection }) { selection = models.first?.id }
    }
    private var freeDisk: String {
        mac.freeDiskBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Speicher unbekannt"
    }
    private func modelRow(_ model: CatalogModel) -> some View {
        let assessment = ModelAssessment.assess(model, on: mac)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(model.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                if library.activeModelID == model.id { Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.green) }
                else if library.installed[model.id] != nil { Image(systemName: "checkmark").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            Text("\(model.diskSize) · \(model.nativeMLX ? "MLX" : model.support == .server ? "Server" : "Nicht unterstützt")")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Text(assessment.title).font(.system(size: 10)).foregroundStyle(assessment.fit == .tooLarge ? Color.orange : Color.secondary)
        }.padding(.vertical, 5)
    }
    private func modelDetail(_ model: CatalogModel) -> some View {
        let assessment = ModelAssessment.assess(model, on: mac)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.family).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(model.title).font(.system(size: 23, weight: .semibold))
                    Text(model.summary).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 22) {
                    metric("Download", value: model.diskSize)
                    metric("Parameter", value: model.totalParameters)
                    if let active = model.activeParameters { metric("Aktiv / Token", value: active) }
                }
                VStack(alignment: .leading, spacing: 7) {
                    Label(assessment.title, systemImage: assessment.fit == .good ? "checkmark.circle" : "info.circle")
                        .font(.system(size: 12, weight: .medium))
                    Text(assessment.reason).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("Planungswert: etwa \(String(format: "%.1f", assessment.estimatedTotalGB)) GB inklusive macOS und begrenztem Kontext. Keine Messung von Spitzenverbrauch oder Geschwindigkeit.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                actions(model, assessment: assessment)
                if library.downloadingID == model.id {
                    ProgressView(value: library.downloadProgress)
                    HStack {
                        Text("\(Int(library.downloadProgress * 100)) % · \(library.downloadDetail)").lineLimit(1)
                        Spacer()
                        Button("Abbrechen") { library.cancelDownload() }
                    }.font(.system(size: 11))
                }
                if let error = library.errorMessage {
                    HStack(alignment: .top) {
                        Text(error).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled)
                        Spacer()
                        Button { library.clearError() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }
                }
                if let result = library.testResult, library.testResultModelID == model.id {
                    Text(result).font(.system(size: 11)).textSelection(.enabled)
                }
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 12) {
                    detailRow("Laufzeit", value: model.nativeMLX ? "MLX in der App" : model.support == .server ? "Separater lokaler Server" : "Hier nicht eingebaut")
                    detailRow("Prüfstand", value: model.tested ? "Textgenerierung auf diesem Mac geprüft" : "Nicht praktisch geprüft")
                    detailRow("Speicher", value: "Ab \(model.recommendedRAMGB) GB empfohlen")
                    detailRow("Format", value: model.quantization)
                    detailRow("Lizenz", value: model.license)
                }.font(.system(size: 11))
                if model.nativeMLX {
                    Text("Die Architektur ist in MLX Swift enthalten. Die App begrenzt Eingaben auf 6.000 Tokens und Ausgaben auf 1.536 Tokens. Thinking-Modelle können dieses Limit früh erreichen.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else if model.support == .server {
                    Text("Ollama oder einen kompatiblen Server separat installieren und dieses Modell dort lokal laden. Die App lädt Servermodelle nicht herunter. Cloud-Varianten sind ausgeschlossen.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("ollama pull \(model.id)").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                } else {
                    Text("Die Nota-Gewichte sind tatsächlich ternär in einem 2-Bit-Container. Der Snapshot verwendet layers_block_type; die eingebundene Nemotron-Implementierung erwartet hybrid_override_pattern. Ein Download allein würde diese Inkompatibilität nicht beheben.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Link("Modellquelle und Lizenz ↗", destination: model.sourceURL).font(.system(size: 11))
                Text(model.id).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary).textSelection(.enabled)
                Text("Sortierung nach Laufzeit, Speicherreserve und Modellgröße relativ zum RAM; mit kuratierter Priorität für Textaufgaben. Keine Qualitätsbewertung. Katalogstand 20.10.2026.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private func actions(_ model: CatalogModel, assessment: ModelAssessment) -> some View {
        HStack(spacing: 10) {
            if model.nativeMLX {
                if library.installed[model.id] != nil {
                    if library.activeModelID == model.id {
                        Text("Geladen").font(.system(size: 11)).foregroundStyle(.secondary)
                        Button("Testen") { Task { await library.runSelfTest(model) } }.disabled(library.isBusy)
                        Button("Entladen") { Task { await library.unload() } }.disabled(library.isBusy)
                    } else {
                        Button(library.isLoading ? "Wird geladen …" : "Verwenden") {
                            Task {
                                await library.activate(model)
                                if library.activeModelID == model.id {
                                    store.settings.runtime = .mlx; store.settings.selectedMLXModelID = model.id; store.saveSettings()
                                }
                            }
                        }.buttonStyle(.borderedProminent).disabled(library.isBusy || !model.fitsThisMac)
                    }
                    Menu {
                        Button("In Papierkorb", role: .destructive) { Task { await library.remove(model) } }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().disabled(library.isBusy)
                } else {
                    Button(library.downloadingID == model.id ? "Wird geladen …" : "Herunterladen") { library.startDownload(model) }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.settings.offlineMode || library.downloadingID != nil || assessment.fit == .tooLarge || assessment.fit == .unsupported || insufficientDisk(model))
                        .help(store.settings.offlineMode ? "Downloads unter Datenschutz freigeben" : insufficientDisk(model) ? "Nicht genügend freier Speicher" : "Nur öffentliche Modelldateien werden geladen.")
                }
            } else if model.support == .server {
                Button("Server einrichten") {
                    store.settings.localModelName = model.id; store.settings.runtime = .localServer; store.saveSettings()
                    Task { await library.unload() }
                    showingServer = true
                }.disabled(library.isBusy)
            }
            if library.isBusy { ProgressView().controlSize(.small) }
        }
    }
    private func insufficientDisk(_ model: CatalogModel) -> Bool {
        library.installed[model.id] == nil && (mac.freeDiskBytes ?? Int64.max) < model.downloadBytes + 500_000_000
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(size: 16, weight: .medium))
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
    private func detailRow(_ title: String, value: String) -> some View {
        GridRow { Text(title).foregroundStyle(.secondary); Text(value).textSelection(.enabled) }
    }
}
