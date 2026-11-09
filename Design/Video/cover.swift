// Draws the social media cover for the promo video, using the same helpers as promo.swift.
// Build: swiftc -O Design/Video/cover.swift -o build/promo-cover
// 16:9: build/promo-cover build/Nomi-cover-16x9.png    3:4: build/promo-cover --portrait build/Nomi-cover-3x4.png
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

let portrait = CommandLine.arguments.contains("--portrait")
let W: CGFloat = portrait ? 1080 : 1920, H: CGFloat = portrait ? 1440 : 1080
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


// MARK: - Cover

let lightInk: UInt32 = 0x111418, lightSec: UInt32 = 0x5E6670, lightAccent: UInt32 = 0x004A77, lightSel: UInt32 = 0xC2E8FF, sunny: UInt32 = 0xFFD23F
/// Chinese in PingFang, so the heavy headline keeps its weight.
func hanzi(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, color: UInt32, anchor: CGFloat = 0, face: String = "PingFangSC-Semibold") -> CGFloat {
    let l = makeLine(s, CTFontCreateWithName(face as CFString, size, nil))
    let w = width(l)
    state {
        c.translateBy(x: x, y: y); c.scaleBy(x: 1, y: -1)
        c.textPosition = CGPoint(x: -w * anchor, y: 0)
        c.setFillColor(rgb(color))
        CTLineDraw(l, c)
    }
    return w
}
func appWindow(_ r: CGRect, _ k: CGFloat) {
    state { c.setShadow(offset: CGSize(width: 0, height: -30 * k), blur: 90 * k, color: rgb(0x0A1020, 0.4)); fillPath(roundRect(r, 26 * k), white) }
    state {
        c.addPath(roundRect(r, 26 * k)); c.clip()
        fill(0xF4F7FB, 1, CGRect(x: r.minX, y: r.minY, width: r.width, height: 84 * k))
        line(CGPoint(x: r.minX, y: r.minY + 84 * k), CGPoint(x: r.maxX, y: r.minY + 84 * k), 0xD5DCE6, 1, width: 2)
        for (i, color) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() { circle(CGPoint(x: r.minX + (36 + CGFloat(i) * 30) * k, y: r.minY + 42 * k), 10 * k, color) }
        text("Biology 101 · Neurons", r.minX + 146 * k, r.minY + 52 * k, 28 * k, .semibold, color: lightSec)
        // The recording capsule.
        let capsule = CGRect(x: r.minX + 600 * k, y: r.minY + 20 * k, width: 216 * k, height: 44 * k)
        pill(capsule, lightSel)
        for i in 0..<6 {
            let h = [10.0, 20, 14, 24, 12, 18][i] * k
            fillPath(roundRect(CGRect(x: capsule.minX + (22 + CGFloat(i) * 9) * k, y: capsule.midY - h / 2, width: 5 * k, height: h), 2.5 * k), lightAccent)
        }
        text("12:27", capsule.minX + 92 * k, capsule.midY + 9 * k, 26 * k, .semibold, color: lightAccent)
        circle(CGPoint(x: capsule.maxX - 22 * k, y: capsule.midY), 9 * k, red)

        let x = r.minX + 44 * k
        var y = r.minY + 164 * k
        text("Today: how neurons pass signals.", x, y, 41 * k, .medium, color: lightInk)
        _ = hanzi("今天：神经元如何传递信号。", x, y + 58 * k, 40 * k, color: lightAccent, face: "PingFangSC-Medium")
        y += 174 * k
        let before = "A neuron fires an ", term = "action potential."
        let bw = measure(before, 41 * k, .medium), tw = measure(term, 41 * k, .medium)
        fillPath(roundRect(CGRect(x: x + bw - 6 * k, y: y - 38 * k, width: tw + 12 * k, height: 52 * k), 10 * k), 0xBFEBD8)
        text(before + term, x, y, 41 * k, .medium, color: lightInk)
        _ = hanzi("神经元会发出动作电位。", x, y + 58 * k, 40 * k, color: lightAccent, face: "PingFangSC-Medium")
        y += 174 * k
        let settled = "It races down ", draft = "the axon to"
        text(settled, x, y, 41 * k, .medium, color: lightInk)
        let sw = measure(settled, 41 * k, .medium), dw = measure(draft, 41 * k, .medium)
        text(draft, x + sw, y, 41 * k, .medium, color: draft2)
        line(CGPoint(x: x + sw + dw + 10 * k, y: y - 34 * k), CGPoint(x: x + sw + dw + 10 * k, y: y + 8 * k), leaf, 1, width: 4 * k)
    }
}
let draft2: UInt32 = 0xA9B1BC
func pill(_ r: CGRect, _ color: UInt32) { fillPath(roundRect(r, r.height / 2), color) }
func badge(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat) -> CGFloat {
    // Measure first, so the pill fits the words.
    let s = "免费开源 · Mac App"
    let w = width(makeLine(s, CTFontCreateWithName("PingFangSC-Semibold" as CFString, size, nil)))
    let r = CGRect(x: x, y: y, width: w + size * 1.1, height: size * 1.75)
    pill(r, 0x34C99B)
    _ = hanzi(s, r.minX + size * 0.55, r.midY + size * 0.36, size, color: navy0)
    return r.maxY
}
func outlined(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat) -> CGFloat {
    let w = width(makeLine(s, CTFontCreateWithName("PingFangSC-Medium" as CFString, size, nil)))
    let r = CGRect(x: x, y: y, width: w + size * 1.1, height: size * 1.85)
    strokePath(roundRect(r, 14), mint, 1, width: 3.5)
    _ = hanzi(s, r.minX + size * 0.55, r.midY + size * 0.36, size, color: white, face: "PingFangSC-Medium")
    return r.maxY
}
func signature(_ x: CGFloat, _ y: CGFloat, _ k: CGFloat) {
    drawLeaf(at: CGPoint(x: x + 26 * k, y: y - 16 * k), height: 58 * k)
    text("Nomi", x + 68 * k, y, 42 * k, .bold, color: white, rounded: true)
    text("nomi.software", x + 68 * k + measure("Nomi", 42 * k, .bold, rounded: true) + 24 * k, y, 32 * k, .medium, color: ice)
}

if portrait {
    // 3:4. Words on top, the app below.
    radialBackground(0x0E2A3E, navy0, at: CGPoint(x: 200, y: 200), radius: 1300)
    glow(CGPoint(x: 900, y: 1300), 800, sky, 0.5)
    glow(CGPoint(x: 120, y: 620), 520, leaf, 0.14)
    _ = badge(84, 64, 42)
    _ = hanzi("上课听不懂？", 84, 318, 150, color: white)
    _ = hanzi("Nomi 实时翻译", 84, 484, 124, color: sunny)
    _ = outlined("课堂问答 · 离线可用", 84, 530, 48)
    appWindow(CGRect(x: 84, y: 680, width: 1060, height: 626), 1.05)
    signature(84, 1392, 1)
} else {
    // 16:9. Dark words on the left, the bright app on the right, like a lit screen in a dark room.
    radialBackground(0x0E2A3E, navy0, at: CGPoint(x: 300, y: 240), radius: 1250)
    let g = CGGradient(colorsSpace: space, colors: [rgb(0xCFE6F7, 0), rgb(0xBFDDF3, 0.75), rgb(0xF4F7FB, 1)] as CFArray, locations: [0, 0.55, 1])!
    c.drawLinearGradient(g, start: CGPoint(x: 800, y: 0), end: CGPoint(x: 1500, y: 0), options: [.drawsAfterEndLocation])
    glow(CGPoint(x: 180, y: 900), 620, leaf, 0.16)
    let bottom = badge(84, 112, 40)
    _ = hanzi("上课听不懂？", 84, bottom + 170, 136, color: white)
    _ = hanzi("Nomi 实时翻译", 84, bottom + 330, 112, color: sunny)
    _ = outlined("课堂问答 · 离线可用", 84, bottom + 390, 46)
    signature(84, 968, 1)
    appWindow(CGRect(x: 985, y: 250, width: 1040, height: 640), 1.08)
}
let image = c.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments.last!)
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
