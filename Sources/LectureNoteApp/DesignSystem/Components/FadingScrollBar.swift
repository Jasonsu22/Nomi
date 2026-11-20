import SwiftUI

/// A scroll bar drawn by Nomi, for long scroll views like the transcript. The system bar in a
/// SwiftUI scroll view can't be brought back on hover and vanished for good once scrolling stopped.
///
/// It fades in when scrolling starts or when the pointer reaches the right edge, stays while the
/// pointer is on it or it is being dragged, and fades out a moment after both end. Dragging the knob
/// scrolls; clicking the track jumps there.
struct FadingScrollBar: ViewModifier {
    /// How close to the right edge the pointer must be to bring the bar in.
    static let hoverWidth: CGFloat = 22
    /// How long the bar stays after the last scroll or hover.
    static let linger: Duration = .milliseconds(1200)

    struct Metrics: Equatable {
        var offset: CGFloat = 0
        var content: CGFloat = 1
        var visible: CGFloat = 1
        var width: CGFloat = 0

        var scrollable: Bool { content > visible + 1 }
        var range: CGFloat { max(1, content - visible) }

        func knobHeight(track: CGFloat) -> CGFloat {
            min(track, max(32, track * visible / max(content, 1)))
        }

        func knobTop(track: CGFloat) -> CGFloat {
            (track - knobHeight(track: track)) * min(1, max(0, offset / range))
        }

        /// The scroll offset that puts the knob's top at `top`.
        func offset(forKnobTop top: CGFloat, track: CGFloat) -> CGFloat {
            let room = max(1, track - knobHeight(track: track))
            return min(range, max(0, top / room * range))
        }
    }

    /// A scroll position the view already drives (the chat's "jump to latest"); otherwise its own.
    var external: Binding<ScrollPosition>? = nil

    @State private var metrics = Metrics()
    @State private var ownPosition = ScrollPosition()
    @State private var shown = false
    @State private var nearEdge = false
    @State private var dragging = false
    @State private var dragStartTop: CGFloat?
    @State private var hide: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let inset: CGFloat = 3

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.hidden, axes: .vertical)
            .scrollPosition(external ?? $ownPosition)
            .onScrollGeometryChange(for: Metrics.self) { geometry in
                Metrics(
                    offset: geometry.contentOffset.y + geometry.contentInsets.top,
                    content: geometry.contentSize.height,
                    visible: geometry.containerSize.height,
                    width: geometry.containerSize.width
                )
            } action: { _, new in
                metrics = new
            }
            .onScrollPhaseChange { _, phase in
                phase == .idle ? fadeLater() : show()
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let near = metrics.width > 0 && point.x >= metrics.width - Self.hoverWidth
                    guard near != nearEdge else { return }
                    nearEdge = near
                    near ? show() : fadeLater()
                case .ended:
                    if nearEdge { nearEdge = false; fadeLater() }
                }
            }
            .overlay(alignment: .topTrailing) {
                if metrics.scrollable { bar }
            }
    }

    private var bar: some View {
        let track = max(0, metrics.visible - inset * 2)
        let wide = nearEdge || dragging
        let knob = metrics.knobHeight(track: track)
        let top = metrics.knobTop(track: track)
        return ZStack(alignment: .topTrailing) {
            Capsule()
                .fill(Color.primary.opacity(wide ? 0.06 : 0))
                .frame(width: wide ? 11 : 7, height: track)
            Capsule()
                .fill(Color.primary.opacity(dragging ? 0.5 : wide ? 0.42 : 0.32))
                .frame(width: wide ? 8 : 5, height: knob)
                .padding(.trailing, wide ? 1.5 : 1)
                .offset(y: top)
        }
        .frame(width: Self.hoverWidth, height: track, alignment: .topTrailing)
        // The whole edge strip takes the pointer, not just the thin bar: press on the knob and drag
        // to scroll, or press elsewhere on the track to jump there and keep dragging.
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStartTop == nil {
                        let onKnob = value.startLocation.y >= top && value.startLocation.y <= top + knob
                        dragStartTop = onKnob ? top : value.startLocation.y - knob / 2
                        dragging = true
                        show()
                    }
                    jump(toKnobTop: (dragStartTop ?? 0) + value.translation.height, track: track)
                }
                .onEnded { _ in
                    dragStartTop = nil
                    dragging = false
                    fadeLater()
                }
        )
        .padding(.top, inset)
        .padding(.trailing, 2)
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: wide)
        .accessibilityHidden(true)
    }

    private func jump(toKnobTop top: CGFloat, track: CGFloat) {
        (external ?? $ownPosition).wrappedValue.scrollTo(y: metrics.offset(forKnobTop: top, track: track))
    }

    private func show() {
        hide?.cancel()
        hide = nil
        guard !shown else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { shown = true }
    }

    /// Fades out after a pause, unless the pointer is still at the edge or the knob is held.
    private func fadeLater() {
        hide?.cancel()
        hide = Task { @MainActor in
            try? await Task.sleep(for: Self.linger)
            guard !Task.isCancelled, !nearEdge, !dragging else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) { shown = false }
        }
    }
}

extension View {
    /// Nomi's own fading scroll bar; see `FadingScrollBar`.
    func fadingScrollBar() -> some View { modifier(FadingScrollBar()) }

    /// The same, sharing a scroll position the view already uses.
    func fadingScrollBar(position: Binding<ScrollPosition>) -> some View { modifier(FadingScrollBar(external: position)) }
}
