import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AskComposerField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focused: Bool
    var onSubmit: () -> Void
    var onPasteImages: (NSPasteboard) -> Bool
    var onRemoveLastImage: () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 240, height: proposal.height ?? 36)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SubmitTextView()
        textView.registerForDraggedTypes([.fileURL, .png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier)])
        textView.delegate = context.coordinator
        textView.onPasteImages = { context.coordinator.parent.onPasteImages($0) }
        textView.onRemoveLastImage = { context.coordinator.parent.onRemoveLastImage() }
        textView.onDropImages = { context.coordinator.parent.onPasteImages($0) }
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.focusRingType = .none
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 2, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.focusRingType = .none
        scroll.documentView = textView
        scroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? SubmitTextView else { return }
        textView.onPasteImages = { context.coordinator.parent.onPasteImages($0) }
        textView.onRemoveLastImage = { context.coordinator.parent.onRemoveLastImage() }
        textView.onDropImages = { context.coordinator.parent.onPasteImages($0) }
        if textView.placeholder != placeholder {
            textView.placeholder = placeholder
            textView.needsDisplay = true
        }
        if textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }
        if focused, scroll.window?.firstResponder !== textView {
            scroll.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AskComposerField
        init(_ parent: AskComposerField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            textView.needsDisplay = true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.deleteBackward(_:)), textView.string.isEmpty {
                return parent.onRemoveLastImage()
            }
            let newline = commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
            guard newline, !textView.hasMarkedText() else { return false }
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return false }
            parent.onSubmit()
            return true
        }
    }
}

final class SubmitTextView: NSTextView {
    var placeholder = ""
    var onPasteImages: ((NSPasteboard) -> Bool)?
    var onDropImages: ((NSPasteboard) -> Bool)?
    var onRemoveLastImage: (() -> Bool)?
    private var lastImagePasteChange = -1
    private var lastImagePasteTime: TimeInterval = 0

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(paste(_:)), ChatImages.containsImage(NSPasteboard.general) {
            return true
        }
        return super.validateMenuItem(menuItem)
    }

    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        if ChatImages.containsImage(board) {
            let now = ProcessInfo.processInfo.systemUptime
            if board.changeCount == lastImagePasteChange, now - lastImagePasteTime < 0.2 {
                return
            }
            lastImagePasteChange = board.changeCount
            lastImagePasteTime = now
        }
        if onPasteImages?(board) == true { return }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        ChatImages.containsImage(sender.draggingPasteboard) ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onDropImages?(sender.draggingPasteboard) == true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: 15),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        placeholder.draw(at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height), withAttributes: attributes)
    }
}
