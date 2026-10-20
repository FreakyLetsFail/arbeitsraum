import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ProjectMemoryView: View {
    @Binding var project: WorkspaceProject
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Projektgedächtnis").font(.title2); Spacer(); Button("Fertig") { dismiss() } }
            Text("Dauerhafte Notizen, die der Chat bei jeder Frage erhält. Du kannst sie jederzeit ändern oder löschen. Das Modell wird damit nicht trainiert.").font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(project.memory ?? []) { item in
                    HStack(alignment: .top) {
                        TextField("Notiz", text: Binding(get: { project.memory?.first { $0.id == item.id }?.text ?? "" }, set: { text in if let index = project.memory?.firstIndex(where: { $0.id == item.id }) { project.memory?[index].text = String(text.prefix(1_000)) } }), axis: .vertical)
                        Button(role: .destructive) { project.memory?.removeAll { $0.id == item.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless).accessibilityLabel("Notiz löschen")
                    }.padding(.vertical, 8)
                }
            }
            HStack {
                TextField("Neue Notiz …", text: $draft).textFieldStyle(.roundedBorder).onSubmit(add)
                Button("Merken", action: add).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (project.memory?.count ?? 0) >= 20)
            }
            Text("Bis 20 Notizen; der Chat erhält die ersten 3.000 Zeichen. Keine automatische Übernahme von Modellantworten.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 640, height: 480)
    }
    private func add() {
        let text = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000))
        guard !text.isEmpty, (project.memory?.count ?? 0) < 20 else { return }
        project.memory = (project.memory ?? []) + [.init(text: text)]; draft = ""
    }
}

struct ReferenceFileView: View {
    let file: WorkspaceFile
    let url: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let note = file.importNote { Label(note, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
            if let url, url.pathExtension.lowercased() == "pdf" { LocalPDFView(url: url) }
            else if let url, ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 250)
            }
            ScrollView { Text(file.text.isEmpty ? "Kein auslesbarer Text für den Chat vorhanden." : file.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
private struct LocalPDFView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.document = PDFDocument(url: url); return view }
    func updateNSView(_ view: PDFView, context: Context) { if view.document?.documentURL != url { view.document = PDFDocument(url: url) } }
}

enum WorkspaceImportTypes {
    static var all: [UTType] { OfficeFiles.supportedExtensions.compactMap { UTType(filenameExtension: $0) } }
}
