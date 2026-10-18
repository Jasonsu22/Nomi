import SwiftUI

struct HeroFrame: ViewModifier {
    var id: UUID
    var namespace: Namespace.ID
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}
