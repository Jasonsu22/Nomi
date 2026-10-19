import SwiftUI

extension View {
    /// Pointing-hand cursor, so a control reads as clickable.
    func clickCursor(enabled: Bool = true) -> some View {
        modifier(ClickCursorModifier(enabled: enabled))
    }
}

private struct ClickCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    var enabled: Bool

    func body(content: Content) -> some View {
        content.pointerStyle(enabled && isEnabled ? .link : .default)
    }
}

extension PrimitiveButtonStyle where Configuration == PrimitiveButtonStyleConfiguration {
    func clicking() -> ClickCursorButtonStyle<Self> {
        ClickCursorButtonStyle(base: self)
    }
}

struct ClickCursorButtonStyle<Base: PrimitiveButtonStyle>: PrimitiveButtonStyle where Base.Configuration == PrimitiveButtonStyleConfiguration {
    var base: Base

    func makeBody(configuration: Configuration) -> some View {
        ClickCursorButtonBody(base: base, configuration: configuration)
    }
}

private struct ClickCursorButtonBody<Base: PrimitiveButtonStyle>: View where Base.Configuration == PrimitiveButtonStyleConfiguration {
    @Environment(\.isEnabled) private var isEnabled
    var base: Base
    var configuration: PrimitiveButtonStyleConfiguration

    var body: some View {
        base.makeBody(configuration: configuration)
            .pointerStyle(isEnabled ? .link : .default)
    }
}
