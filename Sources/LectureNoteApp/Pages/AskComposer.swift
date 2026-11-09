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
    /// ⌘Enter: the other way of sending while an answer is coming (queue or steer).
    var onSubmitAlternate: () -> Void = {}

    /// The box grows with the text, wrapped lines included, up to this many lines; past that it scrolls.
    static let maxLines = 8
    static let minHeight: CGFloat = 36

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? 240
        guard let textView = nsView.documentView as? NSTextView else { return CGSize(width: width, height: Self.minHeight) }
        return CGSize(width: width, height: Self.height(of: textView.string, width: width, in: textView))
    }

    /// The height that shows `text` wrapped at `width`, between one line and `maxLines`.
    static func height(of text: String, width: CGFloat, in textView: NSTextView) -> CGFloat {
        let font = textView.font ?? .systemFont(ofSize: 15)
        let inset = textView.textContainerInset
        let padding = textView.textContainer?.lineFragmentPadding ?? 5
        let lineHeight = textView.layoutManager?.defaultLineHeight(for: font) ?? ceil(font.ascender - font.descender + font.leading)
        // A trailing newline starts a line that string measuring would not count.
        let measured = text.hasSuffix("\n") || text.isEmpty ? text + " " : text
        let bounds = (measured as NSString).boundingRect(
            with: NSSize(width: max(width - inset.width * 2 - padding * 2, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let content = max(lineHeight, ceil(bounds.height))
        let cap = lineHeight * CGFloat(maxLines)
        return max(minHeight, min(content, cap) + inset.height * 2)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SubmitTextView()
        textView.registerForDraggedTypes([.fileURL, .png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier)])
        textView.delegate = context.coordinator
        textView.onPasteImages = { context.coordinator.parent.onPasteImages($0) }
        textView.onRemoveLastImage = { context.coordinator.parent.onRemoveLastImage() }
        textView.onDropImages = { context.coordinator.parent.onPasteImages($0) }
        textView.onSubmitAlternate = { context.coordinator.parent.onSubmitAlternate() }
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
        // Shown only once the text is taller than the box.
        scroll.hasVerticalScroller = true
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
        // Never while an input method is composing: the binding does not carry marked text, and
        // writing it back wiped Chinese input each time a streaming answer redrew the view.
        if !textView.hasMarkedText(), textView.string != text {
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
    var onSubmitAlternate: (() -> Void)?
    private var lastImagePasteChange = -1
    private var lastImagePasteTime: TimeInterval = 0

    /// ⌘Return arrives as a key equivalent, not as a newline command. Ignored while an input
    /// method is composing, so it never cuts a Chinese candidate short.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if isReturn, flags == .command, window?.firstResponder === self, !hasMarkedText(), let onSubmitAlternate {
            onSubmitAlternate()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

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
