import AppKit
import SwiftUI

struct BrandLogo: View {
    var side: CGFloat

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .clipShape(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous))
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private static let image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "AppLogo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}
