// Draws the DMG window background at 1x and 2x.
// Run: swift Design/DMG/make-background.swift Design/DMG
// The layout matches scripts/build-dmg.sh: a 720 x 560 window with 120-point icons,
// Nomi at (200, 205), Applications at (520, 205), and "Open Settings" at (608, 408).
import AppKit

let size = CGSize(width: 720, height: 560)
let output = CommandLine.arguments.dropFirst().first ?? "."

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let ink = color(0x111418)
let secondary = color(0x5B6470)
let faint = color(0x8A929D)
let accent = color(0x004A77)
let leaf = color(0x20B68A)

func draw(_ text: String, font: NSFont, color: NSColor, at point: CGPoint, centered: Bool = false, width: CGFloat? = nil) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
    let string = text as NSString
    if centered {
        let measured = string.size(withAttributes: attributes).width
        string.draw(at: CGPoint(x: (size.width - measured) / 2, y: point.y), withAttributes: attributes)
    } else if let width {
        string.draw(in: CGRect(x: point.x, y: point.y, width: width, height: 60), withAttributes: attributes)
    } else {
        string.draw(at: point, withAttributes: attributes)
    }
}

/// A soft leaf, as a quiet echo of the logo.
func leafShape(center: CGPoint, length: CGFloat, angle: CGFloat, fill: NSColor) {
    let path = NSBezierPath()
    path.move(to: CGPoint(x: -length / 2, y: 0))
    path.curve(to: CGPoint(x: length / 2, y: 0), controlPoint1: CGPoint(x: -length / 4, y: -length / 2.6), controlPoint2: CGPoint(x: length / 4, y: -length / 2.6))
    path.curve(to: CGPoint(x: -length / 2, y: 0), controlPoint1: CGPoint(x: length / 4, y: length / 2.6), controlPoint2: CGPoint(x: -length / 4, y: length / 2.6))
    let transform = AffineTransform(translationByX: center.x, byY: center.y)
    var rotation = AffineTransform(rotationByDegrees: angle)
    rotation.append(transform)
    path.transform(using: rotation)
    fill.setFill()
    path.fill()
}

func render(scale: CGFloat) -> Data {
    let pixels = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    pixels.size = size
    NSGraphicsContext.saveGraphicsState()
    // y grows downward, like Finder's icon positions. The context is marked flipped so text is not drawn mirrored.
    let base = NSGraphicsContext(bitmapImageRep: pixels)!.cgContext
    base.translateBy(x: 0, y: size.height)
    base.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: base, flipped: true)

    // Light background with a few quiet leaves, like the reference's soft clouds.
    NSGradient(colors: [color(0xF7F9FC), color(0xEDF2F8)])!.draw(in: CGRect(origin: .zero, size: size), angle: 90)
    leafShape(center: CGPoint(x: 70, y: 70), length: 90, angle: -35, fill: leaf.withAlphaComponent(0.08))
    leafShape(center: CGPoint(x: 668, y: 92), length: 64, angle: 30, fill: leaf.withAlphaComponent(0.07))
    leafShape(center: CGPoint(x: 36, y: 250), length: 46, angle: 20, fill: accent.withAlphaComponent(0.05))
    leafShape(center: CGPoint(x: 690, y: 262), length: 52, angle: -25, fill: accent.withAlphaComponent(0.05))

    // Title and install line.
    draw("Nomi · 用母语听懂每一节课", font: .systemFont(ofSize: 30, weight: .semibold), color: ink, at: CGPoint(x: 0, y: 26), centered: true)
    draw("拖动 Nomi 到「应用程序」，即可完成安装", font: .systemFont(ofSize: 16, weight: .regular), color: secondary, at: CGPoint(x: 0, y: 74), centered: true)
    draw("Drag Nomi into Applications to install", font: .systemFont(ofSize: 12.5, weight: .regular), color: faint, at: CGPoint(x: 0, y: 98), centered: true)

    // Soft arrow between the two icons.
    let shaft = CGRect(x: 292, y: 197, width: 112, height: 16)
    NSGradient(colors: [color(0xC9D4E2, 0.15), color(0xA9B9CE, 0.95)])!.draw(in: NSBezierPath(rect: shaft), angle: 0)
    let head = NSBezierPath()
    head.move(to: CGPoint(x: 402, y: 183))
    head.line(to: CGPoint(x: 432, y: 205))
    head.line(to: CGPoint(x: 402, y: 227))
    head.close()
    color(0xA9B9CE).setFill()
    head.fill()

    // First-launch panel with the steps printed on the window.
    let panel = CGRect(x: 32, y: 318, width: 656, height: 220)
    NSColor.white.withAlphaComponent(0.8).setFill()
    NSBezierPath(roundedRect: panel, xRadius: 20, yRadius: 20).fill()
    color(0xD5DCE6).setStroke()
    let border = NSBezierPath(roundedRect: panel.insetBy(dx: 0.5, dy: 0.5), xRadius: 20, yRadius: 20)
    border.lineWidth = 1
    border.stroke()

    let pill = CGRect(x: 56, y: 336, width: 172, height: 24)
    accent.withAlphaComponent(0.1).setFill()
    NSBezierPath(roundedRect: pill, xRadius: 12, yRadius: 12).fill()
    draw("第一次打开 · First launch", font: .systemFont(ofSize: 12, weight: .semibold), color: accent, at: CGPoint(x: 68, y: 340))

    let steps = [
        ("在「应用程序」里打开 Nomi，看到「无法验证」提示时点「完成」。", "Open Nomi from Applications. When macOS can't verify it, click Done."),
        ("双击右边的「打开安全设置」，再点页面里的按钮。", "Double-click Open Settings on the right, then click the button on that page."),
        ("找到 Nomi，点「仍要打开」并输入密码。以后就能直接打开。", "Find Nomi, click Open Anyway and enter your password. Just this once."),
    ]
    for (index, step) in steps.enumerated() {
        let top = 374 + CGFloat(index) * 52
        let circle = CGRect(x: 56, y: top, width: 24, height: 24)
        accent.setFill()
        NSBezierPath(ovalIn: circle).fill()
        let number = "\(index + 1)" as NSString
        let numberFont = NSFont.systemFont(ofSize: 13, weight: .bold)
        let numberSize = number.size(withAttributes: [.font: numberFont])
        number.draw(at: CGPoint(x: circle.midX - numberSize.width / 2, y: circle.midY - numberSize.height / 2), withAttributes: [.font: numberFont, .foregroundColor: NSColor.white])
        draw(step.0, font: .systemFont(ofSize: 13.5, weight: .medium), color: ink, at: CGPoint(x: 92, y: top + 1), width: 430)
        draw(step.1, font: .systemFont(ofSize: 11.5, weight: .regular), color: secondary, at: CGPoint(x: 92, y: top + 22), width: 430)
    }

    // A small pointer from step 2 to the Open Settings file.
    accent.withAlphaComponent(0.55).setStroke()
    let pointer = NSBezierPath()
    pointer.lineWidth = 2
    pointer.lineCapStyle = .round
    pointer.setLineDash([1, 6], count: 2, phase: 0)
    pointer.move(to: CGPoint(x: 530, y: 408))
    pointer.line(to: CGPoint(x: 548, y: 408))
    pointer.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return pixels.representation(using: .png, properties: [:])!
}

try render(scale: 1).write(to: URL(fileURLWithPath: output).appendingPathComponent("background.png"))
try render(scale: 2).write(to: URL(fileURLWithPath: output).appendingPathComponent("background@2x.png"))
print("wrote background.png and background@2x.png to \(output)")
