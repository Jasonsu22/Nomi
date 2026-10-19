import AppKit
import SwiftUI

struct ProviderLogo: View {
    var file: String?
    var side: CGFloat = 16

    var body: some View {
        if let image = ProviderLogo.image(named: file, height: side) {
            let square = image.size.height > 0 && abs(image.size.width / image.size.height - 1) < 0.08
            let radius = image.size.height * 0.22
            Image(nsImage: image)
                .interpolation(.high)
                .clipShape(RoundedRectangle(cornerRadius: square ? radius : 0, style: .continuous))
                .overlay {
                    if square {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(AppColor.separator, lineWidth: 0.5)
                    }
                }
                .accessibilityHidden(true)
        } else {
            Image(systemName: "link")
                .font(.system(size: side * 0.55, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: side, height: side)
                .accessibilityHidden(true)
        }
    }

    static func image(named file: String?) -> NSImage? {
        image(named: file, height: 16)
    }

    static func image(named file: String?, height: CGFloat) -> NSImage? {
        guard let file, let source = load(file) else { return nil }
        let key = "\(file)@\(height)"
        if let cached = fitted[key] { return cached }
        let native = source.size
        guard native.width > 0, native.height > 0 else { return source }
        let scale = min((height * 4.6) / native.width, height / native.height)
        guard let copy = source.copy() as? NSImage else { return source }
        copy.size = NSSize(width: native.width * scale, height: native.height * scale)
        copy.isTemplate = false
        fitted[key] = copy
        return copy
    }

    private static func load(_ file: String) -> NSImage? {
        if let cached = cache[file] { return cached }
        for ext in ["svg", "png"] {
            let url = Bundle.module.url(forResource: file, withExtension: ext, subdirectory: "ProviderLogos")
                ?? Bundle.module.url(forResource: file, withExtension: ext)
            guard let url, let image = NSImage(contentsOf: url) else { continue }
            image.isTemplate = false
            cache[file] = image
            return image
        }
        return nil
    }

    private static var cache: [String: NSImage] = [:]
    private static var fitted: [String: NSImage] = [:]
}
