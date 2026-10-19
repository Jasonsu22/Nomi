import AppKit
import SwiftMath

/// Draws a LaTeX formula into an image so it can sit in the answer text.
@MainActor
enum MathRaster {
    struct Result {
        var image: NSImage
        var descent: CGFloat
    }

    private final class Box: NSObject {
        let result: Result
        init(_ result: Result) { self.result = result }
    }

    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 200
        return cache
    }()

    static func raster(latex: String, fontSize: CGFloat, color: NSColor, display: Bool, maxWidth: CGFloat) -> Result? {
        let prepared = prepare(latex)
        guard !prepared.latex.isEmpty else { return nil }
        let key = "\(display)|\(fontSize)|\(colorKey(color))|\(Int(maxWidth.rounded()))|\(prepared.boxed)|\(prepared.latex)" as NSString
        if let hit = cache.object(forKey: key) { return hit.result }
        guard let result = draw(prepared, fontSize: fontSize, color: color, display: display, maxWidth: maxWidth) else { return nil }
        cache.setObject(Box(result), forKey: key)
        return result
    }

    private static func prepare(_ latex: String) -> (latex: String, boxed: Bool) {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrapped = boxedWrap(trimmed)
        let body = stripBoxed(wrapped ?? trimmed)
            .replacingOccurrences(of: "\\dfrac", with: "\\frac")
            .replacingOccurrences(of: "\\tfrac", with: "\\frac")
        return (body, wrapped != nil)
    }

    /// The inside of `\boxed{...}` when that command wraps the whole formula.
    private static func boxedWrap(_ latex: String) -> String? {
        let token = "\\boxed"
        guard latex.hasPrefix(token) else { return nil }
        let brace = latex.index(latex.startIndex, offsetBy: token.count)
        guard brace < latex.endIndex, latex[brace] == "{", let inner = braceContent(latex, open: brace) else { return nil }
        guard inner.next == latex.endIndex else { return nil }
        return inner.body
    }

    private static func stripBoxed(_ latex: String) -> String {
        var result = ""
        var index = latex.startIndex
        let token = "\\boxed"
        while index < latex.endIndex {
            if latex[index...].hasPrefix(token) {
                let brace = latex.index(index, offsetBy: token.count)
                if brace < latex.endIndex, latex[brace] == "{", let inner = braceContent(latex, open: brace) {
                    result += stripBoxed(inner.body)
                    index = inner.next
                    continue
                }
            }
            result.append(latex[index])
            index = latex.index(after: index)
        }
        return result
    }

    private static func braceContent(_ source: String, open: String.Index) -> (body: String, next: String.Index)? {
        guard source[open] == "{" else { return nil }
        var depth = 0
        var index = open
        while index < source.endIndex {
            if source[index] == "\\" {
                let skipped = source.index(after: index)
                guard skipped < source.endIndex else { return nil }
                index = source.index(after: skipped)
                continue
            }
            if source[index] == "{" { depth += 1 }
            if source[index] == "}" {
                depth -= 1
                if depth == 0 {
                    return (String(source[source.index(after: open)..<index]), source.index(after: index))
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static func draw(
        _ prepared: (latex: String, boxed: Bool),
        fontSize: CGFloat,
        color: NSColor,
        display: Bool,
        maxWidth: CGFloat
    ) -> Result? {
        guard var laid = layout(prepared.latex, fontSize: fontSize, color: color, display: display) else { return nil }
        let extra: CGFloat = prepared.boxed ? 12 : 4
        if maxWidth > 32, laid.size.width + extra > maxWidth {
            let scaled = max(fontSize * maxWidth / laid.size.width, 10)
            guard let again = layout(prepared.latex, fontSize: scaled, color: color, display: display) else { return nil }
            laid = again
        }
        let padX: CGFloat = prepared.boxed ? 6 : (display ? 0 : 2)
        let padY: CGFloat = prepared.boxed ? 5 : 0
        let size = NSSize(width: ceil(laid.size.width + padX * 2), height: ceil(laid.size.height + padY * 2))
        let image = NSImage(size: size)
        image.lockFocus()
        laid.image.draw(at: NSPoint(x: padX, y: padY), from: .zero, operation: .sourceOver, fraction: 1)
        if prepared.boxed {
            color.setStroke()
            let path = NSBezierPath(rect: NSRect(x: 0.5, y: 0.5, width: max(size.width - 1, 1), height: max(size.height - 1, 1)))
            path.lineWidth = 1
            path.stroke()
        }
        image.unlockFocus()
        return Result(image: image, descent: laid.descent + padY)
    }

    private struct Laid {
        var image: NSImage
        var size: NSSize
        var descent: CGFloat
    }

    private static func layout(_ latex: String, fontSize: CGFloat, color: NSColor, display: Bool) -> Laid? {
        let label = MTMathUILabel()
        label.displayErrorInline = false
        label.labelMode = display ? .display : .text
        label.textAlignment = .left
        label.fontSize = fontSize
        label.textColor = color
        label.latex = latex
        guard label.error == nil else { return nil }
        var fit = label.fittingSize
        if fit.width < 1 || fit.height < 1 { fit = label.intrinsicContentSize }
        guard fit.width > 1, fit.height > 1, fit.width < 5000, fit.height < 2000 else { return nil }
        label.frame = NSRect(origin: .zero, size: fit)
        label.layout()
        guard let list = label.displayList, list.width > 0 else { return nil }
        let image = NSImage(size: fit)
        image.lockFocus()
        label.draw(NSRect(origin: .zero, size: fit))
        image.unlockFocus()
        return Laid(image: image, size: fit, descent: list.descent)
    }

    private static func colorKey(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return String(format: "%.3f-%.3f-%.3f", rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    }
}
