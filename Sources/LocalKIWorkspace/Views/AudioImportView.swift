import AVFoundation
import Speech
import SwiftUI
import UniformTypeIdentifiers

struct AudioImportView: View {
    @Binding var project: WorkspaceProject
    @ObservedObject var store: WorkspaceStore
    let onCreated: (UUID) -> Void
    var destinationFileID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorder()
    @State private var showingFileImporter = false
    @State private var selectedAssetID: UUID?
    @State private var selectedAudioURL: URL?
    @State private var transcript = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isTranscribing = false

    private var selectedAsset: AudioAsset? { project.audioAssets.first { $0.id == selectedAssetID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("Audio und Transkript", systemImage: "waveform").font(.system(size: 19, weight: .semibold))
                Spacer()
                Button("Fertig") { dismiss() }.disabled(recorder.isRecording)
            }
            Text("Audio importieren oder aufnehmen. Für die Transkription wird ein deutsches Offline-Sprachmodell benötigt.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button { showingFileImporter = true } label: { Label("Datei importieren", systemImage: "square.and.arrow.down") }
                    .disabled(recorder.isRecording || isTranscribing)
                Button {
                    if recorder.isRecording { stopRecording() }
                    else { Task { await startRecording() } }
                } label: {
                    Label(recorder.isRecording ? "Aufnahme beenden" : "Aufnehmen", systemImage: recorder.isRecording ? "stop.fill" : "record.circle")
                }
                .tint(recorder.isRecording ? .red : nil)
                .disabled(isTranscribing)
                Spacer()
                if recorder.isRecording {
                    Label("Aufnahme läuft", systemImage: "circle.fill").font(.system(size: 11, weight: .medium)).foregroundStyle(.red)
                }
            }

            if !project.audioAssets.isEmpty {
                HStack {
                    Text("Audiodatei").font(.system(size: 11, weight: .semibold))
                    Picker("Audiodatei", selection: $selectedAssetID) {
                        ForEach(project.audioAssets) { asset in Text(asset.fileName).tag(Optional(asset.id)) }
                    }
                    .labelsHidden().frame(maxWidth: 400)
                    .onChange(of: selectedAssetID) { _, newValue in
                        if let asset = project.audioAssets.first(where: { $0.id == newValue }) {
                            selectedAudioURL = store.audioFileURL(for: asset)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await transcribe() }
                    } label: {
                        if isTranscribing { ProgressView().controlSize(.small) }
                        else { Label("Offline transkribieren", systemImage: "text.bubble") }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTranscribing || recorder.isRecording || selectedAudioURL == nil)
                }
                if let selectedAsset {
                    Text("Hinzugefügt am \(selectedAsset.addedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }

            if let statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(.green)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Transkript · prüfen und korrigieren").font(.system(size: 11, weight: .semibold))
                    Spacer()
                    if !transcript.isEmpty { Text("\(transcript.split(whereSeparator: \.isWhitespace).count) Wörter").font(.system(size: 10)).foregroundStyle(.secondary) }
                }
                TextEditor(text: $transcript)
                    .font(.system(size: 12))
                    .padding(8).background(.background, in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button("In dieses Dokument übernehmen") {
                        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        var destination = project.content(for: destinationFileID ?? project.id)
                        DocumentContent.append("\n\nTranskript — manuell zu prüfen\n\(transcript)\n", to: &destination)
                        project.updateContent(destination, fileID: destinationFileID ?? project.id)
                        store.updateProject(project)
                        dismiss()
                    }
                    .disabled(destinationFileID == nil || transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    Button("Neues Dokument daraus") { createDocumentFromTranscript() }
                        .buttonStyle(.borderedProminent)
                        .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(20)
        .frame(width: 700, height: 650)
        .interactiveDismissDisabled(recorder.isRecording)
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .onAppear {
            if let asset = project.audioAssets.first {
                selectedAssetID = asset.id
                selectedAudioURL = store.audioFileURL(for: asset)
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let source = try result.get().first else { return }
            let (updatedProject, copiedURL) = try store.addAudioAsset(from: source, to: project)
            project = updatedProject
            selectedAssetID = updatedProject.audioAssets.first?.id
            selectedAudioURL = copiedURL
            transcript = ""
            statusMessage = "Audio wurde lokal in diesem Projekt gespeichert."
            errorMessage = nil
        } catch {
            errorMessage = "Audioimport fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func startRecording() async {
        errorMessage = nil
        let permission = await requestMicrophonePermission()
        guard permission else {
            errorMessage = "Mikrofonzugriff wurde nicht erteilt."
            return
        }
        do {
            let directory = store.audioURL.appending(path: project.id.uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = "Aufnahme-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).m4a"
            let destination = directory.appending(path: name)
            try recorder.start(at: destination)
            statusMessage = "Mikrofonaufnahme läuft."
        } catch {
            errorMessage = "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func stopRecording() {
        guard let url = recorder.stop() else { return }
        let name = url.lastPathComponent
        project = store.registerRecordedAudio(at: url, fileName: name, for: project)
        selectedAssetID = project.audioAssets.first?.id
        selectedAudioURL = url
        statusMessage = "Aufnahme lokal gespeichert."
    }

    @MainActor
    private func transcribe() async {
        guard let selectedAudioURL else { return }
        errorMessage = nil
        statusMessage = nil
        isTranscribing = true
        defer { isTranscribing = false }
        let authorized = await requestSpeechPermission()
        guard authorized else {
            errorMessage = "Spracherkennung wurde nicht freigegeben. Es wurde keine Transkription gestartet."
            return
        }
        do {
            transcript = try await OfflineTranscriptionService().transcribe(fileURL: selectedAudioURL)
            statusMessage = "Offline-Transkription abgeschlossen. Bitte den Text fachlich prüfen."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func createDocumentFromTranscript() {
        let content = "Rohtranskript — bitte prüfen und korrigieren\n\n\(transcript)\n"
        var created = store.createProject(title: "Transkript \(Date().formatted(date: .numeric, time: .omitted))", kind: .document, template: nil)
        created.documentText = content
        store.updateProject(created)
        if let selectedAudioURL, let copied = try? store.addAudioAsset(from: selectedAudioURL, to: created) {
            created = copied.0
        }
        onCreated(created.id)
        dismiss()
    }

    private func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .authorized { return true }
        if status == .denied || status == .restricted { return false }
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in continuation.resume(returning: granted) }
        }
    }

    private func requestSpeechPermission() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        if status == .denied || status == .restricted { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { newStatus in continuation.resume(returning: newStatus == .authorized) }
        }
    }
}
