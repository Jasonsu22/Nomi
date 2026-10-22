// Renders the 30-second Nomi showreel, 1920 x 1080 at 30 fps, as raw BGRA frames on stdout.
// Build: swiftc -O Design/Video/render.swift -o build/showreel-render
// Video: build/showreel-render | ffmpeg -f rawvideo -pix_fmt bgra -s 1920x1080 -r 30 -i - ...
// Stills: build/showreel-render --stills 4.3,9.8 build/stills  (PNG per time, for review)
// See scripts/make-showreel.sh for the full pipeline with music.
//
// Timeline (120 BPM, so every cut sits on a beat of music.swift):
//   0-4    a voice: audio bars build, collapse into a seed      4-6    the leaf blooms, then flies through the camera
//   6-9    the problem: fast talk, a storm of new terms          9-13.5 the app: live transcript and translation
//   13.5-16 one term in many languages                           16-20  Q&A: real questions only, answered
//   20-24  ask about anything you recorded, with sources         24-26  four-beat montage
//   26-30  end card
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

let W: CGFloat = 1920, H: CGFloat = 1080
let fps = 30.0, frameCount = 900, subframes = 4, shutter = 0.5  // motion blur: 4 samples across half a frame
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

// MARK: - Scene 1 (0-4): a voice. Audio bars build, then collapse into one seed of light.

func hud(_ t: Double, alpha: Double) {
    group(alpha) {
        let inset: CGFloat = 64, arm: CGFloat = 36
        for (x, y, sx, sy) in [(inset, inset, 1.0, 1.0), (W - inset, inset, -1.0, 1.0), (inset, H - inset, 1.0, -1.0), (W - inset, H - inset, -1.0, -1.0)] {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x, y: y + arm * sy)); p.addLine(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + arm * sx, y: y))
            strokePath(p, white, 0.35, width: 2)
        }
        text("NOMI  /  SHOWREEL", inset + 56, inset + 24, 17, .semibold, color: white, alpha: 0.55, tracking: 4)
        let frames = Int(t * fps)
        text(String(format: "00:00:%02d:%02d", frames / 30, frames % 30), W - inset - 56, inset + 24, 17, .medium, color: white, alpha: 0.55, anchor: 1, tracking: 2)
        circle(CGPoint(x: inset + 62, y: H - inset - 30), 6, red, 0.6 + 0.4 * sin(t * 6))
        text("REC   BIOLOGY 101  ·  09:00", inset + 80, H - inset - 24, 17, .semibold, color: white, alpha: 0.55, tracking: 3)
        text("1920 × 1080  ·  30 FPS", W - inset - 56, H - inset - 24, 17, .medium, color: white, alpha: 0.45, anchor: 1, tracking: 3)
    }
}

func sceneVoice(_ t: Double) {
    radialBackground(navy1, navy0, radius: 1100)
    let build = inOutCubic(prog(t, 0.2, 3.0))
    let collapse = inCubic(prog(t, 3.15, 3.7))
    glow(center, 700, blue, 0.35 * build * (1 - collapse))
    let count = 64, spacing: CGFloat = 22
    if t < 3.72 {
        for i in 0..<count {
            let u = Double(i) / Double(count - 1)
            let envelope = exp(-pow((u - 0.5) / 0.3, 2))
            let wave = (0.55 + 0.45 * sin(Double(i) * 0.52 + t * 7.1)) * (0.6 + 0.4 * sin(Double(i) * 0.19 - t * 4.3 + 1))
            let flicker = 0.85 + 0.15 * sin(Double(i) * 2.7 + t * 23)
            var h = 8 + build * 300 * envelope * wave * flicker
            let x0 = W / 2 + (CGFloat(i) - CGFloat(count - 1) / 2) * spacing
            let x = mix(x0, W / 2, collapse)
            h = mix(h, 16, collapse)
            let color = blend(sky, leaf, u)
            let bar = CGRect(x: x - 4.5, y: H / 2 - h / 2, width: 9, height: h)
            fillPath(roundRect(bar, 4.5), color, 0.35 + 0.65 * build)
        }
    }
    // The seed: holds its breath, then the drop.
    if t >= 3.55 {
        let breathe = outCubic(prog(t, 3.7, 3.98))
        let r = 12 - 5 * breathe
        glow(center, 90 + 60 * breathe, leaf, 0.6 * prog(t, 3.55, 3.75))
        circle(center, r, mint)
    }
    // Caption above the bars.
    let captionIn = outCubic(prog(t, 0.6, 1.3)), captionOut = prog(t, 2.7, 3.1)
    kinetic("Every lecture starts with a voice.", W / 2, 300, 40, .medium, anchor: 0.5) { i, _ in
        let p = outCubic(prog(t, 0.6 + Double(i) * 0.08, 1.2 + Double(i) * 0.08))
        return Look(dy: (1 - p) * 24 - captionOut * 20, alpha: p * (1 - captionOut) * captionIn, color: white)
    }
    hud(t, alpha: prog(t, 0.2, 0.7) * (1 - prog(t, 3.3, 3.7)))
}

// MARK: - Scene 2 (4-6): the drop. The leaf blooms, then the camera flies through it.

func sceneBloom(_ t: Double) {
    let leafCenter = CGPoint(x: W / 2, y: 430)
    radialBackground(blend(navy1, blue, 0.55), navy0, at: leafCenter, radius: 1200)
    let local = t - 4
    // Shockwaves and sparks from the seed.
    for k in 0..<3 {
        let p = prog(local, Double(k) * 0.07, Double(k) * 0.07 + 1.3)
        if p > 0 && p < 1 { ring(leafCenter, 30 + 1000 * outExpo(p), [mint, leaf, sky][k], 0.7 * (1 - p), width: 10 * (1 - p) + 1) }
    }
    for i in 0..<110 {
        let angle = hash(i, 1) * 2 * .pi, speed = 500 + hash(i, 2) * 1300
        let life = 0.9 + hash(i, 3) * 0.9
        let p = local / life
        guard p > 0, p < 1 else { continue }
        let travel = speed * (1 - exp(-3.2 * local)) / 3.2
        let pos = CGPoint(x: leafCenter.x + cos(angle) * travel, y: leafCenter.y + sin(angle) * travel + 120 * local * local)
        let tail = CGPoint(x: pos.x - cos(angle) * 26 * (1 - p), y: pos.y - sin(angle) * 26 * (1 - p))
        line(tail, pos, [mint, white, sky, leaf][i % 4], 0.85 * (1 - p), width: 2 + 3 * hash(i, 4))
    }
    let zoom = inExpo(prog(t, 5.42, 6.0))
    let grow = outBack(prog(local, 0, 0.6))
    let height = 330 * grow
    let rotation = mix(-50, 0, outCubic(prog(local, 0, 0.7))) + 2 * sin(local * 2.4) + zoom * 30
    glow(leafCenter, 420 * grow, leaf, 0.45 * (1 - zoom))
    // During the fly-through the camera locks onto a point inside the leaf and pushes in.
    let b = leafShape.bounds
    let inside = leafShape.inside
    let scale = height / b.height
    let offset = CGPoint(x: (inside.x - b.midX) * scale, y: (inside.y - b.midY) * scale)
    let angle = rotation * .pi / 180
    let insideOnScreen = CGPoint(x: leafCenter.x + offset.x * cos(angle) - offset.y * sin(angle), y: leafCenter.y + offset.x * sin(angle) + offset.y * cos(angle))
    drawLeaf(at: mix(insideOnScreen, center, zoom), height: height * (1 + zoom * 70), rotate: rotation, anchor: inside, highlight: outCubic(prog(local, 0.3, 0.7)))
    // Wordmark and line.
    let textOut = prog(t, 5.25, 5.5)
    kinetic("Nomi", W / 2, 750, 150, .bold, anchor: 0.5, rounded: true, tracking: -2, characters: true) { i, _ in
        let p = outCubic(prog(local, 0.3 + Double(i) * 0.06, 0.75 + Double(i) * 0.06))
        return Look(dy: (1 - p) * 70, scale: 0.9 + 0.1 * p, alpha: p * (1 - textOut), color: white)
    }
    let tag = outCubic(prog(local, 0.75, 1.2))
    text("Understand every lecture, in your own language.", W / 2, 830 + (1 - tag) * 20, 36, .regular, color: ice, alpha: tag * (1 - textOut), anchor: 0.5)
    fill(white, 0.55 * (1 - prog(local, 0, 0.22)))  // flash on the drop
}

// MARK: - Scene 3 (6-9): the problem. Fast talk and a storm of new words.

let terms = ["action potential", "synapse", "myelin sheath", "axon", "dendrite", "neurotransmitter", "depolarization", "node of Ranvier",
             "refractory period", "sodium channel", "threshold", "soma", "glial cell", "动作电位", "突触", "髓鞘", "轴突", "樹状突起", "시냅스",
             "Aktionspotential", "potentiel d'action", "neurona", "нейрон", "excitatory", "inhibitory", "saltatory conduction", "membrane",
             "ion gradient", "repolarization", "Na⁺ / K⁺ pump", "电压门控", "postsynaptic", "골지체", "graded potential", "all-or-none"]

func sceneProblem(_ t: Double) {
    radialBackground(navy1, navy0, radius: 1200)
    let suck = inCubic(prog(t, 8.45, 8.95))
    let storm = outCubic(prog(t, 6.1, 7.6))
    for (i, term) in terms.enumerated() {
        let depth = i % 3
        let size: CGFloat = [24, 38, 62][depth]
        let speed = [70.0, 140, 260][depth] * (hash(i, 1) < 0.5 ? 1 : -1) * (1 + storm)
        let span = Double(W) + 900
        var x = (hash(i, 3) * span + speed * (t - 6)).truncatingRemainder(dividingBy: span)
        if x < 0 { x += span }
        x -= 450
        let y = 70 + hash(i, 2) * 940
        var p = CGPoint(x: x, y: y)
        p = mix(p, center, suck)
        let alpha = [0.16, 0.26, 0.4][depth] * storm * (1 - suck * 0.6)
        text(term, p.x, p.y, size, depth == 2 ? .semibold : .regular, color: depth == 0 ? sky : white, alpha: alpha, anchor: 0.5, scale: 1 - suck * 0.85)
    }
    // A soft dark band keeps the headline readable over the storm.
    state {
        transform(at: CGPoint(x: W / 2, y: 540), scale: 1)
        c.translateBy(x: W / 2, y: 545); c.scaleBy(x: 1, y: 0.42); c.translateBy(x: -W / 2, y: -545)
        glow(CGPoint(x: W / 2, y: 545), 1000, navy0, 0.92 * storm * (1 - suck))
    }
    // Headline, word by word on the beat.
    group(1 - suck) {
        state {
            transform(at: center, scale: 1 - suck * 0.7)
            let lift = outCubic(prog(t, 7.3, 7.6))
            let y1 = 560 - 90 * lift
            let starts = [6.02, 6.27, 6.52, 7.0]
            kinetic("The teacher talks fast.", W / 2, y1, 124, .heavy, anchor: 0.5, tracking: -2) { i, _ in
                let p = prog(t, starts[i], starts[i] + 0.35)
                let land = outExpo(p)
                var look = Look(scale: 1.6 - 0.6 * land, alpha: min(1, p * 6), color: i == 3 ? leaf : white)
                if i == 3 { look.dx = CGFloat(sin(t * 95) * 9 * (1 - prog(t, 7.0, 7.35))) }
                return look
            }
            // Speed lines behind "fast.".
            let streak = prog(t, 7.0, 7.45)
            if streak > 0 && streak < 1 {
                let (parts, total) = pieces("The teacher talks fast.", 124, .heavy, tracking: -2)
                let fastLeft = W / 2 - total / 2 + parts[3].offset
                for k in 0..<5 {
                    let y = y1 - 90 + CGFloat(k) * 22
                    let length = (260 + hash(k, 9) * 200) * (1 - outCubic(streak))
                    line(CGPoint(x: fastLeft - 30 - length, y: y), CGPoint(x: fastLeft - 30, y: y), mint, 0.7 * (1 - streak), width: 4)
                }
            }
            let starts2 = [7.5, 7.75, 8.0]
            kinetic("New words everywhere.", W / 2, y1 + 150, 96, .semibold, anchor: 0.5, tracking: -1) { i, _ in
                let p = prog(t, starts2[i], starts2[i] + 0.3)
                return Look(dy: (1 - outExpo(p)) * 60, alpha: min(1, p * 5), color: i == 2 ? sky : white)
            }
        }
    }
    // Iris opening out of the leaf green from the previous shot.
    let iris = outCubic(prog(t, 6.0, 6.42))
    if iris < 1 {
        let r = 1200 * iris
        let p = CGMutablePath(); p.addRect(full); p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        c.addPath(p); c.setFillColor(rgb(leaf)); c.fillPath(using: .evenOdd)
    }
}

// MARK: - Scene 4 (9-13.5): the app. Live transcript, then a zoom into one term.

let window = CGRect(x: 850, y: 235, width: 960, height: 600)
let transcript: [(String, String, String, Double)] = [
    ("0:12", "Today: how neurons pass signals.", "今天：神经元如何传递信号。", 9.55),
    ("0:19", "A neuron fires an action potential.", "神经元会发出动作电位。", 10.5),
    ("0:27", "It races down the axon to the synapse.", "它沿着轴突一路传到突触。", 11.45),
]
func transcriptBaseline(_ index: Int) -> CGFloat { window.minY + 170 + CGFloat(index) * 150 }
let sourceX = window.minX + 130
/// The highlighted term on line 2, in screen space before the camera moves.
let termRect: CGRect = {
    let (parts, _) = pieces(transcript[1].1, 32, .regular)
    let start = parts[4].offset, end = parts[5].offset + parts[5].width - 10
    let y = transcriptBaseline(1)
    return CGRect(x: sourceX + start - 8, y: y - 34, width: end - start + 16, height: 46)
}()

func sceneApp(_ t: Double) {
    let push = 1 + 0.05 * inOutCubic(prog(t, 9.0, 12.6))
    let zoom = inExpo(prog(t, 12.75, 13.5))
    let focus = mix(center, CGPoint(x: termRect.midX, y: termRect.midY), outCubic(prog(t, 12.45, 13.25)))
    state {
        c.translateBy(x: W / 2, y: H / 2)
        c.scaleBy(x: push * (1 + zoom * 34), y: push * (1 + zoom * 34))
        c.translateBy(x: -focus.x, y: -focus.y)
        verticalGradient(paper, paper2, full.insetBy(dx: -400, dy: -300))
        // Soft drifting color fields.
        glow(CGPoint(x: 360 + 60 * sin(t * 0.7), y: 860), 620, leaf, 0.14)
        glow(CGPoint(x: 1600, y: 160 + 40 * cos(t * 0.6)), 700, sky, 0.22)

        // Left column: the promise, line by line.
        let headOut = prog(t, 12.4, 12.8)
        group(1 - headOut) {
            text("LIVE TRANSCRIPTION  +  TRANSLATION", 140, 330, 21, .bold, color: blue, alpha: outCubic(prog(t, 9.2, 9.6)), tracking: 4)
            wipeText("Hear it.", 140, 450, 92, .heavy, color: ink, progress: prog(t, 9.35, 9.85))
            wipeText("Read it.", 140, 560, 92, .heavy, color: ink, progress: prog(t, 9.85, 10.35))
            wipeText("Understand it.", 140, 670, 92, .heavy, color: leaf, progress: prog(t, 10.35, 10.85))
            let note = outCubic(prog(t, 10.9, 11.4))
            text("Recognition runs on your Mac, even offline.", 140, 750 + (1 - note) * 16, 27, .regular, color: gray, alpha: note)
        }

        // The window springs up from below.
        let enter = spring(prog(t, 9.0, 10.0))
        state {
            c.translateBy(x: 0, y: (1 - enter) * 560)
            transform(at: CGPoint(x: window.midX, y: window.midY), rotate: (1 - outCubic(prog(t, 9.0, 9.8))) * 7)
            let shape = roundRect(window, 26)
            state { shadow(blur: 60, y: 30, alpha: 0.22); fillPath(shape, white) }
            state {
                c.addPath(shape); c.clip()
                fill(0xF6F8FB, 1, CGRect(x: window.minX, y: window.minY, width: window.width, height: 76))
                line(CGPoint(x: window.minX, y: window.minY + 76), CGPoint(x: window.maxX, y: window.minY + 76), 0xD5DCE6, 1, width: 1.5)
            }
            strokePath(shape, 0xD5DCE6, 1, width: 1.5)
            for (k, color) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() { circle(CGPoint(x: window.minX + 36 + CGFloat(k) * 24, y: window.minY + 38), 7.5, UInt32(color)) }
            text("Biology 101 · Neurons", window.minX + 128, window.minY + 46, 21, .semibold, color: 0x5B6470)
            // Recording pill with live level bars and a running clock.
            let pill = CGRect(x: window.maxX - 214, y: window.minY + 18, width: 184, height: 40)
            fillPath(roundRect(pill, 20), ice)
            circle(CGPoint(x: pill.minX + 22, y: pill.midY), 6.5, red, 0.55 + 0.45 * sin(t * 6))
            for k in 0..<9 {
                let h = 6 + 16 * abs(sin(t * 9 + Double(k) * 0.9)) * (0.5 + 0.5 * sin(t * 3.1 + Double(k)))
                fillPath(roundRect(CGRect(x: pill.minX + 40 + CGFloat(k) * 7, y: pill.midY - h / 2, width: 3.4, height: h), 1.7), 0x17587E)
            }
            let seconds = 4 + Int(t - 9)
            text(String(format: "12:%02d", seconds), pill.maxX - 18, pill.midY + 7, 19, .bold, color: 0x17587E, anchor: 1)

            // Highlight behind the key term.
            let mark = outCubic(prog(t, 12.15, 12.5))
            if mark > 0 { fillPath(roundRect(CGRect(x: termRect.minX, y: termRect.minY, width: termRect.width * mark, height: termRect.height), 10), mint, 0.95) }

            for (index, entry) in transcript.enumerated() {
                let (stamp, source, translation, start) = entry
                let y = transcriptBaseline(index)
                let words = source.components(separatedBy: " ").count
                text(stamp, window.minX + 44, y, 19, .semibold, color: gray, alpha: prog(t, start - 0.05, start + 0.15))
                kinetic(source, sourceX, y, 32, .regular) { i, _ in
                    let appear = start + Double(i) * 0.09
                    let p = prog(t, appear, appear + 0.12)
                    let settle = prog(t, appear + 0.45, appear + 0.7)
                    return Look(dy: (1 - outCubic(p)) * 10, alpha: p, color: blend(draft, ink, settle))
                }
                // Typing caret while the line is still being heard.
                let end = start + Double(words) * 0.09 + 0.15
                if t > start && t < end + 0.2 {
                    let (parts, _) = pieces(source, 32, .regular)
                    let shown = min(parts.count - 1, Int((t - start) / 0.09))
                    let x = sourceX + parts[shown].offset + parts[shown].width + 6
                    fillPath(roundRect(CGRect(x: x, y: y - 28, width: 3, height: 36), 1.5), blue, (sin(t * 18) > -0.3 ? 1 : 0.2))
                }
                let tr = outCubic(prog(t, end + 0.25, end + 0.6))
                text(translation, sourceX, y + 46 + (1 - tr) * 12, 27, .regular, color: blue, alpha: tr)
            }
        }
    }
}

// MARK: - Scene 5 (13.5-16): one term, many languages.

let languages: [(Double, String, String)] = [
    (13.95, "ZH", "动作电位"), (14.5, "JA", "活動電位"), (14.75, "KO", "활동 전위"), (15.0, "DE", "Aktionspotential"),
    (15.25, "FR", "potentiel d'action"), (15.5, "ES", "potencial de acción"), (15.75, "ZH", "动作电位"),
]

func sceneLanguages(_ t: Double) {
    verticalGradient(mint, 0xB8EBD2)
    // Faint drifting rings in the background.
    for k in 0..<4 { ring(CGPoint(x: 1620, y: 220), 140 + CGFloat(k) * 120 + CGFloat((t - 13.5) * 40), white, 0.25, width: 2) }
    let labels = outCubic(prog(t, 13.7, 14.0))
    text("TRANSLATION, UNDER EVERY LINE", 140, 150, 21, .bold, color: ink, alpha: 0.6 * labels, tracking: 4)
    text("Chinese · English · Japanese · Korean · German · French · Spanish · Russian · Arabic", 140, 186, 21, .medium, color: ink, alpha: 0.42 * labels)
    let settle = outExpo(prog(t, 13.5, 13.95))
    text("action potential", W / 2, 470, 172, .heavy, color: ink, anchor: 0.5, tracking: -4, scale: 1 + 2.4 * (1 - settle))
    // The bar slides in, then the translation rolls through languages like a split-flap board.
    let bar = CGRect(x: 0, y: 575, width: W * outExpo(prog(t, 13.8, 14.2)), height: 250)
    fill(blue, 1, bar)
    guard bar.width > 0 else { return }
    state {
        c.clip(to: bar)
        var current = 0
        for (k, entry) in languages.enumerated() where t >= entry.0 { current = k }
        let roll = outCubic(prog(t, languages[current].0, languages[current].0 + 0.16))
        func slot(_ k: Int, _ dy: CGFloat, _ alpha: Double) {
            let (_, code, word) = languages[k]
            let chip = CGRect(x: 140, y: 668 + dy, width: 92, height: 54)
            strokePath(roundRect(chip, 27), mint, alpha, width: 2.5)
            text(code, chip.midX, chip.midY + 10 + dy * 0, 26, .bold, color: mint, alpha: alpha, anchor: 0.5, tracking: 2)
            text(word, W / 2 + 70, 745 + dy, 124, .semibold, color: white, alpha: alpha, anchor: 0.5, tracking: -1)
        }
        if current > 0 && roll < 1 { slot(current - 1, -roll * 220, 1 - roll) }
        slot(current, (1 - roll) * 220, current == 0 ? prog(t, 13.95, 14.1) : roll)
    }
}

// MARK: - Scene 6 (16-20): Q&A. Filler questions fall away; the real one gets answered.

let answer = "Myelin insulates the axon, so the signal jumps from gap to gap (the nodes of Ranvier) instead of creeping along. That is saltatory conduction."

func sceneQA(_ t: Double) {
    fill(paper)
    for gx in 0..<41 { for gy in 0..<23 {
        circle(CGPoint(x: CGFloat(gx) * 48 + CGFloat((t * 6).truncatingRemainder(dividingBy: 48)), y: CGFloat(gy) * 48 + 20), 1.7, 0xD3DBE5)
    } }
    // Headline.
    let chipIn = spring(prog(t, 16.1, 16.6))
    state {
        let chip = CGRect(x: 140, y: 268, width: 112, height: 46)
        transform(at: CGPoint(x: chip.midX, y: chip.midY), scale: chipIn)
        fillPath(roundRect(chip, 23), blue)
        text("Q&A", chip.midX, chip.midY + 9, 24, .bold, color: white, anchor: 0.5, tracking: 2)
    }
    wipeText("The teacher's", 140, 420, 90, .heavy, color: ink, progress: prog(t, 16.15, 16.6))
    wipeText("questions,", 140, 525, 90, .heavy, color: ink, progress: prog(t, 16.35, 16.8))
    wipeText("answered.", 140, 630, 90, .heavy, color: leaf, progress: prog(t, 16.6, 17.05))
    let sub = outCubic(prog(t, 17.6, 18.0))
    text("Real questions only. Never “right?”", 140, 712 + (1 - sub) * 14, 29, .regular, color: gray, alpha: sub)

    // Filler questions fly in, get struck out, and drop.
    let fillers: [(String, CGPoint)] = [("right?", CGPoint(x: 1090, y: 250)), ("can you hear me?", CGPoint(x: 1420, y: 175)), ("okay?", CGPoint(x: 1660, y: 290))]
    for (k, filler) in fillers.enumerated() {
        let arrive = spring(prog(t, 16.35 + Double(k) * 0.12, 17.0 + Double(k) * 0.12))
        guard arrive > 0 else { continue }
        let fall = max(0, t - (17.35 + Double(k) * 0.08))
        let w = measure(filler.0, 30, .medium) + 56
        let p = CGPoint(x: filler.1.x + (1 - arrive) * 900, y: filler.1.y + 2400 * fall * fall)
        state {
            transform(at: p, rotate: fall * (k == 1 ? -200 : 160))
            let r = CGRect(x: p.x - w / 2, y: p.y - 29, width: w, height: 58)
            fillPath(roundRect(r, 29), 0xE3E9F0)
            text(filler.0, p.x, p.y + 10, 30, .medium, color: 0x5B6470, anchor: 0.5)
            let strike = outCubic(prog(t, 17.05 + Double(k) * 0.06, 17.3 + Double(k) * 0.06))
            if strike > 0 { line(CGPoint(x: r.minX + 18, y: p.y), CGPoint(x: r.minX + 18 + (w - 36) * strike, y: p.y), red, 0.9, width: 4) }
        }
    }

    // The real question: two cards stacked behind, the main card in front.
    let card = CGRect(x: 975, y: 365, width: 800, height: 440)
    let behind: [(String, Double, CGFloat, Double)] = [("Why is there a refractory period?", 17.5, -130, 3), ("What happens at the synapse?", 17.38, -66, -2.2)]
    for (question, start, dy, rotation) in behind {
        let e = spring(prog(t, start, start + 0.7))
        guard e > 0 else { continue }
        let r = card.offsetBy(dx: 0, dy: dy + (1 - e) * 400)
        state {
            transform(at: CGPoint(x: r.midX, y: r.midY), scale: 0.93 + 0.03 * (dy < -100 ? 0 : 1), rotate: rotation)
            state { shadow(blur: 30, y: 12, alpha: 0.12); fillPath(roundRect(r, 26), 0xFBFCFE) }
            strokePath(roundRect(r, 26), 0xD5DCE6, 1, width: 1.5)
            text("Q&A", r.minX + 36, r.minY + 44, 18, .bold, color: blue, alpha: 0.7, tracking: 1)
            text(question, r.minX + 100, r.minY + 44, 22, .semibold, color: ink, alpha: 0.55)
        }
    }
    let e = spring(prog(t, 17.2, 18.0))
    guard e > 0 else { return }
    state {
        c.translateBy(x: 0, y: (1 - e) * 520)
        transform(at: CGPoint(x: card.midX, y: card.midY), rotate: (1 - e) * -6)
        let shape = roundRect(card, 28)
        state { shadow(blur: 50, y: 24, alpha: 0.2); fillPath(shape, white) }
        strokePath(shape, 0xD5DCE6, 1, width: 1.5)
        text("Q&A · 0:31", card.minX + 40, card.minY + 56, 20, .bold, color: blue, tracking: 1)
        let jump = CGRect(x: card.maxX - 170, y: card.minY + 28, width: 130, height: 40)
        fillPath(roundRect(jump, 20), ice)
        text("▶  0:31", jump.midX, jump.midY + 7, 18, .bold, color: 0x17587E, anchor: 0.5)
        let q = "Why does myelin make signals travel faster?"
        let size = min(31, 31 * 720 / measure(q, 31, .semibold))
        text(q, card.minX + 40, card.minY + 112, size, .semibold, color: ink)
        text("老师提问：为什么髓鞘能让信号传得更快？", card.minX + 40, card.minY + 156, 25, .regular, color: blue)
        line(CGPoint(x: card.minX + 40, y: card.minY + 186), CGPoint(x: card.maxX - 40, y: card.minY + 186), 0xE3E9F0, 1, width: 2)
        circle(CGPoint(x: card.minX + 48, y: card.minY + 222), 6, leaf)
        text("Answer", card.minX + 64, card.minY + 229, 19, .bold, color: gray)
        let typed = Int(Double(answer.count) * prog(t, 17.75, 19.0))
        paragraph(answer, CGRect(x: card.minX + 40, y: card.minY + 244, width: 720, height: 130), 25, .regular, color: ink, visible: typed, lineSpacing: 7)
        let sources = ["Lecture · 0:31", "Slides · p. 12", "Web"]
        var x = card.minX + 40
        for (k, s) in sources.enumerated() {
            let w = measure(s, 19, .semibold) + 40
            let pop = spring(prog(t, 19.1 + Double(k) * 0.1, 19.6 + Double(k) * 0.1))
            let r = CGRect(x: x, y: card.maxY - 66, width: w, height: 38)
            state {
                transform(at: CGPoint(x: r.midX, y: r.midY), scale: pop)
                fillPath(roundRect(r, 19), k == 2 ? 0xEAF4FB : 0xE6F6EF)
                text(s, r.midX, r.midY + 7, 19, .semibold, color: k == 2 ? blue : 0x127A5C, anchor: 0.5)
            }
            x += w + 12
        }
    }
}

// MARK: - Scene 7 (20-24): ask about anything you recorded.

let question = "What did the teacher say about the exam last week?"
let reply = "The exam is on Oct 28 and covers chapters 3 to 5. Practice problems on action potentials will count the most."
let nodes: [(String, CGPoint, UInt32)] = [
    ("Lecture · Oct 14", CGPoint(x: 330, y: 660), red), ("Slides.pdf", CGPoint(x: 560, y: 880), sky), ("Notes · Week 7", CGPoint(x: 270, y: 440), sun),
    ("Chat · Oct 15", CGPoint(x: 1360, y: 880), mint), ("Lecture · Oct 16", CGPoint(x: 1590, y: 660), red), ("Reading.pdf", CGPoint(x: 1650, y: 440), sky),
]
let matches: Set<Int> = [0, 1]

func sceneAsk(_ t: Double) {
    radialBackground(0x0C2A44, navy0, at: CGPoint(x: W / 2, y: 470), radius: 1200)
    for i in 0..<70 {
        let p = CGPoint(x: hash(i, 21) * W, y: hash(i, 22) * H)
        circle(p, 1 + 1.6 * hash(i, 23), white, 0.12 + 0.18 * (0.5 + 0.5 * sin(t * 2 + Double(i))))
    }
    kinetic("Ask about anything you recorded.", W / 2, 200, 68, .bold, anchor: 0.5, tracking: -1) { i, _ in
        let p = outCubic(prog(t, 20.05 + Double(i) * 0.05, 20.5 + Double(i) * 0.05))
        return Look(dy: (1 - p) * 40, alpha: p, color: white)
    }
    let sub = outCubic(prog(t, 20.4, 20.8))
    text("Lectures, files and past chats, with sources.", W / 2, 258 + (1 - sub) * 14, 29, .regular, color: sky, alpha: sub, anchor: 0.5)

    let bubbleIn = spring(prog(t, 20.2, 20.9))
    let rise = inOutCubic(prog(t, 22.55, 23.0))
    let bubble = CGRect(x: 460, y: 425 - rise * 40, width: 1000, height: 92)
    let anchorPoint = CGPoint(x: bubble.midX, y: bubble.midY)
    let fade = 1 - prog(t, 22.55, 22.85)
    // Retrieval lines and travelling pulses.
    for (k, node) in nodes.enumerated() {
        let grow = outCubic(prog(t, 21.3 + Double(k) * 0.07, 21.75 + Double(k) * 0.07))
        guard grow > 0 else { continue }
        let target = CGPoint(x: min(max(node.1.x, bubble.minX + 60), bubble.maxX - 60), y: node.1.y < bubble.midY ? bubble.minY : bubble.maxY)
        let lit = matches.contains(k) ? prog(t, 22.25, 22.4) : 0
        let dim = matches.contains(k) ? 1 : 1 - 0.65 * prog(t, 22.25, 22.45)
        line(node.1, mix(node.1, target, grow), lit > 0 ? leaf : sky, (0.3 + 0.5 * lit) * dim * fade, width: 2 + 2 * lit)
        for pulse in 0..<2 {
            let u = (t - 21.8 - Double(pulse) * 0.25 - Double(k) * 0.05) / 0.5
            guard u > 0, u < 1, t < 22.6 else { continue }
            glow(mix(node.1, target, outCubic(u)), 16, matches.contains(k) ? mint : sky, 0.9)
        }
    }
    // Source nodes; the two matches fly down to become citations.
    let card = CGRect(x: 460, y: 535, width: 1000, height: 285)
    var chipX = card.minX + 40
    for (k, node) in nodes.enumerated() {
        let pop = spring(prog(t, 21.2 + Double(k) * 0.07, 21.8 + Double(k) * 0.07))
        guard pop > 0 else { continue }
        let w = measure(node.0, 24, .medium) + 80
        var p = node.1
        var alpha = matches.contains(k) ? 1 : (1 - 0.65 * prog(t, 22.25, 22.45)) * fade
        let isMatch = matches.contains(k)
        var scale = pop
        if isMatch {
            let target = CGPoint(x: chipX + (w * 0.82) / 2, y: card.maxY - 52)
            chipX += w * 0.82 + 14
            let fly = inOutCubic(prog(t, 22.6, 23.15))
            p = mix(p, target, fly)
            scale *= 1 - 0.18 * fly
            alpha = 1
        }
        let lit = isMatch ? prog(t, 22.25, 22.4) : 0
        state {
            transform(at: p, scale: scale * (1 + 0.08 * sin(.pi * lit)))
            let r = CGRect(x: p.x - w / 2, y: p.y - 28, width: w, height: 56)
            if lit > 0 { glow(p, w * 0.7, leaf, 0.25 * lit * alpha) }
            fillPath(roundRect(r, 28), 0x10263A, 0.95 * alpha)
            strokePath(roundRect(r, 28), lit > 0 ? leaf : node.2, (0.55 + 0.45 * lit) * alpha, width: 2)
            circle(CGPoint(x: r.minX + 30, y: p.y), 9, node.2, alpha)
            text(node.0, r.minX + 52, p.y + 8, 24, .medium, color: white, alpha: 0.92 * alpha)
        }
    }
    // The query bubble.
    state {
        transform(at: anchorPoint, scale: bubbleIn)
        state { c.setShadow(offset: .zero, blur: 40, color: rgb(sky, 0.35)); fillPath(roundRect(bubble, 46), 0x0F2840) }
        strokePath(roundRect(bubble, 46), sky, 0.6, width: 2)
        ring(CGPoint(x: bubble.minX + 50, y: bubble.midY - 3), 12, sky, 1, width: 3.5)
        line(CGPoint(x: bubble.minX + 59, y: bubble.midY + 6), CGPoint(x: bubble.minX + 68, y: bubble.midY + 15), sky, 1, width: 3.5)
        let typed = Int(Double(question.count) * prog(t, 20.45, 21.45))
        let shown = String(question.prefix(typed))
        text(shown, bubble.minX + 92, bubble.midY + 11, 31, .regular, color: white)
        if t < 22.6 && sin(t * 16) > -0.2 {
            let x = bubble.minX + 96 + measure(shown, 31, .regular)
            fillPath(roundRect(CGRect(x: x, y: bubble.midY - 20, width: 3, height: 40), 1.5), mint)
        }
    }
    // The answer card.
    let cardIn = outCubic(prog(t, 22.55, 23.0))
    if cardIn > 0 {
        group(cardIn) {
            let r = card.offsetBy(dx: 0, dy: (1 - cardIn) * 40)
            fillPath(roundRect(r, 30), white, 0.07)
            strokePath(roundRect(r, 30), white, 0.16, width: 1.5)
            drawLeaf(at: CGPoint(x: r.minX + 56, y: r.minY + 52), height: 34)
            text("Nomi", r.minX + 84, r.minY + 61, 24, .bold, color: mint, rounded: true)
            let typed = Int(Double(reply.count) * prog(t, 22.8, 23.6))
            paragraph(reply, CGRect(x: r.minX + 40, y: r.minY + 92, width: 920, height: 140), 30, .regular, color: white, visible: typed, lineSpacing: 8)
        }
    }
}

// MARK: - Scene 8 (24-26): four beats, four promises.

func sceneMontage(_ t: Double) {
    let cards: [(UInt32, String, UInt32, Int, UInt32)] = [
        (leaf, "Runs on your Mac.", white, 3, white), (navy0, "Works offline.", white, 1, mint),
        (blue, "Learns how you study.", white, 2, sun), (paper, "Free & open source.", ink, 0, leaf),
    ]
    let k = min(3, Int((t - 24) / 0.5))
    let local = t - 24 - Double(k) * 0.5
    let previous: UInt32 = k == 0 ? navy0 : cards[k - 1].0
    fill(previous)
    let sweep = outCubic(prog(local, 0, 0.12))
    fill(cards[k].0, 1, CGRect(x: W * (1 - sweep), y: 0, width: W * sweep + 1, height: H))
    let (bg, words, color, accentWord, accent) = cards[k]
    // Rings burst behind the words.
    for j in 0..<3 {
        let p = prog(local, Double(j) * 0.07, Double(j) * 0.07 + 0.55)
        if p > 0 && p < 1 { ring(center, 120 + 900 * outExpo(p), bg == paper ? leaf : white, 0.28 * (1 - p), width: 3) }
    }
    if k == 3 { drawLeaf(at: CGPoint(x: 1640, y: 760), height: 760, rotate: 12 + local * 30, alpha: 0.1, highlight: 0) }
    let land = outExpo(prog(local, 0.02, 0.3))
    state {
        transform(at: center, scale: (1.3 - 0.3 * land) * (1 + 0.05 * local))
        kinetic(words, W / 2, 595, 150, .heavy, anchor: 0.5, tracking: -4) { i, _ in
            let p = outExpo(prog(local, 0.02 + Double(i) * 0.03, 0.25 + Double(i) * 0.03))
            return Look(dy: (1 - p) * 80, alpha: min(1, p * 3), color: i == accentWord ? accent : color)
        }
    }
}

// MARK: - Scene 9 (26-30): the end card.

func sceneEnd(_ t: Double) {
    let local = t - 26
    let leafCenter = CGPoint(x: W / 2, y: 370)
    radialBackground(blend(blue, navy1, 0.35), navy0, at: leafCenter, radius: 1250)
    // Slow light rays turning behind the logo.
    state {
        c.translateBy(x: leafCenter.x, y: leafCenter.y)
        c.rotate(by: local * 0.12)
        for k in 0..<14 {
            let a = Double(k) / 14 * 2 * .pi
            let p = CGMutablePath()
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: cos(a - 0.06) * 1500, y: sin(a - 0.06) * 1500))
            p.addLine(to: CGPoint(x: cos(a + 0.06) * 1500, y: sin(a + 0.06) * 1500))
            p.closeSubpath()
            fillPath(p, white, 0.03 * outCubic(prog(local, 0.2, 1.2)))
        }
    }
    for i in 0..<60 {
        let speed = 40 + hash(i, 31) * 90
        let y = H + 40 - (hash(i, 32) * (H + 80) + speed * local).truncatingRemainder(dividingBy: H + 80)
        let x = hash(i, 33) * W + 30 * sin(local + Double(i))
        circle(CGPoint(x: x, y: y), 1.5 + 2.5 * hash(i, 34), i % 3 == 0 ? mint : white, 0.25 * prog(local, 0, 0.6))
    }
    let grow = outBack(prog(local, 0, 0.6))
    glow(leafCenter, 430 * grow * (1 + 0.04 * sin(local * 3)), leaf, 0.42)
    for k in 0..<2 {
        let p = prog(local, Double(k) * 0.1, Double(k) * 0.1 + 1.2)
        if p > 0 && p < 1 { ring(leafCenter, 60 + 900 * outExpo(p), k == 0 ? mint : sky, 0.6 * (1 - p), width: 8 * (1 - p) + 1) }
    }
    drawLeaf(at: leafCenter, height: 290 * grow, rotate: mix(-35, 0, outCubic(prog(local, 0, 0.7))) + 2 * sin(local * 1.4), highlight: outCubic(prog(local, 0.35, 0.75)))
    kinetic("Nomi", W / 2, 650, 150, .bold, anchor: 0.5, rounded: true, tracking: -2, characters: true) { i, _ in
        let p = outCubic(prog(local, 0.35 + Double(i) * 0.07, 0.85 + Double(i) * 0.07))
        return Look(dy: (1 - p) * 70, scale: 0.9 + 0.1 * p, alpha: p, color: white)
    }
    let tag = outCubic(prog(local, 0.9, 1.35))
    text("Understand every lecture, in your own language.", W / 2, 735 + (1 - tag) * 18, 38, .regular, color: white, alpha: 0.9 * tag, anchor: 0.5)
    let zh = outCubic(prog(local, 1.15, 1.6))
    text("用母语听懂每一节课", W / 2, 790 + (1 - zh) * 18, 31, .medium, color: mint, alpha: zh, anchor: 0.5, tracking: 4)
    let cta = spring(prog(local, 1.5, 2.2))
    if cta > 0 {
        let label = "Free download  ·  nomi.software"
        let w = measure(label, 31, .semibold) + 90
        let pill = CGRect(x: W / 2 - w / 2, y: 852, width: w, height: 72)
        state {
            transform(at: CGPoint(x: pill.midX, y: pill.midY), scale: cta)
            state { c.setShadow(offset: .zero, blur: 40, color: rgb(leaf, 0.6)); fillPath(roundRect(pill, 36), leaf) }
            text(label, pill.midX, pill.midY + 11, 31, .semibold, color: white, anchor: 0.5)
        }
    }
    let small = prog(local, 1.9, 2.3)
    text("macOS 26  ·  Apple silicon  ·  MIT", W / 2, 985, 21, .medium, color: ice, alpha: 0.6 * small, anchor: 0.5, tracking: 3)
    fill(white, 0.85 * (1 - prog(local, 0, 0.3)))  // impact flash
}

// MARK: - Timeline

func frame(_ t: Double) {
    c.saveGState()
    if t < 4 { sceneVoice(t) }
    else if t < 6 { sceneBloom(t) }
    else if t < 9.32 {
        if t < 8.85 || prog(t, 8.8, 9.3) < 1 { sceneProblem(t) }
        if t >= 8.8 {
            let r = 1200 * outCubic(prog(t, 8.8, 9.3))
            state {
                c.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)); c.clip()
                sceneApp(t)
            }
        }
    }
    else if t < 13.5 { sceneApp(t) }
    else if t < 15.8 { sceneLanguages(t) }
    else if t < 16.3 {
        // A slanted leaf-green band sweeps across: languages on its right, Q&A on its left.
        let lead = mix(-700, Double(W) + 900, inOutCubic(prog(t, 15.8, 16.28)))
        let band = 300.0, slant = 0.4
        func edge(_ x: Double) -> [CGPoint] { [CGPoint(x: x + 540 * slant, y: 0), CGPoint(x: x - 540 * slant, y: H)] }
        state { clipPolygon(edge(lead) + [CGPoint(x: W + 2000, y: H), CGPoint(x: W + 2000, y: 0)]); sceneLanguages(t) }
        state { clipPolygon(edge(lead - band).reversed() + [CGPoint(x: -2000, y: 0), CGPoint(x: -2000, y: H)].reversed()); sceneQA(t) }
        state { clipPolygon(edge(lead) + edge(lead - band).reversed()); fill(leaf) }
    }
    else if t < 19.7 { sceneQA(t) }
    else if t < 20.15 {
        let e = inOutCubic(prog(t, 19.7, 20.15))
        state { c.translateBy(x: 0, y: -H * e); sceneQA(t) }
        state { c.translateBy(x: 0, y: H * (1 - e)); sceneAsk(t) }
    }
    else if t < 24 { sceneAsk(t) }
    else if t < 26 { sceneMontage(t) }
    else { sceneEnd(t) }
    // Vignette and the closing fade.
    let v = CGGradient(colorsSpace: space, colors: [rgb(0, 0), rgb(0, 0), rgb(0, 0.32)] as CFArray, locations: [0, 0.55, 1])!
    c.drawRadialGradient(v, startCenter: center, startRadius: 0, endCenter: center, endRadius: 1150, options: [.drawsAfterEndLocation])
    fill(0, prog(t, 29.25, 29.95))
    fill(0, 1 - prog(t, 0, 0.35))
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
    let fast = [(4.0, 4.45), (5.4, 6.0), (12.7, 13.6), (26.0, 26.45)].contains { time >= $0.0 && time < $0.1 }
    let samples = fast ? 12 : subframes
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
