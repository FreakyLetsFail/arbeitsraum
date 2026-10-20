import SwiftUI

struct WorkspaceSettingsView: View {
    @ObservedObject var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Einstellungen").font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("Fertig") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .padding(18)
            Divider()
            TabView {
                ModelLibraryView(store: store)
                    .tabItem { Label("Modelle", systemImage: "cpu") }
                TemplateLibraryView(store: store)
                    .tabItem { Label("Vorlagen & Prompts", systemImage: "doc.on.doc") }
                PrivacySettingsView(store: store)
                    .tabItem { Label("Datenschutz", systemImage: "lock.shield") }
            }
            .padding(14)
        }
        .frame(width: 980, height: 720)
    }
}

struct LocalServerSettingsView: View {
    @ObservedObject var store: WorkspaceStore
    @State private var checking = false
    @State private var result: String?
    @State private var availableModels: [String] = []

    private let engine: any LocalLanguageModelEngine = LoopbackOpenAIEngine()

    var body: some View {
        Form {
            Section("Lokaler Modellserver") {
                TextField("OpenAI-kompatible Basis-URL", text: $store.settings.localModelEndpoint)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: store.settings.localModelEndpoint) { _, _ in store.saveSettings() }
                TextField("Modellkennung", text: $store.settings.localModelName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: store.settings.localModelName) { _, _ in store.saveSettings() }
                HStack {
                    Button {
                        Task { await checkConnection() }
                    } label: {
                        if checking { ProgressView().controlSize(.small) }
                        else { Label("Lokale Verbindung prüfen", systemImage: "antenna.radiowaves.left.and.right") }
                    }
                    .disabled(checking)
                    Spacer()
                    Text("Nur localhost / Loopback").font(.system(size: 11, weight: .medium)).foregroundStyle(.green)
                }
                if let result {
                    Text(result).font(.system(size: 11)).foregroundStyle(result.hasPrefix("Verbunden") ? .green : .orange)
                }
                if !availableModels.isEmpty {
                    Picker("Gefundenes Modell", selection: $store.settings.localModelName) {
                        ForEach(availableModels, id: \.self) { model in Text(model).tag(model) }
                    }
                    .onChange(of: store.settings.localModelName) { _, _ in store.saveSettings() }
                    Text("Die Liste stammt vom lokalen Server. Nur lokale Modellkennungen verwenden.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }

            Section("Verarbeitung") {
                Text("Nur lokale HTTP-Adressen sind erlaubt. Verwende einen vertrauenswürdigen Server mit lokal gespeicherten Gewichten. Die App kann nicht erkennen, ob ein beliebiger Server intern Daten weiterleitet.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Das ausgewählte Modell wird im Chat verwendet. Installation und Download der Servermodelle erfolgen außerhalb dieser App.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private var physicalMemory: String {
        let bytes = ProcessInfo.processInfo.physicalMemory
        let gib = Double(bytes) / 1_073_741_824
        return "\(Int(gib.rounded())) GB"
    }

    @MainActor
    private func checkConnection() async {
        guard !store.settings.offlineMode else { result = "Im Offline-Modus sind Serververbindungen gesperrt."; return }
        checking = true
        result = nil
        availableModels = []
        defer { checking = false }
        do {
            let configuration = LocalModelConfiguration(endpoint: store.settings.localModelEndpoint, model: store.settings.localModelName)
            availableModels = try await engine.availableModels(configuration: configuration).filter { !LoopbackOpenAIEngine.isCloudModel($0) }
            if availableModels.contains(configuration.model) {
                result = "Verbunden · gewünschtes Modell ist verfügbar."
            } else if availableModels.isEmpty {
                result = "Server erreichbar; er hat keine Modellkennungen gemeldet."
            } else {
                result = "Server erreichbar; das konfigurierte Modell wurde nicht in der Liste gefunden."
            }
        } catch {
            result = error.localizedDescription
        }
    }
}

private struct PrivacySettingsView: View {
    @ObservedObject var store: WorkspaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Offline-Modus", isOn: $store.settings.offlineMode)
                .onChange(of: store.settings.offlineMode) { _, value in
                    store.modelLibrary.networkAllowed = !value
                    if value { store.modelLibrary.cancelDownload() }
                    store.saveSettings()
                }
            Text("Standardmäßig aktiv: keine Modelldownloads und keine Serververbindungen. Bereits installierte MLX-Modelle und die Dokumentfunktionen funktionieren ohne Netzwerk.").font(.caption).foregroundStyle(.secondary)
            privacyItem("Projekte und Vorlagen", "JSON-Dateien im lokalen App-Speicher mit eingeschränkten Dateirechten.", symbol: "internaldrive")
            privacyItem("MLX in der App", "Texte werden direkt auf diesem Mac verarbeitet. Der Modell-Ladepfad verwendet ausschließlich vollständig heruntergeladene lokale Dateien.", symbol: "cpu")
            privacyItem("Modelldownloads", "Nur der ausdrückliche Download lädt öffentliche Gewichte aus Hugging Face. Dabei werden keine Projektinhalte oder Audiodateien gesendet.", symbol: "arrow.down.circle")
            privacyItem("Optionaler lokaler Server", "Anfragen gehen nur an Loopback. Der lokale Server muss selbst vertrauenswürdig und lokal konfiguriert sein.", symbol: "network")
            privacyItem("Transkription", "Apple Speech mit erzwungener On-Device-Erkennung. Fehlt das Offline-Sprachmodell, wird abgebrochen.", symbol: "waveform")
            privacyItem("Audio", "Importierte oder aufgenommene Dateien werden lokal im jeweiligen Projekt gespeichert.", symbol: "waveform.badge.mic")
            Divider()
            Text("Diese erste Version ist keine geprüfte Gesundheitssoftware und begründet keine DSGVO-Konformität. Für reale Patientendaten müssen auch macOS-Benutzerkonto, Geräteschutz, Backups, Aufbewahrung, Zugriffsrechte und die konkrete Laufzeitumgebung geprüft werden.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Link("Fehler melden oder Verbesserung vorschlagen (GitHub · online)", destination: URL(string: "https://github.com/FreakyLetsFail/arbeitsraum/issues/new/choose")!)
                .font(.callout)
            Text("Öffnet nur auf Klick den Browser. Keine Projektinhalte, Protokolle oder Dateien werden automatisch übertragen.").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
    }

    private func privacyItem(_ title: String, _ detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.green).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}
