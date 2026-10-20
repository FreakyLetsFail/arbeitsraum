import AppKit
import SwiftUI

@MainActor
final class DocumentFormatting: ObservableObject {
    enum Action {
        case bold, italic, underline, heading, body
        case fontFamily(String), fontSize(CGFloat), alignment(NSTextAlignment), bullet, print
    }
    @Published var command: (UUID, Action)?
    func send(_ action: Action) { command = (UUID(), action) }
}

enum DocumentContent {
    static func append(_ suffix: String, to project: inout WorkspaceProject) {
        let content = attributed(text: project.documentText, rtf: project.documentRTF)
        content.append(NSAttributedString(string: suffix, attributes: baseAttributes))
        project.documentText = content.string
        project.documentRTF = encode(content)
    }
    static var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        paragraph.paragraphSpacing = 10
        return [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
    }
    static func attributed(text: String, rtf: Data?) -> NSMutableAttributedString {
        if let rtf, let value = try? NSMutableAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil), value.string == text { return value }
        return NSMutableAttributedString(string: text, attributes: baseAttributes)
    }
    static func encode(_ content: NSAttributedString) -> Data? {
        try? content.data(from: NSRange(location: 0, length: content.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
}

struct DocumentEditor: View {
    @Binding var project: WorkspaceProject
    @StateObject private var formatting = DocumentFormatting()
    @State private var zoom = 100

    private var wordCount: Int { project.documentText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button("Text") { formatting.send(.body) }.help("Absatz als normalen Text formatieren")
                Button("Überschrift") { formatting.send(.heading) }
                Divider().frame(height: 16).padding(.horizontal, 6)
                Menu("Schrift") {
                    Button("System") { formatting.send(.fontFamily("system")) }
                    Button("Avenir Next") { formatting.send(.fontFamily("AvenirNext-Regular")) }
                    Button("Georgia") { formatting.send(.fontFamily("Georgia")) }
                    Button("Helvetica Neue") { formatting.send(.fontFamily("HelveticaNeue")) }
                    Button("Courier New") { formatting.send(.fontFamily("CourierNewPSMT")) }
                }
                .menuStyle(.borderlessButton).fixedSize().help("Schriftfamilie für Auswahl oder nächste Eingabe")
                Menu("Größe") {
                    ForEach([10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 28, 32], id: \.self) { size in
                        Button("\(size) pt") { formatting.send(.fontSize(CGFloat(size))) }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize().help("Schriftgröße für Auswahl oder nächste Eingabe")
                Divider().frame(height: 16).padding(.horizontal, 6)
                Button { formatting.send(.bold) } label: { Image(systemName: "bold") }
                    .keyboardShortcut("b", modifiers: .command).help("Fett · ⌘B").accessibilityLabel("Fett")
                Button { formatting.send(.italic) } label: { Image(systemName: "italic") }
                    .keyboardShortcut("i", modifiers: .command).help("Kursiv · ⌘I").accessibilityLabel("Kursiv")
                Button { formatting.send(.underline) } label: { Image(systemName: "underline") }
                    .keyboardShortcut("u", modifiers: .command).help("Unterstrichen · ⌘U").accessibilityLabel("Unterstrichen")
                Divider().frame(height: 16).padding(.horizontal, 6)
                Menu {
                    Button("Linksbündig") { formatting.send(.alignment(.left)) }
                    Button("Zentriert") { formatting.send(.alignment(.center)) }
                    Button("Rechtsbündig") { formatting.send(.alignment(.right)) }
                    Button("Blocksatz") { formatting.send(.alignment(.justified)) }
                } label: { Image(systemName: "text.alignleft") }
                    .menuStyle(.borderlessButton).help("Absatzausrichtung")
                Button { formatting.send(.bullet) } label: { Image(systemName: "list.bullet") }
                    .help("Aufzählungspunkt am Absatzanfang einfügen").accessibilityLabel("Aufzählungspunkt")
                Spacer()
                Button { formatting.send(.print) } label: { Image(systemName: "printer") }
                    .help("Drucken oder als PDF sichern").accessibilityLabel("Drucken oder als PDF sichern")
                Menu("\(zoom) %") {
                    ForEach([85, 100, 115, 130], id: \.self) { value in Button("\(value) %") { zoom = value } }
                }.menuStyle(.borderlessButton).fixedSize()
            }
            .buttonStyle(.borderless).font(.system(size: 12))
            .padding(.horizontal, 18).frame(height: 42)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            NativeDocumentEditor(text: $project.documentText, rtf: $project.documentRTF, formatting: formatting, zoom: CGFloat(zoom) / 100)
                .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 18)
                .background(Color(nsColor: .underPageBackgroundColor))
            HStack {
                Text("\(wordCount) Wörter")
                Spacer()
                if !project.audioAssets.isEmpty { Label("\(project.audioAssets.count) Audio", systemImage: "waveform") }
                Text("Gespeichert").foregroundStyle(.tertiary)
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, 20).frame(height: 28)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

struct NativeDocumentEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var rtf: Data?
    @ObservedObject var formatting: DocumentFormatting
    var zoom: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.borderType = .noBorder
        let editor = NSTextView(frame: scroll.contentView.bounds)
        editor.isRichText = true
        editor.usesAdaptiveColorMappingForDarkAppearance = true
        editor.importsGraphics = false
        editor.allowsImageEditing = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.allowsUndo = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 36, height: 38)
        editor.typingAttributes = DocumentContent.baseAttributes
        editor.textStorage?.setAttributedString(DocumentContent.attributed(text: text, rtf: rtf))
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel("Dokumentinhalt")
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text {
            let selection = editor.selectedRange()
            editor.textStorage?.setAttributedString(DocumentContent.attributed(text: text, rtf: rtf))
            editor.setSelectedRange(NSRange(location: min(selection.location, editor.string.utf16.count), length: 0))
        }
        if context.coordinator.lastZoom != zoom {
            editor.scaleUnitSquare(to: NSSize(width: zoom / context.coordinator.lastZoom, height: zoom / context.coordinator.lastZoom))
            context.coordinator.lastZoom = zoom
        }
        if let command = formatting.command, command.0 != context.coordinator.lastCommand {
            context.coordinator.lastCommand = command.0
            context.coordinator.apply(command.1, to: editor)
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeDocumentEditor
        var lastCommand: UUID?
        var lastZoom: CGFloat = 1
        init(_ parent: NativeDocumentEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            sync(editor)
        }
        func sync(_ editor: NSTextView) {
            parent.text = editor.string
            parent.rtf = DocumentContent.encode(editor.attributedString())
        }
        func apply(_ action: DocumentFormatting.Action, to editor: NSTextView) {
            editor.window?.makeFirstResponder(editor)
            if case .print = action {
                NSPrintOperation(view: editor).run()
                return
            }
            if case .bullet = action {
                let paragraph = (editor.string as NSString).paragraphRange(for: editor.selectedRange())
                editor.insertText("• ", replacementRange: NSRange(location: paragraph.location, length: 0))
                sync(editor)
                return
            }
            let isParagraphAction: Bool
            switch action {
            case .heading, .body, .alignment: isParagraphAction = true
            default: isParagraphAction = false
            }
            let range = isParagraphAction ? (editor.string as NSString).paragraphRange(for: editor.selectedRange()) : editor.selectedRange()
            let manager = NSFontManager.shared
            func changedFont(_ current: NSFont) -> NSFont {
                switch action {
                case .heading: return .systemFont(ofSize: 22, weight: .semibold)
                case .body: return .systemFont(ofSize: 15)
                case .fontFamily(let name):
                    let size = current.pointSize
                    if name == "system" { return NSFont.systemFont(ofSize: size) }
                    return NSFont(name: name, size: size) ?? current
                case .fontSize(let size): return NSFontManager.shared.convert(current, toSize: size)
                case .bold:
                    let trait: NSFontTraitMask = .boldFontMask
                    return manager.traits(of: current).contains(trait) ? manager.convert(current, toNotHaveTrait: trait) : manager.convert(current, toHaveTrait: trait)
                case .italic:
                    let trait: NSFontTraitMask = .italicFontMask
                    return manager.traits(of: current).contains(trait) ? manager.convert(current, toNotHaveTrait: trait) : manager.convert(current, toHaveTrait: trait)
                default: return current
                }
            }
            if range.length == 0 {
                applyToTypingAttributes(action, editor: editor, changedFont: changedFont)
            } else if let storage = editor.textStorage {
                let previous = storage.attributedSubstring(from: range)
                editor.undoManager?.registerUndo(withTarget: editor) { target in
                    target.textStorage?.replaceCharacters(in: range, with: previous)
                    target.didChangeText()
                }
                storage.beginEditing()
                switch action {
                case .alignment(let alignment):
                    let existing = range.location < storage.length
                        ? storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
                        : nil
                    let style = existing?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    style.alignment = alignment
                    storage.addAttribute(.paragraphStyle, value: style, range: range)
                case .underline:
                    let isUnderlined = (storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0) != 0
                    storage.addAttribute(.underlineStyle, value: isUnderlined ? 0 : NSUnderlineStyle.single.rawValue, range: range)
                default:
                    var runs: [(NSRange, NSFont)] = []
                    storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                        runs.append((subrange, changedFont(value as? NSFont ?? .systemFont(ofSize: 15))))
                    }
                    for (subrange, value) in runs { storage.addAttribute(.font, value: value, range: subrange) }
                }
                storage.endEditing()
                editor.didChangeText()
            }
            sync(editor)
        }

        private func applyToTypingAttributes(_ action: DocumentFormatting.Action, editor: NSTextView, changedFont: (NSFont) -> NSFont) {
            let currentFont = editor.typingAttributes[.font] as? NSFont ?? .systemFont(ofSize: 15)
            switch action {
            case .alignment(let alignment):
                let style = (editor.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                style.alignment = alignment
                editor.typingAttributes[.paragraphStyle] = style
            case .underline:
                let current = editor.typingAttributes[.underlineStyle] as? Int ?? 0
                editor.typingAttributes[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            default:
                editor.typingAttributes[.font] = changedFont(currentFont)
            }
        }
    }
}
