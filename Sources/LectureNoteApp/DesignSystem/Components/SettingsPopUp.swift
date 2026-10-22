import AppKit
import SwiftUI

/// A pop-up menu drawn like the ones in macOS System Settings: the value next to a chevron in a
/// small round well, a rounded highlight only while the pointer is over it, and the native menu
/// opening over the control with a checkmark on the current item.
struct SettingsPopUp<Value: Hashable>: NSViewRepresentable {
    @Binding var selection: Value
    var options: [(value: Value, title: String)]
    var fontSize: CGFloat = 13
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SettingsPopUpButton {
        let button = SettingsPopUpButton()
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        return button
    }

    func updateNSView(_ button: SettingsPopUpButton, context: Context) {
        let options = options
        let selection = $selection
        context.coordinator.select = { index in
            guard options.indices.contains(index) else { return }
            selection.wrappedValue = options[index].value
        }
        let titles = options.map(\.title)
        if button.itemArray.map(\.title) != titles {
            // Built item by item: addItems(withTitles:) drops repeated titles.
            button.removeAllItems()
            for title in titles { button.menu?.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: "")) }
        }
        let index = options.firstIndex { $0.value == self.selection } ?? -1
        if button.indexOfSelectedItem != index { button.selectItem(at: index) }
        button.font = .systemFont(ofSize: fontSize)
        button.isEnabled = isEnabled
        button.invalidateIntrinsicContentSize()
        button.needsDisplay = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SettingsPopUpButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    final class Coordinator: NSObject {
        var select: (Int) -> Void = { _ in }
        @objc func changed(_ sender: NSPopUpButton) { select(sender.indexOfSelectedItem) }
    }
}

final class SettingsPopUpButton: NSPopUpButton {
    private static let inset: CGFloat = 8, gap: CGFloat = 6, well: CGFloat = 20, edge: CGFloat = 3, height: CGFloat = 26
    private var hovering = false { didSet { if hovering != oldValue { needsDisplay = true } } }
    private var tracking: NSTrackingArea?

    init() {
        super.init(frame: .zero, pullsDown: false)
        isBordered = false
        (cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: font ?? .systemFont(ofSize: 13), .foregroundColor: isEnabled ? NSColor.labelColor : NSColor.tertiaryLabelColor]
    }

    override var intrinsicContentSize: NSSize {
        let title = (selectedItem?.title ?? "") as NSString
        let width = ceil(title.size(withAttributes: attributes).width)
        return NSSize(width: Self.inset + width + Self.gap + Self.well + Self.edge, height: Self.height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)  // returns once the menu closes
        guard let window else { return }
        hovering = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    override func draw(_ dirtyRect: NSRect) {
        // One gray for the chevron well and the hover box, so on hover the well blends into the box.
        let pressed = cell?.isHighlighted == true
        let fill = NSColor.labelColor.withAlphaComponent(pressed ? 0.14 : 0.08)
        let wellRect = NSRect(x: bounds.maxX - Self.edge - Self.well, y: (bounds.height - Self.well) / 2, width: Self.well, height: Self.well)
        if isEnabled, hovering || pressed {
            fill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        } else {
            NSColor.labelColor.withAlphaComponent(isEnabled ? 0.08 : 0.04).setFill()
            NSBezierPath(ovalIn: wellRect).fill()
        }
        let title = (selectedItem?.title ?? "") as NSString
        let size = title.size(withAttributes: attributes)
        title.draw(at: NSPoint(x: Self.inset, y: (bounds.height - size.height) / 2), withAttributes: attributes)

        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            .applying(.init(paletteColors: [isEnabled ? .labelColor : .tertiaryLabelColor]))
        if let chevron = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let s = chevron.size
            chevron.draw(in: NSRect(x: wellRect.midX - s.width / 2, y: wellRect.midY - s.height / 2, width: s.width, height: s.height))
        }
    }
}

/// The same look for a button that opens its own popover instead of a menu.
struct SettingsPopUpLabel<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            content
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 20, height: 20)
                .background(Color.primary.opacity(hovering ? 0 : 0.08), in: Circle())
        }
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
