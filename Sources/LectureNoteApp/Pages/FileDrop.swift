import AppKit
import SwiftUI
import UniformTypeIdentifiers

func fileURL(fromDroppedItem item: Any?) -> URL? {
    if let url = item as? URL {
        return url.isFileURL ? url : nil
    }
    if let string = item as? String {
        return fileURL(fromDroppedString: string)
    }
    guard let data = item as? Data else { return nil }
    if let string = String(data: data, encoding: .utf8), let url = fileURL(fromDroppedString: string) {
        return url
    }
    guard let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else { return nil }
    return url
}

func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
    pasteboard.readObjects(forClasses: [NSURL.self], options: [
        .urlReadingFileURLsOnly: true,
    ]) as? [URL] ?? []
}

private func fileURL(fromDroppedString string: String) -> URL? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
    guard let url = URL(string: trimmed), url.isFileURL else { return nil }
    return url
}

@MainActor
struct FileDropBox: NSViewRepresentable {
    var isTargeted: (Bool) -> Void
    var onClick: () -> Void
    var onDrop: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> FileDropNSView {
        let view = FileDropNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: FileDropNSView, context: Context) {
        context.coordinator.isTargeted = isTargeted
        context.coordinator.onClick = onClick
        context.coordinator.onDrop = onDrop
        view.coordinator = context.coordinator
    }

    final class Coordinator {
        var isTargeted: (Bool) -> Void = { _ in }
        var onClick: () -> Void = {}
        var onDrop: ([URL]) -> Void = { _ in }
    }
}

@MainActor
final class FileDropNSView: NSView {
    var coordinator: FileDropBox.Coordinator?
    private var suppressClick = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        suppressClick = false
    }

    override func mouseUp(with event: NSEvent) {
        guard !suppressClick else {
            suppressClick = false
            return
        }
        coordinator?.onClick()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        suppressClick = true
        coordinator?.isTargeted(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        coordinator?.isTargeted(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        coordinator?.isTargeted(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        coordinator?.isTargeted(false)
        let urls = fileURLs(on: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        coordinator?.onDrop(urls)
        return true
    }
}
