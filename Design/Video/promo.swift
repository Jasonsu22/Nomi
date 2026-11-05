// Renders the Nomi promo video, 1920 x 1080 at 30 fps, as raw BGRA frames on stdout. Everything on screen is drawn here,
// including the product demos: their sizes, colors and type come from the app's own SwiftUI views (dark appearance).
// Build: swiftc -O Design/Video/promo.swift -o build/promo-render
// Stills: build/promo-render --stills 4.5,8.5 build/video2/frames  (PNG per time, for review)
//
// Timeline, one continuous take inside the app from 10 to 63:
//   0-6    the problem            6-10   the voice becomes the leaf, and the leaf lands in the app
//   10-25  live transcription     25-39  the teacher's questions, answered
//   39-52  ask about anything     52-63  interactive demos        63-70  end card
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

let W: CGFloat = 1920, H: CGFloat = 1080
let fps = 30.0, frameCount = 2100, subframes = 4, shutter = 0.5  // motion blur: 4 samples across half a frame
let full = CGRect(x: 0, y: 0, width: W, height: H)
let center = CGPoint(x: W / 2, y: H / 2)

// MARK: - Math and easing

func clamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(max(x, a), b) }
func prog(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
func mix(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint { CGPoint(x: mix(a.x, b.x, t), y: mix(a.y, b.y, t)) }
func outCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
func inCubic(_ x: Double) -> Double { x * x * x }
func inOutCubic(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
func outExpo(_ x: Double) -> Double { x >= 1 ? 1 : 1 - pow(2, -10 * x) }
func inExpo(_ x: Double) -> Double { x <= 0 ? 0 : pow(2, 10 * x - 10) }
func outBack(_ x: Double, _ s: Double = 1.9) -> Double { 1 + (s + 1) * pow(x - 1, 3) + s * pow(x - 1, 2) }
/// Settles at 1 with a damped overshoot.
func spring(_ x: Double) -> Double { x <= 0 ? 0 : (x >= 1 ? 1 : 1 - exp(-6.5 * x) * cos(11 * x)) }
func hash(_ i: Int, _ salt: Int = 0) -> Double {
    var h = UInt64(truncatingIfNeeded: i &* 73_856_093 ^ (salt &+ 17) &* 19_349_663)
    h ^= h >> 33; h = h &* 0xff51afd7ed558ccd; h ^= h >> 33; h = h &* 0xc4ceb9fe1a85ec53; h ^= h >> 33
    return Double(h % 1_000_000) / 1_000_000
}

// MARK: - Palette

let navy0: UInt32 = 0x05121E, navy1: UInt32 = 0x0B2438, blue: UInt32 = 0x004A77, sky: UInt32 = 0x7CC4F2
let ice: UInt32 = 0xC2E8FF, leaf: UInt32 = 0x20B68A, mint: UInt32 = 0x8EDDBA, paper: UInt32 = 0xF4F7FB
let paper2: UInt32 = 0xE4ECF5, ink: UInt32 = 0x111418, gray: UInt32 = 0x8A929D, draft: UInt32 = 0xA9B1BC
let red: UInt32 = 0xE5484D, sun: UInt32 = 0xFFC857, white: UInt32 = 0xFFFFFF

func rgb(_ hex: UInt32, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func blend(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
    func ch(_ s: UInt32) -> Double { Double(s & 0xFF) }
    let r = UInt32(mix(ch(a >> 16), ch(b >> 16), t)), g = UInt32(mix(ch(a >> 8), ch(b >> 8), t)), bl = UInt32(mix(ch(a), ch(b), t))
    return r << 16 | g << 8 | bl
}

// MARK: - Canvas

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
func makeContext() -> CGContext {
    CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: Int(W) * 4, space: space, bitmapInfo: bitmapInfo)!
}
let c = makeContext()
c.translateBy(x: 0, y: H)
c.scaleBy(x: 1, y: -1)  // y grows downward, like a screen
c.interpolationQuality = .high
let accumulator = makeContext()

func state(_ body: () -> Void) { c.saveGState(); body(); c.restoreGState() }
/// Draws `body` as one group at the given opacity.
func group(_ alpha: Double, _ body: () -> Void) {
    guard alpha > 0.002 else { return }
    if alpha >= 0.999 { state(body); return }
    c.saveGState(); c.setAlpha(alpha); c.beginTransparencyLayer(auxiliaryInfo: nil)
    body()
    c.endTransparencyLayer(); c.restoreGState()
}
func transform(at point: CGPoint, scale: Double = 1, rotate degrees: Double = 0) {
    c.translateBy(x: point.x, y: point.y)
    if degrees != 0 { c.rotate(by: degrees * .pi / 180) }
    if scale != 1 { c.scaleBy(x: scale, y: scale) }
    c.translateBy(x: -point.x, y: -point.y)
}
func fill(_ color: UInt32, _ alpha: Double = 1, _ rect: CGRect = full) { c.setFillColor(rgb(color, alpha)); c.fill(rect) }
func roundRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    let k = min(radius, r.width / 2, r.height / 2)
    return CGPath(roundedRect: r, cornerWidth: max(k, 0), cornerHeight: max(k, 0), transform: nil)
}
func fillPath(_ path: CGPath, _ color: UInt32, _ alpha: Double = 1) { c.addPath(path); c.setFillColor(rgb(color, alpha)); c.fillPath() }
func strokePath(_ path: CGPath, _ color: UInt32, _ alpha: Double = 1, width: CGFloat = 2) {
    c.addPath(path); c.setStrokeColor(rgb(color, alpha)); c.setLineWidth(width); c.setLineCap(.round); c.strokePath()
}
func circle(_ p: CGPoint, _ r: CGFloat, _ color: UInt32, _ alpha: Double = 1) {
    guard r > 0 else { return }
    c.setFillColor(rgb(color, alpha)); c.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
}
func ring(_ p: CGPoint, _ r: CGFloat, _ color: UInt32, _ alpha: Double, width: CGFloat) {
    guard r > 0, width > 0.05 else { return }
    c.setStrokeColor(rgb(color, alpha)); c.setLineWidth(width)
    c.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
}
func line(_ a: CGPoint, _ b: CGPoint, _ color: UInt32, _ alpha: Double, width: CGFloat) {
    c.setStrokeColor(rgb(color, alpha)); c.setLineWidth(width); c.setLineCap(.round)
    c.strokeLineSegments(between: [a, b])
}
func glow(_ p: CGPoint, _ radius: CGFloat, _ color: UInt32, _ alpha: Double) {
    guard alpha > 0.002, radius > 0 else { return }
    let g = CGGradient(colorsSpace: space, colors: [rgb(color, alpha), rgb(color, alpha * 0.35), rgb(color, 0)] as CFArray, locations: [0, 0.45, 1])!
    c.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
}
func verticalGradient(_ top: UInt32, _ bottom: UInt32, _ rect: CGRect = full) {
    let g = CGGradient(colorsSpace: space, colors: [rgb(top), rgb(bottom)] as CFArray, locations: [0, 1])!
    state { c.clip(to: rect); c.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: []) }
}
func radialBackground(_ inner: UInt32, _ outer: UInt32, at p: CGPoint = center, radius: CGFloat = 1300) {
    fill(outer)
    let g = CGGradient(colorsSpace: space, colors: [rgb(inner), rgb(outer)] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [.drawsAfterEndLocation])
}
func shadow(blur: CGFloat, y: CGFloat, alpha: Double) {
    c.setShadow(offset: CGSize(width: 0, height: -y), blur: blur, color: rgb(0x0A1020, alpha))  // shadows ignore the flip
}
func clipPolygon(_ points: [CGPoint]) {
    let p = CGMutablePath(); p.addLines(between: points); p.closeSubpath(); c.addPath(p); c.clip()
}

// MARK: - Text

var fonts: [String: CTFont] = [:]
func font(_ size: CGFloat, _ weight: NSFont.Weight, rounded: Bool = false) -> CTFont {
    let key = "\(size)|\(weight.rawValue)|\(rounded)"
    if let f = fonts[key] { return f }
    var f = NSFont.systemFont(ofSize: size, weight: weight)
    if rounded, let d = f.fontDescriptor.withDesign(.rounded), let r = NSFont(descriptor: d, size: size) { f = r }
    fonts[key] = f
    return f as CTFont
}
func attributed(_ s: String, _ f: CTFont, tracking: CGFloat = 0, lineSpacing: CGFloat = 0) -> NSAttributedString {
    var attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): f,
        NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
    ]
    if tracking != 0 { attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = tracking }
    if lineSpacing != 0 {
        var spacing = lineSpacing
        let style = withUnsafeBytes(of: &spacing) { raw in
            var setting = CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: raw.baseAddress!)
            return CTParagraphStyleCreate(&setting, 1)
        }
        attributes[NSAttributedString.Key(kCTParagraphStyleAttributeName as String)] = style
    }
    return NSAttributedString(string: s, attributes: attributes)
}
func makeLine(_ s: String, _ f: CTFont, tracking: CGFloat = 0) -> CTLine { CTLineCreateWithAttributedString(attributed(s, f, tracking: tracking)) }
func width(_ l: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil)) }
func measure(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, rounded: Bool = false, tracking: CGFloat = 0) -> CGFloat {
    width(makeLine(s, font(size, weight, rounded: rounded), tracking: tracking))
}

/// Draws one line with its baseline at y. anchor 0 is left, 0.5 center, 1 right.
func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight = .regular, color: UInt32, alpha: Double = 1,
          anchor: CGFloat = 0, tracking: CGFloat = 0, rounded: Bool = false, scale: Double = 1) {
    guard alpha > 0.002, !s.isEmpty else { return }
    let l = makeLine(s, font(size, weight, rounded: rounded), tracking: tracking)
    let w = width(l)
    state {
        c.translateBy(x: x, y: y)
        c.scaleBy(x: scale, y: -scale)
        c.textPosition = CGPoint(x: -w * anchor, y: 0)
        c.setFillColor(rgb(color, alpha))
        CTLineDraw(l, c)
    }
}

struct Piece { let text: String; let offset: CGFloat; let width: CGFloat }
/// Splits a line into words (or characters) with their positions inside the whole line.
func pieces(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, rounded: Bool = false, tracking: CGFloat = 0, characters: Bool = false) -> ([Piece], CGFloat) {
    let f = font(size, weight, rounded: rounded)
    let whole = makeLine(s, f, tracking: tracking)
    var result: [Piece] = []
    var index = 0
    let units: [String] = characters ? s.map { String($0) } : s.components(separatedBy: " ")
    for unit in units {
        let offset = CTLineGetOffsetForStringIndex(whole, index, nil)
        result.append(Piece(text: unit, offset: offset, width: width(makeLine(unit, f, tracking: tracking))))
        index += unit.utf16.count + (characters ? 0 : 1)
    }
    return (result, width(whole))
}
struct Look { var dx: CGFloat = 0; var dy: CGFloat = 0; var scale: Double = 1; var alpha: Double = 1; var color: UInt32 = white }
/// Draws a line piece by piece so each word or letter can move on its own.
func kinetic(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight, anchor: CGFloat = 0, rounded: Bool = false,
             tracking: CGFloat = 0, characters: Bool = false, look: (Int, Piece) -> Look) {
    let (parts, total) = pieces(s, size, weight, rounded: rounded, tracking: tracking, characters: characters)
    let left = x - total * anchor
    for (i, p) in parts.enumerated() {
        let l = look(i, p)
        text(p.text, left + p.offset + p.width / 2 + l.dx, y + l.dy, size, weight, color: l.color, alpha: l.alpha, anchor: 0.5,
             tracking: tracking, rounded: rounded, scale: l.scale)
    }
}
/// Wrapped text inside a rectangle, showing only the first `visible` characters.
func paragraph(_ s: String, _ rect: CGRect, _ size: CGFloat, _ weight: NSFont.Weight, color: UInt32, alpha: Double = 1, visible: Int? = nil, lineSpacing: CGFloat = 6) {
    let shown = visible.map { String(s.prefix($0)) } ?? s
    guard !shown.isEmpty, alpha > 0.002 else { return }
    let framesetter = CTFramesetterCreateWithAttributedString(attributed(shown, font(size, weight), lineSpacing: lineSpacing))
    state {
        c.translateBy(x: rect.minX, y: rect.maxY)
        c.scaleBy(x: 1, y: -1)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil), nil)
        c.setFillColor(rgb(color, alpha))
        CTFrameDraw(frame, c)
    }
}
/// Reveals text from left to right with a rising slide, like a mask wipe.
func wipeText(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight, color: UInt32, progress p: Double, alpha: Double = 1) {
    guard p > 0 else { return }
    let w = measure(s, size, weight)
    state {
        c.clip(to: CGRect(x: x - 10, y: y - size * 1.2, width: (w + 20) * outExpo(p), height: size * 1.6))
        text(s, x, y + (1 - outCubic(p)) * size * 0.5, size, weight, color: color, alpha: alpha)
    }
}

// MARK: - The leaf logo, parsed from the brand SVG

struct Leaf { let body: CGPath; let highlight: CGPath; let bounds: CGRect; let inside: CGPoint }
func parseSVGPath(_ d: String) -> CGPath {
    let path = CGMutablePath()
    var numbers: [CGFloat] = []
    var command: Character = "M"
    func flush() {
        switch command {
        case "M": if numbers.count >= 2 { path.move(to: CGPoint(x: numbers[0], y: numbers[1])) }
        case "C":
            var i = 0
            while i + 5 < numbers.count {
                path.addCurve(to: CGPoint(x: numbers[i + 4], y: numbers[i + 5]), control1: CGPoint(x: numbers[i], y: numbers[i + 1]), control2: CGPoint(x: numbers[i + 2], y: numbers[i + 3]))
                i += 6
            }
        case "Z": path.closeSubpath()
        default: break
        }
        numbers = []
    }
    var token = ""
    for ch in d + " " {
        if ch.isLetter { if !token.isEmpty { numbers.append(CGFloat(Double(token)!)); token = "" }; flush(); command = ch; if ch == "Z" { flush() } }
        else if ch == " " || ch == "," { if !token.isEmpty { numbers.append(CGFloat(Double(token)!)); token = "" } }
        else { token.append(ch) }
    }
    if !token.isEmpty { numbers.append(CGFloat(Double(token)!)) }
    flush()
    return path
}
let leafShape: Leaf = {
    let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let svg = try! String(contentsOf: here.appendingPathComponent("../Brand/logo-transparent.svg"), encoding: .utf8)
    let regex = try! NSRegularExpression(pattern: "fill=\"(#[0-9A-Fa-f]+)\"\\s+d=\"([^\"]+)\"")
    var body: CGPath?, highlight: CGPath?
    for m in regex.matches(in: svg, range: NSRange(svg.startIndex..., in: svg)) {
        let fillColor = String(svg[Range(m.range(at: 1), in: svg)!]).uppercased()
        let path = parseSVGPath(String(svg[Range(m.range(at: 2), in: svg)!]))
        if fillColor == "#20B68A" { body = path } else { highlight = path }
    }
    let b = body!.boundingBoxOfPath
    // A point deep inside the green body (and outside the highlight), used as the zoom-through target.
    var best = CGPoint(x: b.midX, y: b.midY), bestDistance = -1.0
    for i in 0..<60 { for j in 0..<60 {
        let p = CGPoint(x: b.minX + b.width * CGFloat(i) / 59, y: b.minY + b.height * CGFloat(j) / 59)
        guard body!.contains(p), !(highlight?.contains(p) ?? false) else { continue }
        var nearest = 1e9
        for k in 0..<48 {
            let a = Double(k) / 48 * 2 * .pi
            var r = 4.0
            while r < 900, body!.contains(CGPoint(x: p.x + r * cos(a), y: p.y + r * sin(a))), !(highlight?.contains(CGPoint(x: p.x + r * cos(a), y: p.y + r * sin(a))) ?? false) { r += 8 }
            nearest = min(nearest, r)
        }
        if nearest > bestDistance { bestDistance = nearest; best = p }
    } }
    return Leaf(body: body!, highlight: highlight!, bounds: b, inside: best)
}()
/// Draws the leaf so the SVG point `anchor` lands on `at`. `height` is the leaf's on-screen height.
func drawLeaf(at: CGPoint, height: CGFloat, rotate: Double = 0, anchor: CGPoint? = nil, alpha: Double = 1, highlight: Double = 1, color: UInt32 = leaf) {
    guard height > 0.5, alpha > 0.002 else { return }
    let b = leafShape.bounds
    let s = height / b.height
    let a = anchor ?? CGPoint(x: b.midX, y: b.midY)
    state {
        c.translateBy(x: at.x, y: at.y)
        c.rotate(by: rotate * .pi / 180)
        c.scaleBy(x: s, y: s)
        c.translateBy(x: -a.x, y: -a.y)
        fillPath(leafShape.body, color, alpha)
        if highlight > 0 { fillPath(leafShape.highlight, mint, alpha * highlight) }
    }
}

// MARK: - The app's dark palette (Sources/LectureNoteApp/DesignSystem/Colors.swift)

let dCanvas: UInt32 = 0x0F1216, dSurface: UInt32 = 0x181C21, dInset: UInt32 = 0x1F242B, dSel: UInt32 = 0x1D3A50, dOnSel: UInt32 = 0xCDEBFF
let dAcc: UInt32 = 0x7CC4F2, dOnAcc: UInt32 = 0x0F1216, dSoft: UInt32 = 0x1A2C3A, dGreen: UInt32 = 0x34C99B
let dText: UInt32 = 0xE6E8EB, dSec: UInt32 = 0x9AA3AD, dSep: UInt32 = 0x2A3038

// MARK: - Drawing helpers for the demos

var symbols: [String: (CGImage, CGSize)] = [:]
/// An SF Symbol, centered on p.
func symbol(_ name: String, _ p: CGPoint, _ size: CGFloat, _ color: UInt32, weight: NSFont.Weight = .regular, alpha: Double = 1) {
    guard alpha > 0.002 else { return }
    let key = "\(name)|\(size)|\(color)|\(weight.rawValue)"
    if symbols[key] == nil {
        let k: CGFloat = 6
        let config = NSImage.SymbolConfiguration(pointSize: size * k, weight: symbolWeight(weight))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config),
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("no symbol \(name)") }
        let tint = CGContext(data: nil, width: source.width, height: source.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo)!
        let r = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        tint.draw(source, in: r)
        tint.setBlendMode(.sourceIn)
        tint.setFillColor(rgb(color))
        tint.fill(r)
        symbols[key] = (tint.makeImage()!, CGSize(width: image.size.width / k, height: image.size.height / k))
    }
    let (image, s) = symbols[key]!
    state {
        c.setAlpha(alpha)
        c.translateBy(x: p.x, y: p.y)
        c.scaleBy(x: 1, y: -1)
        c.draw(image, in: CGRect(x: -s.width / 2, y: -s.height / 2, width: s.width, height: s.height))
    }
}
func symbolWeight(_ w: NSFont.Weight) -> NSFont.Weight { w }

func isWide(_ ch: Character) -> Bool { ch.unicodeScalars.contains { $0.value >= 0x2E80 } }
var wrapCache: [String: [String]] = [:]
func wrap(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ maxWidth: CGFloat) -> [String] {
    let key = "\(s)|\(size)|\(weight.rawValue)|\(maxWidth)"
    if let hit = wrapCache[key] { return hit }
    var tokens: [String] = [], current = ""
    for ch in s {
        if isWide(ch) { if !current.isEmpty { tokens.append(current); current = "" }; tokens.append(String(ch)) }
        else { current.append(ch); if ch == " " { tokens.append(current); current = "" } }
    }
    if !current.isEmpty { tokens.append(current) }
    var lines: [String] = [], line = ""
    for token in tokens {
        if !line.isEmpty, measure((line + token).trimmingCharacters(in: .whitespaces), size, weight) > maxWidth { lines.append(line); line = "" }
        line += token
    }
    if !line.isEmpty { lines.append(line) }
    wrapCache[key] = lines
    return lines
}
/// Wrapped lines, first baseline at y. Only `visible` characters show, and the newest `draftTail` of them are still being heard.
@discardableResult
func flow(_ lines: [String], _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight = .regular, lineHeight: CGFloat, color: UInt32, alpha: Double = 1,
          visible: Int? = nil, draftTail: Int = 0, draft: UInt32 = dSec) -> CGFloat {
    let total = lines.reduce(0) { $0 + $1.count }
    let shown = visible ?? total, settled = shown - draftTail
    var seen = 0, baseline = y
    for line in lines {
        guard seen < shown else { break }
        let count = min(line.count, shown - seen)
        let solid = max(0, min(count, settled - seen))
        let a = String(line.prefix(solid)), b = String(line.dropFirst(solid).prefix(count - solid))
        text(a, x, baseline, size, weight, color: color, alpha: alpha)
        if !b.isEmpty { text(b, x + measure(a, size, weight), baseline, size, weight, color: draft, alpha: alpha * 0.8) }
        seen += line.count
        baseline += lineHeight
    }
    return baseline
}
func pill(_ r: CGRect, fill color: UInt32, _ alpha: Double = 1) { fillPath(roundRect(r, r.height / 2), color, alpha) }
func card(_ r: CGRect, radius: CGFloat = 16, fill color: UInt32 = dSurface) { fillPath(roundRect(r, radius), color) }

func pointer(_ p: CGPoint, press: Double = 0, alpha: Double = 1) {
    group(alpha) {
        state {
            c.translateBy(x: p.x, y: p.y)
            let s = 1.7 * (1 - 0.12 * press)
            c.scaleBy(x: s, y: s)
            let path = CGMutablePath()
            path.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 17), CGPoint(x: 4.2, y: 13), CGPoint(x: 7, y: 19.4), CGPoint(x: 9.8, y: 18.2), CGPoint(x: 7, y: 12), CGPoint(x: 12.4, y: 12)])
            path.closeSubpath()
            c.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: rgb(0, 0.5))
            c.addPath(path); c.setFillColor(rgb(0x111418)); c.fillPath()
            c.setShadow(offset: .zero, blur: 0, color: nil)
            c.addPath(path); c.setStrokeColor(rgb(white)); c.setLineWidth(1.2); c.setLineJoin(.round); c.strokePath()
        }
    }
}
func clickRipple(_ p: CGPoint, _ t: Double, at: Double) {
    let k = prog(t, at, at + 0.55)
    if k > 0 && k < 1 { ring(p, 10 + 46 * outCubic(k), white, 0.55 * (1 - k), width: 2.5) }
}
func backdrop(_ t: Double) {
    radialBackground(0x0D2535, navy0, at: CGPoint(x: W / 2, y: 420), radius: 1250)
    glow(CGPoint(x: 330 + 70 * sin(t * 0.31), y: 880), 760, leaf, 0.10)
    glow(CGPoint(x: 1620, y: 180 + 50 * cos(t * 0.27)), 820, sky, 0.12)
}
func headline(_ title: String, _ sub: String?, _ t: Double, from a: Double, to b: Double, accentFrom: Int = 99) {
    let out = prog(t, b - 0.4, b)
    guard t > a, out < 1 else { return }
    kinetic(title, W / 2, 96, 56, .bold, anchor: 0.5, tracking: -0.6) { i, _ in
        let p = outExpo(prog(t, a + Double(i) * 0.05, a + 0.6 + Double(i) * 0.05))
        return Look(dy: (1 - p) * 34 - out * 16, alpha: p * (1 - out), color: i >= accentFrom ? mint : white)
    }
    if let sub {
        let p = outCubic(prog(t, a + 0.35, a + 0.9))
        text(sub, W / 2, 142 + (1 - p) * 14 - out * 12, 25, .regular, color: ice, alpha: 0.85 * p * (1 - out), anchor: 0.5)
    }
}
/// A caption on a dark scrim along the bottom, for close-ups.
func lowerCaption(_ s: String, _ t: Double, from a: Double, to b: Double) {
    let k = prog(t, a, a + 0.5) * (1 - prog(t, b - 0.4, b))
    guard k > 0 else { return }
    let g = CGGradient(colorsSpace: space, colors: [rgb(navy0, 0), rgb(navy0, 0.94 * k)] as CFArray, locations: [0, 0.75])!
    c.drawLinearGradient(g, start: CGPoint(x: 0, y: H - 260), end: CGPoint(x: 0, y: H), options: [])
    text(s, W / 2, H - 58 + (1 - outCubic(k)) * 14, 38, .semibold, color: white, alpha: k, anchor: 0.5, tracking: -0.3)
}

// MARK: - Sample lecture (invented for the video)

struct Row { let clock, en, zh: String; let start, speak: Double }
let rows: [Row] = [
    Row(clock: "0:02", en: "Today we're looking at how neurons pass signals to each other.", zh: "今天我们来看神经元之间如何传递信号。", start: 13.6, speak: 1.9),
    Row(clock: "0:09", en: "When the membrane reaches threshold, the neuron fires an action potential.", zh: "当膜电位达到阈值时，神经元会发出动作电位。", start: 15.7, speak: 2.5),
    Row(clock: "0:17", en: "That signal races down the axon, and myelin makes it travel much faster.", zh: "这个信号沿着轴突快速传导，髓鞘让它传得更快。", start: 18.5, speak: 2.5),
    Row(clock: "0:26", en: "At the synapse, the electrical signal becomes a chemical one.", zh: "在突触处，电信号转变为化学信号。", start: 21.3, speak: 2.1),
    Row(clock: "0:33", en: "Neurotransmitters cross the gap and bind to the next cell.", zh: "神经递质穿过间隙，与下一个细胞结合。", start: 23.7, speak: 2.0),
    Row(clock: "0:41", en: "So here's one for you. Why does myelin make the signal faster?", zh: "那我考考大家：为什么髓鞘能让信号传得更快？", start: 26.2, speak: 2.0),
]
let questionRow = 5
let bodyWidth: CGFloat = 388

// MARK: - The app window. All coordinates below are the real window's points (1180 x 780).

struct Camera { var scale: CGFloat; var origin: CGPoint }
let wide = Camera(scale: 1.12, origin: CGPoint(x: 299, y: 178))
let startClose = Camera(scale: 1.5, origin: CGPoint(x: -317, y: 213))
let transcriptClose = Camera(scale: 1.9, origin: CGPoint(x: 731, y: -262))
let popupClose = Camera(scale: 1.7, origin: CGPoint(x: -400, y: -440))
let chatClose = Camera(scale: 1.5, origin: CGPoint(x: 80, y: -130))
let figureClose = Camera(scale: 1.72, origin: CGPoint(x: 55, y: -205))
let shots: [(Double, Camera)] = [
    (10.0, wide), (11.4, wide), (12.4, startClose), (13.5, startClose), (14.7, wide), (16.6, wide), (18.2, transcriptClose), (24.6, transcriptClose), (26.0, wide),
    (30.5, wide), (31.6, popupClose), (33.7, popupClose), (34.7, wide),
    (45.9, wide), (47.0, chatClose), (51.6, chatClose), (52.6, wide),
    (56.8, wide), (58.0, figureClose), (61.6, figureClose), (62.4, wide),
]
func camera(_ t: Double) -> Camera {
    guard let next = shots.firstIndex(where: { $0.0 > t }) else { return shots.last!.1 }
    guard next > 0 else { return shots[0].1 }
    let (a, ca) = shots[next - 1], (b, cb) = shots[next]
    let k = inOutCubic(prog(t, a, b))
    // Interpolating the log of the scale keeps the zoom speed even.
    let s = exp(mix(log(ca.scale), log(cb.scale), k))
    // The origin follows the scale, so the point being approached moves in a straight line on screen.
    let e = ca.scale == cb.scale ? k : (s - ca.scale) / (cb.scale - ca.scale)
    return Camera(scale: s, origin: CGPoint(x: mix(ca.origin.x, cb.origin.x, e), y: mix(ca.origin.y, cb.origin.y, e)))
}

func topBar(_ t: Double, recording: Double, resumeTitle: Bool = false) {
    drawLeaf(at: CGPoint(x: 36, y: 58), height: 30)
    text("Nomi", 64, 65, 19, .semibold, color: dText)
    let rec = outCubic(recording)
    let width = mix(175, 176, rec)
    let r = CGRect(x: 1165 - width, y: 38, width: width, height: 40)
    pill(r, fill: blend(dAcc, dSel, rec))
    if rec < 0.5 {
        group(1 - rec * 2) {
            symbol("waveform", CGPoint(x: r.minX + 25, y: r.midY), 14, dOnAcc, weight: .semibold)
            text("Start Transcription", r.minX + 40, r.midY + 4.5, 13, .semibold, color: dOnAcc)
        }
    } else {
        group(rec * 2 - 1) {
            // DotWaveform, the elapsed time, then pause and stop.
            for i in 0..<7 {
                let h = 4 + 12 * (0.5 + 0.5 * sin(t * 7 + Double(i) * 1.1)) * (0.45 + 0.55 * sin(t * 2.3 + Double(i)) * sin(t * 2.3 + Double(i)))
                fillPath(roundRect(CGRect(x: r.minX + 14 + CGFloat(i) * 5.5, y: r.midY - h / 2, width: 3, height: h), 1.5), dOnSel)
            }
            let elapsed = max(0, (t - 13.1) * 3.0)
            text(String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60), r.minX + 62, r.midY + 4.5, 13, .semibold, color: dOnSel)
            circle(CGPoint(x: r.maxX - 44, y: r.midY), 11, dSurface)
            symbol("pause.fill", CGPoint(x: r.maxX - 44, y: r.midY), 10, dOnSel, weight: .bold)
            circle(CGPoint(x: r.maxX - 15, y: r.midY), 11, 0xFF453A)
            symbol("stop.fill", CGPoint(x: r.maxX - 15, y: r.midY), 10, white, weight: .bold)
        }
    }
}
func railItems(selected: Double) {
    // selected is continuous so the highlight can slide: 0 Meetings, 1 Sources, 2 Chat.
    let y = 92 + 58 * CGFloat(selected)
    fillPath(roundRect(CGRect(x: 6, y: y, width: 60, height: 54), 12), dSel)
    let items: [(String, String, CGFloat)] = [("calendar", "Meetings", 92), ("folder", "Sources", 150), ("text.bubble", "Chat", 208),
                                              ("questionmark.circle", "Help", 652), ("gearshape", "Settings", 710)]
    for (i, item) in items.enumerated() {
        let on = i < 3 && abs(Double(i) - selected) < 0.5
        let color = on ? dOnSel : dSec
        symbol(item.0, CGPoint(x: 36, y: item.2 + 19), 18, color, weight: on ? .semibold : .regular)
        text(item.1, 36, item.2 + 44, 12, on ? .semibold : .medium, color: color, anchor: 0.5)
    }
}
func chip(_ s: String, _ x: CGFloat, icon: String? = nil) -> CGFloat {
    let w = measure(s, 13, .medium) + 24 + (icon == nil ? 0 : 22)
    let r = CGRect(x: x, y: 144, width: w, height: 28)
    pill(r, fill: dSurface)
    if let icon { symbol(icon, CGPoint(x: x + 20, y: r.midY), 13, dSec) }
    text(s, x + 12 + (icon == nil ? 0 : 22), r.midY + 4.5, 13, .medium, color: dSec)
    return x + w + 8
}
func meetingHeader() {
    circle(CGPoint(x: 112, y: 116), 16, dSurface)
    symbol("chevron.left", CGPoint(x: 112, y: 116), 13, dText, weight: .semibold)
    circle(CGPoint(x: 156, y: 116), 16, 0x24404F)
    symbol("brain.head.profile", CGPoint(x: 156, y: 116), 15, dAcc)
    text("Neuroscience · Lecture 7", 184, 123, 20, .semibold, color: dText)
    circle(CGPoint(x: 1140, y: 116), 16, dSurface)
    symbol("rectangle.on.rectangle", CGPoint(x: 1140, y: 116), 13, dSec)
    var x: CGFloat = 96
    x = chip("Oct 21 Tue 09:00", x)
    x = chip("Biology 101", x)
    x = chip("English → Chinese", x)
    _ = chip("AirPods Pro", x, icon: "airpodspro")
}
func rowHeight(_ row: Row) -> CGFloat {
    CGFloat(wrap(row.en, 15, .regular, bodyWidth).count) * 24 + CGFloat(wrap(row.zh, 13.5, .regular, bodyWidth).count) * 21 + 26
}
func transcriptCard(_ t: Double, highlight: Double = 0) {
    let r = CGRect(x: 96, y: 188, width: 498, height: 572)
    card(r)
    text("Transcript", 112, 221, 16, .semibold, color: dText)
    for (s, x) in [("A−", 409.0), ("A+", 445), ("Inline", 483), ("Copy All", 530)] { text(s, x, 221, 12, .medium, color: dSec) }
    let listening = prog(t, 13.2, 13.35) * (1 - prog(t, 13.55, 13.7))
    if t > 13.2 && t < 13.7 { text("Listening…", 116, 262, 14, .regular, color: dSec, alpha: listening) }
    // The list scrolls as new rows arrive, so the newest line stays in view.
    var content: CGFloat = 0
    for row in rows { content += rowHeight(row) * outCubic(prog(t, row.start + row.speak * 0.55, row.start + row.speak * 0.55 + 0.7)) }
    let viewHeight: CGFloat = 470
    let scroll = max(0, content - viewHeight)
    state {
        c.clip(to: CGRect(x: r.minX, y: 240, width: r.width, height: r.maxY - 240))
        var y: CGFloat = 262 - scroll
        for (i, row) in rows.enumerated() where t >= row.start {
            let spoken = prog(t, row.start, row.start + row.speak)
            let lines = wrap(row.en, 15, .regular, bodyWidth)
            let total = lines.reduce(0) { $0 + $1.count }
            let height = rowHeight(row)
            if i == questionRow && highlight > 0 {
                fillPath(roundRect(CGRect(x: 104, y: y - 22, width: 482, height: height - 6), 10), dSel, 0.9 * highlight)
            }
            let appear = outCubic(prog(t, row.start, row.start + 0.25))
            text(row.clock, 116, y, 12, .medium, color: dSec, alpha: appear)
            let next = flow(lines, 184, y, 15, lineHeight: 24, color: dText, visible: Int(Double(total) * spoken), draftTail: spoken < 1 ? 16 : 0)
            let zhIn = outCubic(prog(t, row.start + row.speak + 0.05, row.start + row.speak + 0.55))
            if zhIn > 0 {
                flow(wrap(row.zh, 13.5, .regular, bodyWidth), 184, next + 1 + (1 - zhIn) * 8, 13.5, lineHeight: 21, color: dSec, alpha: zhIn)
            }
            y += height
        }
    }
}
func sideTabs(_ selected: Int) {
    let tabs: [(String, CGFloat, CGFloat)] = [("Chat", 627, 44), ("Q&A", 678, 44), ("Summary", 728, 70), ("Sources", 804, 62), ("Info", 872, 42)]
    for (i, tab) in tabs.enumerated() {
        if i == selected { pill(CGRect(x: tab.1, y: 204, width: tab.2, height: 26), fill: dSel) }
        text(tab.0, tab.1 + tab.2 / 2, 221, 12, .medium, color: i == selected ? dOnSel : dSec, anchor: 0.5)
    }
    symbol("xmark", CGPoint(x: 1128, y: 217), 11, dSec, weight: .semibold)
}
func clockChip(_ s: String, _ x: CGFloat, _ y: CGFloat) -> CGRect {
    let w = measure(s, 12, .medium) + 34
    let r = CGRect(x: x, y: y, width: w, height: 22)
    pill(r, fill: dSoft)
    symbol("clock", CGPoint(x: x + 14, y: r.midY), 11, dAcc)
    text(s, x + 25, r.midY + 4, 12, .medium, color: dAcc)
    return r
}
let myelinQuestion = "Why does myelin make the signal faster?"
let myelinQuote = "So here's one for you. Why does myelin make the signal faster?"
let myelinAnswer = "Myelin insulates the axon, so the signal jumps from one gap to the next instead of crawling along every part of the membrane."
let oldQuestions: [(String, String, String, String)] = [
    ("0:17", "How fast can a signal travel along an axon?", "Do you remember how fast these signals go?", "Up to about 120 m/s in thick, myelinated axons, and around 1 m/s in thin ones without myelin."),
    ("0:09", "What triggers an action potential?", "And what sets it off in the first place?", "The membrane potential reaching threshold, which opens the voltage-gated sodium channels."),
]
func qaCard(_ x: CGFloat, _ y: CGFloat, clock: String, question: String, quote: String, answer: String, width: CGFloat = 513) -> CGFloat {
    let inner = width - 24
    let answerLines = wrap(answer, 14, .regular, inner)
    let height = 12 + 22 + 8 + 20 + 18 + 8 + CGFloat(answerLines.count) * 21 + 8 + 16 + 12
    card(CGRect(x: x, y: y, width: width, height: height), fill: dInset)
    _ = clockChip(clock, x + 12, y + 12)
    symbol("ellipsis", CGPoint(x: x + width - 22, y: y + 22), 13, dSec)
    text(question, x + 12, y + 58, 14, .semibold, color: dText)
    text("“\(quote)”", x + 12, y + 78, 12, .medium, color: dSec)
    flow(answerLines, x + 12, y + 103, 14, lineHeight: 21, color: dText)
    text("Continue in Chat", x + 12, y + height - 14, 12, .medium, color: dAcc)
    return height
}
func qaPanel(_ t: Double, newCard: Double) {
    let r = CGRect(x: 611, y: 188, width: 545, height: 572)
    card(r)
    sideTabs(1)
    text("Auto-answer", 627, 262, 12, .medium, color: dText)
    let toggle = CGRect(x: 706, y: 250, width: 40, height: 22)
    pill(toggle, fill: 0x0A84FF)
    circle(CGPoint(x: toggle.maxX - 11, y: toggle.midY), 9, white)
    // Questions arrive during the lecture, newest on top. Nothing is here before the recording starts.
    let arrivals = [22.0, 20.0]
    let arrived = arrivals.filter { t >= $0 }.count
    let count = arrived + (newCard > 0.5 ? 1 : 0)
    text("\(count) questions · \(count) answered", 1120, 262, 12, .medium, color: dSec, anchor: 1)
    state {
        c.clip(to: CGRect(x: r.minX, y: 282, width: r.width, height: r.maxY - 282))
        var y: CGFloat = 286
        if newCard > 0 {
            let height = 12 + 22 + 8 + 20 + 18 + 8 + CGFloat(wrap(myelinAnswer, 14, .regular, 489).count) * 21 + 8 + 16 + 12
            group(prog(newCard, 0.3, 1)) {
                _ = qaCard(627, y - (1 - newCard) * 24, clock: "0:41", question: myelinQuestion, quote: myelinQuote, answer: myelinAnswer)
            }
            y += (height + 12) * newCard
        }
        for (i, q) in oldQuestions.enumerated() {
            let k = outCubic(prog(t, arrivals[i], arrivals[i] + 0.5))
            guard k > 0 else { continue }
            let height = 12 + 22 + 8 + 20 + 18 + 8 + CGFloat(wrap(q.3, 14, .regular, 489).count) * 21 + 8 + 16 + 12
            group(k) { _ = qaCard(627, y - (1 - k) * 24, clock: q.0, question: q.1, quote: q.2, answer: q.3) }
            y += (height + 12) * k
        }
    }
}
func questionPopup(_ t: Double, enter: Double) {
    // Bottom right of the window, 24 points in (AppShell.swift).
    let width: CGFloat = 420
    let answering = t >= 30.2
    let lines = wrap(myelinAnswer, 14, .regular, width - 36)
    let typed = prog(t, 31.0, 33.0)
    let bodyHeight: CGFloat = answering ? (typed > 0 ? CGFloat(lines.count) * 21 + 12 : 40) : 0
    let grow = outCubic(prog(t, 30.2, 30.7))
    let height: CGFloat = 16 + 22 + 8 + 22 + 22 + 16 + bodyHeight * grow + 8
    let r = CGRect(x: 1180 - 24 - width, y: 780 - 24 - height, width: width, height: height)
    let e = spring(enter)
    state {
        c.translateBy(x: 0, y: (1 - e) * 60)
        c.setAlpha(min(1, enter * 4))
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        state { c.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: rgb(0, 0.45)); fillPath(roundRect(r, 18), dSurface) }
        strokePath(roundRect(r, 18), dSep, 1, width: 1)
        let pulse = 0.8 + 0.2 * sin(t * 4)
        circle(CGPoint(x: r.minX + 22, y: r.minY + 25), 4 * (typed >= 1 ? 1 : pulse), dGreen, typed >= 1 ? 1 : pulse)
        let label = typed >= 1 ? "Answered" : (answering ? "Answering" : "Teacher asked")
        text("\(label) · 0:41", r.minX + 34, r.minY + 29.5, 12, .bold, color: dAcc)
        symbol("xmark", CGPoint(x: r.maxX - 26, y: r.minY + 25), 10, dSec, weight: .bold)
        text(myelinQuestion, r.minX + 18, r.minY + 62, 16, .semibold, color: dText)
        text(String(myelinQuote.prefix(52)) + "…", r.minX + 18, r.minY + 84, 13, .regular, color: dAcc)
        if answering {
            state {
                c.clip(to: CGRect(x: r.minX, y: r.minY + 92, width: r.width, height: bodyHeight * grow + 8))
                if typed <= 0 {
                    let sweep = (t * 0.9).truncatingRemainder(dividingBy: 1)
                    for (k, w) in [(0, width - 36), (1, 220.0)] {
                        let bar = CGRect(x: r.minX + 18, y: r.minY + 100 + CGFloat(k) * 18, width: w, height: 10)
                        fillPath(roundRect(bar, 5), dInset)
                        state { c.addPath(roundRect(bar, 5)); c.clip(); glow(CGPoint(x: bar.minX + bar.width * sweep, y: bar.midY), 70, dSec, 0.35) }
                    }
                } else {
                    let total = lines.reduce(0) { $0 + $1.count }
                    flow(lines, r.minX + 18, r.minY + 110, 14, lineHeight: 21, color: dSec, visible: Int(Double(total) * typed))
                }
            }
        }
        c.endTransparencyLayer()
    }
}
func fillerChip(_ s: String, _ p: CGPoint, _ t: Double, at: Double, tilt: Double) {
    let inP = outBack(prog(t, at, at + 0.35))
    let strike = outCubic(prog(t, at + 0.55, at + 0.9))
    let fall = inCubic(prog(t, at + 1.6, at + 2.3))
    guard inP > 0, fall < 1 else { return }
    let w = measure(s, 18, .semibold) + 36
    let r = CGRect(x: p.x - w / 2, y: p.y - 21, width: w, height: 42)
    group(prog(t, at, at + 0.2) * (1 - fall)) {
        state {
            transform(at: p, scale: inP, rotate: tilt + fall * 22)
            c.translateBy(x: 0, y: fall * 90)
            state { c.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: rgb(0, 0.4)); pill(r, fill: 0x2A3038) }
            text(s, p.x, p.y + 6, 18, .semibold, color: dText, anchor: 0.5)
            line(CGPoint(x: r.minX + 12, y: p.y), CGPoint(x: r.minX + 12 + (w - 24) * strike, y: p.y), 0xFF6B6B, 1, width: 2)
        }
    }
}

// Chat
let chatQuestion = "What did the teacher say about the exam last week?"
let answerParas: [(String, String, String, Double)] = [
    ("The midterm covers lectures 4 to 7, with the most weight on action potentials.", "clock", "Lecture 6 · 41:18", 46.4),
    ("You can bring one page of handwritten notes.", "clock", "Lecture 6 · 43:02", 47.6),
    ("It's on November 18 in Hall B.", "doc.text", "Syllabus.pdf · p. 3", 48.5),
]
let searched: [(String, String, Double)] = [("clock", "Lecture 6 · Oct 14", 44.1), ("clock", "Lecture 7 · Oct 21", 44.5), ("doc.text", "Syllabus.pdf", 44.9), ("text.bubble", "Chat · Exam prep", 45.3)]
let demoQuestion = "Can you show me how myelin speeds up the signal?"

func composer(_ t: Double, typed: String, focused: Bool) {
    let r = CGRect(x: 136, y: 628, width: 996, height: 112)
    card(r, radius: 22, fill: dInset)
    // Scope and Web
    let scope = CGRect(x: 152, y: 644, width: 130, height: 28)
    pill(scope, fill: dSoft)
    symbol("folder", CGPoint(x: scope.minX + 18, y: scope.midY), 13, dAcc)
    text("All lectures", scope.minX + 32, scope.midY + 4.5, 13, .medium, color: dAcc)
    let web = CGRect(x: 290, y: 644, width: 74, height: 28)
    pill(web, fill: dSurface); strokePath(roundRect(web, 14), dSep, 1, width: 1)
    symbol("globe", CGPoint(x: web.minX + 19, y: web.midY), 13, dSec)
    text("Web", web.minX + 33, web.midY + 4.5, 13, .medium, color: dSec)
    text("Local model", 1100, 662, 13, .regular, color: dSec, anchor: 1)
    symbol("chevron.down", CGPoint(x: 1014 - measure("Local model", 13, .regular) + 72, y: 658), 9, dSec, weight: .bold)
    symbol("paperclip", CGPoint(x: 160, y: 706), 15, dSec)
    if typed.isEmpty { text("Chat about something…", 186, 711, 14, .regular, color: dSec) }
    else { text(typed, 186, 711, 14, .regular, color: dText) }
    if focused, sin(t * 7) > -0.3 {
        let x = 186 + (typed.isEmpty ? 0 : measure(typed, 14, .regular))
        line(CGPoint(x: x + 1, y: 697), CGPoint(x: x + 1, y: 715), dAcc, 1, width: 1.6)
    }
    circle(CGPoint(x: 1108, y: 706), 16, typed.isEmpty ? dSurface : dAcc)
    symbol("arrow.up", CGPoint(x: 1108, y: 706), 13, typed.isEmpty ? dSec : dOnAcc, weight: .bold)
}
func userBubble(_ s: String, rightEdge: CGFloat, _ y: CGFloat, alpha: Double = 1) {
    let w = measure(s, 14, .regular) + 32
    let r = CGRect(x: rightEdge - w, y: y, width: w, height: 38)
    group(alpha) {
        pill(r, fill: dSel)
        text(s, r.minX + 16, r.midY + 5, 14, .regular, color: dOnSel)
    }
}
/// A source link inline in an answer, like the app's: a small symbol and accent text.
func citation(_ icon: String, _ s: String, _ x: CGFloat, _ baseline: CGFloat, alpha: Double, lit: Double = 0) {
    guard alpha > 0 else { return }
    group(alpha) {
        let w = measure(s, 14, .medium) + 20
        if lit > 0 { pill(CGRect(x: x - 5, y: baseline - 16, width: w + 8, height: 22), fill: dSoft, lit) }
        symbol(icon, CGPoint(x: x + 7, y: baseline - 5), 12, dAcc)
        text(s, x + 18, baseline, 14, .medium, color: dAcc)
    }
}
func exploreSource(_ t: Double) {
    // The preview the cited moment opens: the real lines from that lecture.
    let k = spring(prog(t, 49.8, 50.5))
    guard k > 0 else { return }
    let r = CGRect(x: 640, y: 366, width: 450, height: 150)
    group(min(1, prog(t, 49.8, 50.05))) {
        state {
            transform(at: CGPoint(x: r.minX, y: r.minY), scale: 0.94 + 0.06 * k)
            state { c.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0, 0.5)); fillPath(roundRect(r, 14), dInset) }
            strokePath(roundRect(r, 14), dSep, 1, width: 1)
            symbol("clock", CGPoint(x: r.minX + 24, y: r.minY + 26), 12, dAcc)
            text("Lecture 6 · Oct 14 · 41:18", r.minX + 38, r.minY + 31, 13, .semibold, color: dAcc)
            flow(wrap("“For the midterm, it's lectures four to seven. Most of the marks are on action potentials, so make sure you can draw that graph.”", 14, .regular, r.width - 40), r.minX + 20, r.minY + 62, 14, lineHeight: 22, color: dText)
        }
    }
}
func chatPage(_ t: Double) {
    text("Chat", 120, 142, 28, .medium, color: dText)
    circle(CGPoint(x: 1082, y: 130), 18, dSurface)
    symbol("clock.arrow.circlepath", CGPoint(x: 1082, y: 130), 15, dSec)
    circle(CGPoint(x: 1130, y: 130), 18, dSurface)
    symbol("plus", CGPoint(x: 1130, y: 130), 15, dSec)
    let area = CGRect(x: 120, y: 166, width: 1030, height: 452)
    card(area)
    let sent = t >= 43.2
    let demoAsked = t >= 52.6
    let typedCount = Int(Double(chatQuestion.count) * prog(t, 41.0, 43.0))
    let demoTyped = Int(Double(demoQuestion.count) * prog(t, 52.6, 53.8))
    var field = sent ? "" : String(chatQuestion.prefix(typedCount))
    if t >= 52.6 && t < 53.9 { field = String(demoQuestion.prefix(demoTyped)) }
    state {
        c.clip(to: roundRect(area, 16).boundingBox)
        // The conversation scrolls up to make room for the next question.
        let lift = 372 * inOutCubic(prog(t, 53.9, 54.7))
        c.translateBy(x: 0, y: -lift)
        if sent {
            let rise = outCubic(prog(t, 43.2, 43.6))
            userBubble(chatQuestion, rightEdge: 1124, 186 + (1 - rise) * 40, alpha: rise)
        }
        // Sources being searched, each lighting up in turn.
        let searching = prog(t, 43.7, 44.0)
        if searching > 0 {
            text(t < 46.2 ? "Searching your lectures, chats and files…" : "Found in 3 sources", 146, 262, 13, .regular, color: dSec, alpha: searching)
            var x: CGFloat = 146
            for (i, s) in searched.enumerated() {
                let p = outBack(prog(t, s.2, s.2 + 0.3))
                let w = measure(s.1, 13, .medium) + 40
                if p > 0 {
                    let used = i != 3
                    let lit = used ? prog(t, s.2 + 0.2, s.2 + 0.6) : 0
                    let r = CGRect(x: x, y: 276, width: w, height: 30)
                    state {
                        transform(at: CGPoint(x: r.midX, y: r.midY), scale: p)
                        pill(r, fill: lit > 0.5 ? dSoft : dInset)
                        symbol(s.0, CGPoint(x: r.minX + 18, y: r.midY), 12, lit > 0.5 ? dAcc : dSec)
                        text(s.1, r.minX + 32, r.midY + 4.5, 13, .medium, color: lit > 0.5 ? dAcc : dSec)
                    }
                }
                x += w + 8
            }
        }
        // The answer, with a source after every part.
        var y: CGFloat = 342
        for (i, para) in answerParas.enumerated() where t >= para.3 {
            let lines = wrap(para.0, 14, .regular, 760)
            let total = lines.reduce(0) { $0 + $1.count }
            let k = prog(t, para.3, para.3 + Double(total) / 70)
            flow(lines, 146, y, 14, lineHeight: 22, color: dText, visible: Int(Double(total) * k))
            let last = lines.last!
            citation(para.1, para.2, 146 + measure(last, 14, .regular) + 8, y + CGFloat(lines.count - 1) * 22, alpha: prog(t, para.3 + Double(total) / 70, para.3 + Double(total) / 70 + 0.25), lit: i == 0 ? prog(t, 49.5, 49.8) : 0)
            y += CGFloat(lines.count) * 22 + 14
        }
        if t >= 49.8 && t < 52.6 { group(1 - prog(t, 52.1, 52.5)) { exploreSource(t) } }
        // The interactive figure, on the next turn.
        if t >= 53.9 {
            let rise = outCubic(prog(t, 53.9, 54.3))
            userBubble(demoQuestion, rightEdge: 1124, 186 + 372 + (1 - rise) * 40, alpha: rise)
        }
        if t >= 54.6 { figure(t, CGPoint(x: 146, y: 186 + 372 + 56)) }
    }
    composer(t, typed: field, focused: (t > 40.8 && t < 43.2) || (t > 52.5 && t < 53.9))
}

// MARK: - The interactive figure: how myelin speeds up a signal

func axon(_ t: Double, _ r: CGRect, myelin m: Double, phase: Double, name: String, speed: String) {
    // m is how much of the axon is wrapped. At 0 the signal crawls; wrapped, it jumps between the gaps.
    text(name, r.minX, r.minY - 10, 13, .medium, color: dSec)
    text(speed, r.maxX, r.minY - 10, 13, .semibold, color: m > 0.05 ? mint : dSec, anchor: 1)
    let tube = CGRect(x: r.minX, y: r.midY - 7, width: r.width, height: 14)
    fillPath(roundRect(tube, 7), 0x2E3640)
    let segments = 6
    let gap: CGFloat = 12
    let segWidth = (r.width - gap * CGFloat(segments + 1)) / CGFloat(segments)
    var nodes: [CGFloat] = [r.minX + gap / 2]
    for i in 0..<segments {
        let x = r.minX + gap + CGFloat(i) * (segWidth + gap)
        nodes.append(x + segWidth + gap / 2)
        let thick = 7 + 12 * m
        let shown = CGFloat(clamp(m * 2.4 - Double(i) * 0.06))
        if shown > 0 {
            let seg = CGRect(x: x, y: r.midY - thick, width: segWidth, height: thick * 2)
            state { c.addRect(CGRect(x: x + segWidth * (1 - shown) / 2, y: r.minY - 30, width: segWidth * shown, height: r.height + 60)); c.clip(); fillPath(roundRect(seg, thick), 0xE8D5A8, 0.9) }
        }
    }
    let hop = m > 0.5
    let u = phase.truncatingRemainder(dividingBy: 1)
    if hop {
        let position = u * Double(segments)
        let i = min(Int(position), segments - 1)
        let f = position - Double(i)
        let x = mix(nodes[i], nodes[i + 1], inOutCubic(f))
        let arc = sin(f * .pi) * 30
        for k in 1...6 {
            let trail = max(0, f - Double(k) * 0.05)
            let tx = mix(nodes[i], nodes[i + 1], inOutCubic(trail))
            circle(CGPoint(x: tx, y: r.midY - sin(trail * .pi) * 30), 7 - CGFloat(k), dAcc, 0.3 - Double(k) * 0.04)
        }
        glow(CGPoint(x: x, y: r.midY - arc), 34, dAcc, 0.8)
        circle(CGPoint(x: x, y: r.midY - arc), 7, white)
        for node in nodes where node <= x { circle(CGPoint(x: node, y: r.midY), 3.5, dAcc, 0.9) }
    } else {
        let x = mix(r.minX, r.maxX, u)
        state { c.clip(to: tube); fillPath(CGPath(rect: CGRect(x: r.minX, y: tube.minY, width: x - r.minX, height: tube.height), transform: nil), dAcc, 0.45) }
        glow(CGPoint(x: x, y: r.midY), 28, dAcc, 0.75)
        circle(CGPoint(x: x, y: r.midY), 6, white)
    }
}
func figure(_ t: Double, _ o: CGPoint) {
    let build = outCubic(prog(t, 54.6, 55.2))
    group(build) {
        state {
            c.translateBy(x: 0, y: (1 - build) * 26)
            text("Interactive figure", o.x, o.y - 8, 13, .regular, color: dSec)
            let r = CGRect(x: o.x, y: o.y, width: 760, height: 318)
            card(r, fill: dInset)
            text("How myelin speeds up a signal", r.minX + 24, r.minY + 42, 22, .bold, color: dText)
            let m = mix(0.08, 0.92, inOutCubic(prog(t, 57.0, 59.4)))
            let v = 1 + m * 119
            let bare = CGRect(x: r.minX + 24, y: r.minY + 88, width: r.width - 48, height: 40)
            let wrapped = CGRect(x: r.minX + 24, y: r.minY + 164, width: r.width - 48, height: 40)
            axon(t, bare, myelin: 0, phase: t * 0.06, name: "No myelin", speed: "1 m/s")
            axon(t, wrapped, myelin: m, phase: t * (0.08 + 0.34 * m), name: "With myelin", speed: String(format: "%.0f m/s", v))
            // The slider the viewer can drag.
            let track = CGRect(x: r.minX + 24, y: r.minY + 262, width: r.width - 218, height: 6)
            text("Myelin", r.minX + 24, r.minY + 250, 13, .medium, color: dSec)
            text(String(format: "%.0f%%", m * 100), track.maxX, r.minY + 250, 13, .semibold, color: dText, anchor: 1)
            fillPath(roundRect(track, 3), 0x3A414A)
            let knob = CGPoint(x: track.minX + track.width * CGFloat(m), y: track.midY)
            fillPath(roundRect(CGRect(x: track.minX, y: track.minY, width: knob.x - track.minX, height: 6), 3), dAcc)
            state { c.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: rgb(0, 0.5)); circle(knob, 10, white) }
            let button = CGRect(x: r.maxX - 170, y: r.minY + 246, width: 146, height: 38)
            pill(button, fill: dAcc)
            text("Send a signal", button.midX, button.midY + 5, 14, .semibold, color: dOnAcc, anchor: 0.5)
        }
    }
}
func figureKnob(_ t: Double) -> CGPoint {
    // In window points, for the pointer that drags the slider.
    let m = mix(0.08, 0.92, inOutCubic(prog(t, 57.0, 59.4)))
    let lift: CGFloat = 372
    return CGPoint(x: 146 + 24 + (760 - 218) * CGFloat(m), y: 186 + 372 + 56 + 265 - lift)
}

// MARK: - The whole window

func meetingPage(_ t: Double) {
    meetingHeader()
    let jump = prog(t, 36.3, 36.7) * (1 - prog(t, 38.6, 39.2))
    transcriptCard(t, highlight: jump)
    let newCard = outCubic(prog(t, 34.0, 34.6))
    qaPanel(t, newCard: newCard)
}
func appWindow(_ t: Double, alpha: Double = 1) {
    let cam = camera(t)
    let rect = CGRect(x: 0, y: 0, width: 1180, height: 780)
    group(alpha) {
        state {
            c.translateBy(x: cam.origin.x, y: cam.origin.y)
            c.scaleBy(x: cam.scale, y: cam.scale)
            state { c.setShadow(offset: CGSize(width: 0, height: -40), blur: 120, color: rgb(0, 0.6)); fillPath(roundRect(rect, 16), dCanvas) }
            state {
                c.addPath(roundRect(rect, 16)); c.clip()
                for (i, color) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() { circle(CGPoint(x: 16 + CGFloat(i) * 23, y: 16), 6.5, color) }
                let tab = inOutCubic(prog(t, 40.0, 40.4))
                topBar(t, recording: prog(t, 13.0, 13.35))
                railItems(selected: 2 * tab)
                // Pages slide and fade like the app's own page change.
                if tab < 1 { group(1 - tab) { state { c.translateBy(x: -30 * tab, y: 0); meetingPage(t) } } }
                if tab > 0 { group(tab) { state { c.translateBy(x: 30 * (1 - tab), y: 0); chatPage(t) } } }
                let dim = prog(t, 30.6, 31.3) * (1 - prog(t, 33.5, 34.1))
                if dim > 0 { fill(0x05080C, 0.55 * dim, rect) }
                if t > 26 && t < 34.6 {
                    fillerChip("right?", CGPoint(x: 260, y: 660), t, at: 26.6, tilt: -5)
                    fillerChip("can you hear me?", CGPoint(x: 440, y: 700), t, at: 27.2, tilt: 4)
                    fillerChip("okay?", CGPoint(x: 210, y: 720), t, at: 27.8, tilt: 6)
                    questionPopup(t, enter: prog(t, 29.0, 29.6) * (1 - prog(t, 33.7, 34.0)))
                }
            }
            strokePath(roundRect(rect, 16), white, 0.09, width: 1)
        }
    }
}
func toScreen(_ p: CGPoint, _ t: Double) -> CGPoint {
    let cam = camera(t)
    return CGPoint(x: cam.origin.x + p.x * cam.scale, y: cam.origin.y + p.y * cam.scale)
}
let sourceChip = CGPoint(x: 146 + measure(answerParas[0].0, 14, .regular) + 70, y: 342)
/// The pointer's path through the take, in window points: (time, position).
let pointerPath: [(Double, CGPoint)] = [
    (10.8, CGPoint(x: 700, y: 480)), (12.7, CGPoint(x: 1078, y: 58)), (13.4, CGPoint(x: 1078, y: 58)), (14.8, CGPoint(x: 1000, y: 880)),
    (34.6, CGPoint(x: 1000, y: 880)), (35.7, CGPoint(x: 681, y: 317)), (37.4, CGPoint(x: 681, y: 317)), (39.7, CGPoint(x: 36, y: 232)),
    (40.3, CGPoint(x: 36, y: 232)), (40.8, CGPoint(x: 500, y: 708)), (43.0, CGPoint(x: 500, y: 708)), (43.2, CGPoint(x: 1108, y: 706)), (43.6, CGPoint(x: 1108, y: 706)),
    (48.9, CGPoint(x: 640, y: 480)), (49.5, sourceChip), (52.0, sourceChip), (52.5, CGPoint(x: 500, y: 708)),
    (53.9, CGPoint(x: 500, y: 708)), (56.2, CGPoint(x: 900, y: 500)), (57.0, figureKnob(57.0)),
]
func pointerAt(_ t: Double) -> CGPoint {
    if t >= 57.0 && t <= 59.6 { return figureKnob(t) }
    if t > 59.6 { return mix(figureKnob(59.6), CGPoint(x: 900, y: 880), inOutCubic(prog(t, 59.9, 61.2))) }
    guard let next = pointerPath.firstIndex(where: { $0.0 > t }), next > 0 else { return pointerPath.first!.1 }
    let (a, pa) = pointerPath[next - 1], (b, pb) = pointerPath[next]
    return mix(pa, pb, inOutCubic(prog(t, a, b)))
}

// MARK: - Opening

func openingTerms(_ t: Double, alpha: Double) {
    let terms = ["action potential", "synapse", "myelin sheath", "axon", "dendrite", "neurotransmitter", "depolarization", "node of Ranvier",
                 "refractory period", "sodium channel", "threshold", "动作电位", "突触", "髓鞘", "轴突", "시냅스", "Aktionspotential", "potentiel d'action",
                 "excitatory", "inhibitory", "saltatory conduction", "ion gradient", "repolarization", "Na⁺ / K⁺ pump", "postsynaptic", "all-or-none"]
    for (i, term) in terms.enumerated() {
        let depth = i % 3
        let size: CGFloat = [22, 32, 48][depth]
        let speed = [80.0, 170, 320][depth] * (hash(i, 1) < 0.5 ? 1 : -1)
        let span = Double(W) + 900
        var x = (hash(i, 3) * span + speed * t).truncatingRemainder(dividingBy: span)
        if x < 0 { x += span }
        text(term, x - 450, 60 + hash(i, 2) * 960, size, depth == 2 ? .semibold : .regular, color: depth == 0 ? sky : white, alpha: [0.13, 0.2, 0.28][depth] * alpha, anchor: 0.5)
    }
}
func handwriting(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, color: UInt32) {
    let f = CTFontCreateWithName("Noteworthy-Light" as CFString, size, nil)
    let l = makeLine(s, f)
    state {
        c.translateBy(x: x, y: y); c.scaleBy(x: 1, y: -1)
        c.textPosition = .zero
        c.setFillColor(rgb(color))
        CTLineDraw(l, c)
    }
}
func notebook(_ t: Double, enter: Double) {
    guard enter > 0 else { return }
    let e = spring(enter)
    let center = CGPoint(x: 1370, y: 545 + (1 - e) * 700)
    let r = CGRect(x: center.x - 330, y: center.y - 230, width: 660, height: 460)
    state {
        transform(at: center, scale: 1, rotate: 4 - 2 * e + (1 - e) * 10)
        state { c.setShadow(offset: CGSize(width: 0, height: -24), blur: 70, color: rgb(0, 0.6)); fillPath(roundRect(r, 18), 0xFAF7EF) }
        state {
            c.addPath(roundRect(r, 18)); c.clip()
            for i in 0..<9 { line(CGPoint(x: r.minX, y: r.minY + 56 + CGFloat(i) * 46), CGPoint(x: r.maxX, y: r.minY + 56 + CGFloat(i) * 46), 0x9DB9D3, 0.45, width: 1.5) }
            line(CGPoint(x: r.minX + 74, y: r.minY), CGPoint(x: r.minX + 74, y: r.maxY), 0xE5484D, 0.4, width: 1.5)
            let notes = ["Neurons - how they signal", "membrane → threshold", "fires an action pot—"]
            for (i, note) in notes.enumerated() {
                let k = prog(t, 2.9 + Double(i) * 0.55, 3.3 + Double(i) * 0.55)
                state {
                    let w = measure(note, 34, .regular) * 1.2
                    c.clip(to: CGRect(x: r.minX + 90, y: r.minY + 60 + CGFloat(i) * 92 - 50, width: w * k, height: 100))
                    handwriting(note, r.minX + 94, r.minY + 96 + CGFloat(i) * 92, 34, color: 0x24374A)
                }
            }
            // The writing has stopped; the next lines never come.
            let pen = CGPoint(x: r.minX + 455, y: r.minY + 290)
            line(pen, CGPoint(x: pen.x + 90, y: pen.y - 130), 0x24374A, 0.9, width: 12)
            line(pen, CGPoint(x: pen.x + 7, y: pen.y - 10), 0x111418, 1, width: 5)
            text("???", r.minX + 94, r.minY + 420, 40, .bold, color: red, alpha: prog(t, 4.6, 4.9), rounded: true)
        }
    }
}
func sceneOpen(_ t: Double) {
    backdrop(t)
    let fade = prog(t, 5.5, 6.0)
    openingTerms(t, alpha: outCubic(prog(t, 0.2, 1.4)) * (1 - fade))
    let shift = inOutCubic(prog(t, 2.5, 3.1))
    let x = mix(W / 2, 110, shift)
    let anchor = mix(0.5, 0, shift)
    group(1 - fade) {
        state {
            c.addRect(full); c.setFillColor(rgb(navy0, 0)); c.fillPath()
            glow(CGPoint(x: x + (anchor < 0.25 ? 390 : 0), y: 500), 800, navy0, 0.85)
            let starts = [0.25, 0.5, 0.75, 1.25]
            kinetic("The teacher talks fast.", x, mix(560, 420, shift), mix(124, 84, shift), .heavy, anchor: anchor, tracking: -1.6) { i, _ in
                let p = prog(t, starts[i], starts[i] + 0.35)
                var look = Look(scale: 1.5 - 0.5 * outExpo(p), alpha: min(1, p * 6), color: i == 3 ? leaf : white)
                if i == 3 { look.dx = CGFloat(sin(t * 95) * 8 * (1 - prog(t, 1.25, 1.6))) }
                return look
            }
            let second = prog(t, 3.0, 3.5)
            text("You can't listen and", 110, 530 + (1 - outCubic(second)) * 20, 52, .semibold, color: white, alpha: second)
            text("write at the same time.", 110, 596 + (1 - outCubic(second)) * 20, 52, .semibold, color: white, alpha: prog(t, 3.2, 3.7))
        }
    }
    group(1 - fade) { notebook(t, enter: prog(t, 2.6, 3.5)) }
}
func sceneLogo(_ t: Double) {
    backdrop(t)
    let local = t - 6
    let voice = outCubic(prog(local, 0, 0.5)), collapse = inCubic(prog(local, 0.55, 1.0))
    let leafAt = CGPoint(x: W / 2, y: 410)
    if local < 1.05 {
        for i in 0..<64 {
            let u = Double(i) / 63
            let envelope = exp(-pow((u - 0.5) / 0.3, 2))
            let wave = (0.55 + 0.45 * sin(Double(i) * 0.52 + t * 7.1)) * (0.6 + 0.4 * sin(Double(i) * 0.19 - t * 4.3 + 1))
            let h = mix(8 + voice * 280 * envelope * wave, 16, collapse)
            let x0 = W / 2 + (CGFloat(i) - 31.5) * 22
            let bar = CGRect(x: mix(x0, W / 2, collapse) - 4.5, y: leafAt.y - h / 2, width: 9, height: h)
            fillPath(roundRect(bar, 4.5), blend(sky, leaf, u), voice)
        }
    }
    let bloom = local - 1.0
    guard bloom > 0 else { return }
    for k in 0..<3 {
        let p = prog(bloom, Double(k) * 0.07, Double(k) * 0.07 + 1.2)
        if p > 0 && p < 1 { ring(leafAt, 30 + 950 * outExpo(p), [mint, leaf, sky][k], 0.65 * (1 - p), width: 9 * (1 - p) + 1) }
    }
    let land = inOutCubic(prog(t, 9.5, 10.4))
    let target = toScreen(CGPoint(x: 36, y: 58), 10)
    let height = mix(330 * outBack(prog(bloom, 0, 0.6)), 30 * wide.scale, land)
    glow(mix(leafAt, target, land), 420 * outCubic(prog(bloom, 0, 0.6)) * (1 - land), leaf, 0.42)
    let out = prog(t, 9.2, 9.5)
    kinetic("Nomi", W / 2, 730, 142, .bold, anchor: 0.5, rounded: true, tracking: -2, characters: true) { i, _ in
        let p = outCubic(prog(bloom, 0.25 + Double(i) * 0.06, 0.7 + Double(i) * 0.06))
        return Look(dy: (1 - p) * 60, scale: 0.9 + 0.1 * p, alpha: p * (1 - out), color: white)
    }
    let tag = outCubic(prog(bloom, 0.7, 1.15))
    text("Understand every lecture, in your own language.", W / 2, 806 + (1 - tag) * 18, 36, .regular, color: ice, alpha: tag * (1 - out), anchor: 0.5)
    if t > 9.7 { appWindow(t, alpha: prog(t, 9.7, 10.3)) }
    drawLeaf(at: mix(leafAt, target, land), height: height, rotate: mix(-50, 0, outCubic(prog(bloom, 0, 0.7))), highlight: outCubic(prog(bloom, 0.25, 0.6)))
}

// MARK: - End card

func sceneEnd(_ t: Double) {
    let local = t - 63
    radialBackground(blend(navy1, blue, 0.6), navy0, at: CGPoint(x: W / 2, y: 400), radius: 1250)
    state {
        c.translateBy(x: W / 2, y: 400)
        c.rotate(by: t * 0.05)
        for i in 0..<12 {
            let a = Double(i) / 12 * 2 * .pi
            let p = CGMutablePath(); p.move(to: .zero)
            p.addLine(to: CGPoint(x: cos(a - 0.07) * 1700, y: sin(a - 0.07) * 1700)); p.addLine(to: CGPoint(x: cos(a + 0.07) * 1700, y: sin(a + 0.07) * 1700)); p.closeSubpath()
            fillPath(p, sky, 0.035 * prog(local, 0.2, 1.2))
        }
    }
    glow(CGPoint(x: W / 2, y: 400), 460, leaf, 0.4)
    drawLeaf(at: CGPoint(x: W / 2, y: 330), height: 290 * outBack(prog(local, 0, 0.55)), rotate: 2 * sin(t * 1.3))
    kinetic("Nomi", W / 2, 640, 132, .bold, anchor: 0.5, rounded: true, tracking: -2, characters: true) { i, _ in
        let p = outCubic(prog(local, 0.25 + Double(i) * 0.06, 0.7 + Double(i) * 0.06))
        return Look(dy: (1 - p) * 60, alpha: p, color: white)
    }
    let tag = outCubic(prog(local, 0.75, 1.2))
    text("Understand every lecture, in your own language.", W / 2, 720 + (1 - tag) * 16, 38, .regular, color: white, alpha: 0.92 * tag, anchor: 0.5)
    let zh = outCubic(prog(local, 1.0, 1.45))
    text("用母语听懂每一节课", W / 2, 774 + (1 - zh) * 16, 30, .medium, color: mint, alpha: zh, anchor: 0.5, tracking: 4)
    let cta = spring(prog(local, 1.4, 2.1))
    if cta > 0 {
        let label = "Free download  ·  nomi.software"
        let w = measure(label, 31, .semibold) + 90
        let r = CGRect(x: W / 2 - w / 2, y: 830, width: w, height: 72)
        state {
            transform(at: CGPoint(x: r.midX, y: r.midY), scale: cta)
            state { c.setShadow(offset: .zero, blur: 40, color: rgb(leaf, 0.6)); fillPath(roundRect(r, 36), leaf) }
            text(label, r.midX, r.midY + 11, 31, .semibold, color: white, anchor: 0.5)
        }
    }
    text("macOS 26  ·  Apple silicon  ·  MIT", W / 2, 966, 21, .medium, color: ice, alpha: 0.6 * prog(local, 1.8, 2.2), anchor: 0.5, tracking: 3)
    fill(leaf, 1 - prog(local, 0, 0.32))
}

// MARK: - Timeline

func captionsAndPointer(_ t: Double) {
    headline("Live transcription.", "Words appear as the teacher speaks, with the translation underneath.", t, from: 10.6, to: 16.7, accentFrom: 1)
    // The close-up on the transcript leaves room on the left for the promise.
    let close = prog(t, 18.0, 18.6) * (1 - prog(t, 24.2, 24.7))
    if close > 0 {
        group(close) {
            wipeText("Hear it.", 110, 380, 84, .heavy, color: white, progress: prog(t, 18.2, 18.8))
            wipeText("Read it.", 110, 480, 84, .heavy, color: white, progress: prog(t, 18.7, 19.3))
            wipeText("Understand it.", 110, 580, 84, .heavy, color: mint, progress: prog(t, 19.2, 19.8))
            let p = outCubic(prog(t, 20.2, 20.8))
            let a = CGRect(x: 110, y: 640 + (1 - p) * 14, width: measure("Pause and resume anytime", 22, .medium) + 36, height: 44)
            pill(a, fill: white, 0.1 * p)
            text("Pause and resume anytime", a.minX + 18, a.midY + 7.5, 22, .medium, color: ice, alpha: p)
            let q = outCubic(prog(t, 20.6, 21.2))
            let b = CGRect(x: 110, y: 696 + (1 - q) * 14, width: measure("AirPods and Bluetooth mics", 22, .medium) + 36, height: 44)
            pill(b, fill: white, 0.1 * q)
            text("AirPods and Bluetooth mics", b.minX + 18, b.midY + 7.5, 22, .medium, color: ice, alpha: q)
        }
    }
    headline("The teacher's questions, answered.", "Real questions only. Not “right?” or “can you hear me?”", t, from: 25.8, to: 30.6, accentFrom: 3)
    lowerCaption("Every real question gets its answer.", t, from: 31.2, to: 34.0)
    headline("Jump to the moment it was asked.", nil, t, from: 34.8, to: 39.4, accentFrom: 3)
    headline("Ask about anything you recorded.", "Lectures, earlier chats and files, all searched together.", t, from: 40.2, to: 46.0, accentFrom: 3)
    lowerCaption("See where every part of the answer came from.", t, from: 47.0, to: 51.6)
    headline("Some ideas are easier to see.", "The answer comes with a small interactive page.", t, from: 52.8, to: 56.9, accentFrom: 3)
    lowerCaption("Drag it. Watch the concept move.", t, from: 58.0, to: 61.6)

    let visible = prog(t, 10.6, 11.0) * (1 - prog(t, 14.4, 14.8)) + prog(t, 34.8, 35.2) * (1 - prog(t, 60.8, 61.2))
    if visible > 0 {
        let press = [13.0, 36.0, 40.0, 43.2, 49.5].contains { abs(t - $0) < 0.1 } || (t >= 57.0 && t <= 59.5) ? 1.0 : 0.0
        let cam = toScreen(pointerAt(t), t)
        pointer(cam, press: press, alpha: min(visible, 1))
        for at in [13.0, 36.0, 40.0, 43.2, 49.5] { clickRipple(cam, t, at: at) }
    }
}
func scenePushIntoLeaf(_ t: Double) {
    // The take ends by flying into the leaf in the top bar, so the green fills the screen.
    let k = inExpo(prog(t, 62.4, 63.0))
    let base = wide
    let scale = base.scale * (1 + k * 120)
    let leafPoint = CGPoint(x: 36, y: 58)
    let screen = toScreen(leafPoint, 62.4)
    state {
        c.translateBy(x: mix(screen.x, W / 2, k), y: mix(screen.y, H / 2, k))
        c.scaleBy(x: scale / base.scale, y: scale / base.scale)
        c.translateBy(x: -screen.x, y: -screen.y)
        backdrop(t)
        appWindow(62.4)
    }
}
func frame(_ t: Double) {
    c.saveGState()
    if t < 6 { sceneOpen(t) }
    else if t < 10.4 { sceneLogo(t) }
    else if t < 62.4 {
        backdrop(t)
        appWindow(t)
        captionsAndPointer(t)
    }
    else if t < 63 { scenePushIntoLeaf(t) }
    else { sceneEnd(t) }
    let v = CGGradient(colorsSpace: space, colors: [rgb(0, 0), rgb(0, 0), rgb(0, 0.28)] as CFArray, locations: [0, 0.6, 1])!
    c.drawRadialGradient(v, startCenter: center, startRadius: 0, endCenter: center, endRadius: 1200, options: [.drawsAfterEndLocation])
    fill(0, prog(t, 69.3, 70))
    fill(0, 1 - prog(t, 0, 0.3))
    c.restoreGState()
}
// MARK: - Film grain

let grains: [CGImage] = (0..<6).map { seed in
    let w = 960, h = 540
    var pixels = [UInt8](repeating: 255, count: w * h * 4)
    for i in 0..<(w * h) {
        let v = UInt8(128 + Int((hash(i, seed * 7 + 101) - 0.5) * 255))
        pixels[i * 4] = v; pixels[i * 4 + 1] = v; pixels[i * 4 + 2] = v
    }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

/// Renders one output frame: several sub-frames averaged for motion blur, then grain.
func render(_ index: Int) -> CGImage {
    // The drops, the fly-through and the big zoom move fast enough to need more samples.
    let time = Double(index) / fps
    let fast = [(62.4, 63.0)].contains { time >= $0.0 && time < $0.1 }
    let samples = ProcessInfo.processInfo.environment["PROMO_DRAFT"] != nil ? 1 : (fast ? 12 : subframes)  // PROMO_DRAFT skips motion blur for quick previews
    for s in 0..<samples {
        let t = (Double(index) + shutter * Double(s) / Double(samples)) / fps
        frame(t)
        let image = c.makeImage()!
        accumulator.saveGState()
        accumulator.setAlpha(1 / CGFloat(s + 1))
        accumulator.draw(image, in: full)
        accumulator.restoreGState()
    }
    accumulator.saveGState()
    accumulator.setBlendMode(.overlay)
    accumulator.setAlpha(0.06)
    accumulator.draw(grains[index % grains.count], in: full)
    accumulator.restoreGState()
    return accumulator.makeImage()!
}

let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--stills") {
    let times = arguments[flag + 1].split(separator: ",").compactMap { Double($0) }
    let folder = URL(fileURLWithPath: arguments[flag + 2])
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for time in times {
        let image = render(Int((time * fps).rounded()))
        let url = folder.appendingPathComponent(String(format: "still-%05.2f.png", time))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        FileHandle.standardError.write("wrote \(url.lastPathComponent)\n".data(using: .utf8)!)
    }
} else {
    let out = FileHandle.standardOutput
    let start = Date()
    for index in 0..<frameCount {
        _ = render(index)
        out.write(Data(bytes: accumulator.data!, count: Int(W) * Int(H) * 4))
        if index % 90 == 89 { FileHandle.standardError.write(String(format: "rendered %d/%d frames, %.0fs\n", index + 1, frameCount, Date().timeIntervalSince(start)).data(using: .utf8)!) }
    }
}
