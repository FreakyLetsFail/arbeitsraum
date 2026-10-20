import AppKit
import SwiftUI

struct ChatInput: NSViewRepresentable {
    @Binding var text: String
    var canSend: Bool
    var onSend: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let view = SendTextView(); view.isRichText = false; view.font = .systemFont(ofSize: 13); view.drawsBackground = false
        view.textContainerInset = NSSize(width: 2, height: 4); view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator; view.onSend = { if context.coordinator.parent.canSend { context.coordinator.parent.onSend() } }
        view.setAccessibilityLabel("Nachricht – Enter senden, Umschalt Enter neue Zeile")
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text { view.string = text }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInput
        init(_ parent: ChatInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let view = notification.object as? NSTextView { parent.text = view.string } }
    }
}
final class SendTextView: NSTextView {
    var onSend: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76) && !event.modifierFlags.contains(.shift) && !hasMarkedText() { onSend?(); return }
        super.keyDown(with: event)
    }
}
