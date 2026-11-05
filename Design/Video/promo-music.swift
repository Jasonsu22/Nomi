// Synthesizes the promo video's soundtrack: 70 seconds at 120 BPM in D major, written as a WAV.
// Build and run: swiftc -O Design/Video/promo-music.swift -o build/promo-music && build/promo-music build/promo-music.wav
// Everything is generated here (oscillators, filters, noise, reverb); no samples or services.
import Foundation

let rate = 44_100.0
let length = 70.0
let count = Int(rate * length)
let beat = 0.5
let bar = 2.0

var left = [Double](repeating: 0, count: count)
var right = [Double](repeating: 0, count: count)
var reverbSendL = [Double](repeating: 0, count: count)
var reverbSendR = [Double](repeating: 0, count: count)

func midi(_ note: Double) -> Double { 440 * pow(2, (note - 69) / 12) }
func index(_ time: Double) -> Int { max(0, min(count, Int(time * rate))) }

struct Random {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) & 0xFFFFFF) / Double(0xFFFFFF) * 2 - 1
    }
}
var noise = Random(state: 0x5EED)

/// Topology-preserving state-variable filter.
struct Filter {
    var ic1 = 0.0, ic2 = 0.0
    mutating func run(_ input: Double, cutoff: Double, q: Double = 0.7) -> (low: Double, band: Double, high: Double) {
        let g = tan(Double.pi * min(cutoff, rate * 0.45) / rate)
        let k = 1 / q
        let a1 = 1 / (1 + g * (g + k)), a2 = g * a1, a3 = g * a2
        let v3 = input - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        return (v2, v1, input - k * v1 - v2)
    }
}

func polyBlep(_ t: Double, _ dt: Double) -> Double {
    if t < dt { let x = t / dt; return x + x - x * x - 1 }
    if t > 1 - dt { let x = (t - 1) / dt; return x * x + x + x + 1 }
    return 0
}

func add(_ i: Int, _ value: Double, pan: Double = 0, send: Double = 0) {
    guard i >= 0, i < count else { return }
    let l = cos((pan + 1) * Double.pi / 4), r = sin((pan + 1) * Double.pi / 4)
    left[i] += value * l
    right[i] += value * r
    reverbSendL[i] += value * l * send
    reverbSendR[i] += value * r * send
}


// MARK: - Arrangement. Bars start on odd seconds, so these moments in promo.swift land on bar lines:
// 7 the leaf blooms, 13 Start Transcription starts the beat, 25 questions, 29 the pop-up, 33 answered,
// 39 chat (the drums drop out while it searches), 47 the answer, 53 demos, 63 the end card.

let D = [57.0, 62, 66, 69], A = [57.0, 61, 64, 69], Bm = [59.0, 62, 66, 71], G = [55.0, 59, 62, 67]
let bloom = 7.0, start = 13.0, questions = 25.0, chat = 39.0, answer = 47.0, demos = 53.0, finale = 63.0
func harmony(at time: Double) -> ([Double], Double) {
    if time < 5 { return (Bm, 35) }
    if time < bloom { return (A, 33) }
    if time < 9 { return (D, 38) }
    if time < 11 { return (A, 33) }
    if time < start { return (Bm, 35) }
    if time >= finale { return (D, 38) }
    if time >= 61 { return (A, 33) }
    let cycle: [([Double], Double)] = [(Bm, 35), (G, 31), (D, 38), (A, 33)]
    return cycle[Int((time - start) / bar) % 4]
}
func grooving(_ time: Double) -> Bool { (time >= start && time < chat) || (time >= answer && time < finale) }

/// Kick times: none until Start is clicked, out for the chat's search, eighths into the finale.
var kicks: [Double] = [bloom]
var t = start
while t < finale - 0.001 {
    if grooving(t), !(t > 38.4) || t >= answer { kicks.append(t) }
    if t >= 61.5 { kicks.append(t + 0.25) }
    t += beat
}
kicks.append(finale)

/// Sidechain gain from the kicks, so the pad and bass breathe with the drums.
var duck = [Double](repeating: 1, count: count)
for k in kicks {
    let first = index(k)
    for i in first..<min(count, first + Int(0.3 * rate)) {
        let x = Double(i - first) / rate / 0.3
        duck[i] = min(duck[i], 0.45 + 0.55 * pow(x, 0.6))
    }
}

// MARK: Kick
for k in kicks {
    let big = k == bloom || k == finale
    let first = index(k), dur = big ? 1.6 : 0.42
    var phase = 0.0
    for i in first..<min(count, first + Int(dur * rate)) {
        let x = Double(i - first) / rate
        let freq = 46 + (big ? 140 : 110) * exp(-x * 28)
        phase += 2 * Double.pi * freq / rate
        let body = sin(phase) * exp(-x * (big ? 2.2 : 7.5))
        let click = x < 0.004 ? noise.next() * (1 - x / 0.004) * 0.3 : 0
        add(i, tanh((body + click) * 1.6) * (big ? 0.95 : 0.66))
    }
}

// MARK: Clap, from the questions on
var clapTimes: [Double] = []
t = questions + beat
while t < finale - 2 { if (t < 38.4) || t >= demos { clapTimes.append(t) }; t += 2 * beat }
for at in clapTimes {
    var filter = Filter()
    let first = index(at)
    for i in first..<min(count, first + Int(0.3 * rate)) {
        let x = Double(i - first) / rate
        let bursts = (x < 0.03) ? (sin(x / 0.01 * Double.pi) > 0 ? 1.0 : 0.4) : 1.0
        let v = filter.run(noise.next(), cutoff: 1600, q: 1.2).band
        add(i, v * exp(-x * 18) * bursts * 0.42, pan: 0.05, send: 0.25)
    }
}

// MARK: Hats
var hatFilter = Filter()
t = start
while t < 61.5 {
    for step in 0..<4 {
        let at = t + Double(step) * 0.125
        guard grooving(at) else { continue }
        let offbeat = step == 2
        let ghost = (at >= questions && at < chat) || at >= demos
        guard offbeat || ghost else { continue }
        let first = index(at), dur = offbeat ? 0.07 : 0.03
        for i in first..<min(count, first + Int(dur * rate)) {
            let x = Double(i - first) / rate
            let v = hatFilter.run(noise.next(), cutoff: 8000, q: 0.8).high
            add(i, v * exp(-x * (offbeat ? 55 : 110)) * (offbeat ? 0.2 : 0.08), pan: step == 1 ? -0.3 : 0.3)
        }
    }
    t += beat
}

// MARK: The opening: fast ticking for fast talk, hits on each word, and a pen that stops
var tickFilter = Filter()
t = 0.25
while t < 6.0 {
    let first = index(t)
    let swell = min(1, t / 2.5) * (t > 5 ? max(0, (6 - t)) : 1)
    for i in first..<min(count, first + Int(0.03 * rate)) {
        let x = Double(i - first) / rate
        add(i, tickFilter.run(noise.next(), cutoff: 7000, q: 1).high * exp(-x * 140) * 0.13 * swell, pan: sin(t * 9) * 0.4)
    }
    t += 0.125
}
func hit(at time: Double, pitch: Double, level: Double) {
    let first = index(time)
    var phase = 0.0
    for i in first..<min(count, first + Int(0.5 * rate)) {
        let x = Double(i - first) / rate
        phase += 2 * Double.pi * (pitch + 80 * exp(-x * 30)) / rate
        add(i, sin(phase) * exp(-x * 9) * level, send: 0.5)
    }
}
for (at, pitch) in [(0.25, 70.0), (0.5, 70), (0.75, 70), (1.25, 92)] { hit(at: at, pitch: pitch, level: at == 1.25 ? 0.55 : 0.38) }
// The pen writes three lines, then gives up.
var penFilter = Filter()
for (from, to) in [(2.9, 3.3), (3.45, 3.85), (4.0, 4.4)] {
    for i in index(from)..<index(to) {
        let time = Double(i) / rate
        let stroke = 0.5 + 0.5 * sin(time * 2 * Double.pi * 13) * sin(time * 2 * Double.pi * 3.1)
        add(i, penFilter.run(noise.next(), cutoff: 3600, q: 1.6).band * stroke * 0.09, pan: 0.35)
    }
}

// MARK: Snare roll into the end card
t = 61.5
while t < 62.95 {
    let progress = (t - 61.5) / 1.45
    var filter = Filter()
    let first = index(t)
    for i in first..<min(count, first + Int(0.12 * rate)) {
        let x = Double(i - first) / rate
        let tone = sin(2 * Double.pi * 190 * x) * 0.4
        let v = filter.run(noise.next(), cutoff: 2600, q: 0.9).band + tone
        add(i, v * exp(-x * 30) * (0.1 + 0.32 * progress), send: 0.2)
    }
    t += progress < 0.5 ? 0.125 : 0.0625
}

// MARK: Sub bass and offbeat bass
var bassFilter = Filter()
var subPhase = 0.0, bassPhase = 0.0
for i in index(bloom)..<index(finale + 3.6) {
    let time = Double(i) / rate
    let note = harmony(at: min(time, finale + 1)).1
    let final = time >= finale
    subPhase += 2 * Double.pi * midi(note) / rate
    let fade = final ? max(0, 1 - (time - finale) / 3.6) : 1
    // The sub thins out during the chat's search, then the groove comes back.
    let body = (time >= chat && time < answer) ? 0.5 : 1.0
    var v = sin(subPhase) * 0.3 * body * (final ? fade : duck[i])
    if !final && grooving(time) {
        let position = time.truncatingRemainder(dividingBy: beat)
        if position >= 0.25 {
            let x = position - 0.25
            bassPhase += midi(note + 12) / rate
            bassPhase -= floor(bassPhase)
            let saw = 2 * bassPhase - 1 - polyBlep(bassPhase, midi(note + 12) / rate)
            v += bassFilter.run(saw, cutoff: 300 + 1600 * exp(-x * 22), q: 1.1).low * 0.26 * exp(-x * 6)
        }
    }
    add(i, tanh(v * 1.4) * 0.8)
}

// MARK: Pad (detuned saws through a lowpass that follows the story)
let detune = [-0.11, -0.05, 0, 0.06, 0.12]
var padFilters = [Filter(), Filter()]
var padPhases = [Double](repeating: 0, count: 4 * detune.count)
for i in 0..<count {
    let time = Double(i) / rate
    let notes = harmony(at: time).0
    var l = 0.0, r = 0.0
    for (n, note) in notes.enumerated() {
        for (d, cents) in detune.enumerated() {
            let p = n * detune.count + d
            let freq = midi(note + cents)
            padPhases[p] += freq / rate
            padPhases[p] -= floor(padPhases[p])
            let saw = 2 * padPhases[p] - 1 - polyBlep(padPhases[p], freq / rate)
            if d % 2 == 0 { l += saw } else { r += saw }
            if d == 2 { l += saw * 0.5; r += saw * 0.5 }
        }
    }
    var cutoff: Double
    if time < bloom { cutoff = 250 + 2000 * pow(time / bloom, 2.4) }
    else if time < start { cutoff = 2600 }
    else if time < chat { cutoff = 1400 + 500 * sin(time * 0.7) }
    else if time < answer { cutoff = 600 + 1700 * pow((time - chat) / (answer - chat), 1.6) }
    else if time < finale { cutoff = 1700 + 600 * sin(time * 0.9) + (time > 61 ? (time - 61) * 1500 : 0) }
    else { cutoff = 4200 * exp(-(time - finale) * 0.35) + 600 }
    let level: Double
    if time < 0.5 { level = time / 0.5 * 0.04 }
    else if time < 6.8 { level = 0.04 + 0.03 * time / 6.8 }
    else if time < bloom { level = 0.02 }  // the breath before the leaf
    else if time < start { level = 0.078 }
    else if time < finale { level = (time >= chat && time < answer ? 0.075 : 0.055) * duck[i] }
    else { level = 0.085 * max(0, 1 - (time - finale) / 6.8) }
    let lv = padFilters[0].run(l, cutoff: cutoff, q: 0.9).low * level
    let rv = padFilters[1].run(r, cutoff: cutoff, q: 0.9).low * level
    left[i] += lv; right[i] += rv
    reverbSendL[i] += lv * 0.35; reverbSendR[i] += rv * 0.35
}

// MARK: Arpeggio (sixteenths, filtered square, panned)
let pattern = [0, 1, 2, 3, 4, 3, 2, 1, 0, 2, 4, 5, 4, 2, 1, 3]
var arpFilter = Filter()
t = start
var step = 0
while t < finale - 0.01 {
    defer { t += 0.125; step += 1 }
    let tones = harmony(at: t).0.map { $0 + 12 }
    let all = tones + tones.map { $0 + 12 }
    let note = all[pattern[step % pattern.count] % all.count]
    let freq = midi(note)
    let first = index(t)
    var phase = 0.0
    let pan = step % 2 == 0 ? -0.45 : 0.45
    // Quiet under the transcript, up front while chat searches.
    let swell = (t >= chat && t < answer) ? 1.5 : min(1, (t - start) / 3)
    for i in first..<min(count, first + Int(0.22 * rate)) {
        let x = Double(i - first) / rate
        phase += freq / rate
        phase -= floor(phase)
        let square = (phase < 0.5 ? 1.0 : -1.0)
        let v = arpFilter.run(square, cutoff: 700 + 4200 * exp(-x * 30), q: 1.4).low
        add(i, v * exp(-x * 14) * 0.06 * swell * duck[i], pan: pan, send: 0.45)
    }
}

// MARK: Bell melody and chimes (two-operator FM)
func bell(at time: Double, note: Double, beats: Double = 1, level: Double = 0.11, pan: Double = 0.2) {
    let freq = midi(note)
    let first = index(time)
    for i in first..<min(count, first + Int((beats * beat + 1.2) * rate)) {
        let x = Double(i - first) / rate
        let modIndex = 2.2 * exp(-x * 5)
        let v = sin(2 * Double.pi * freq * x + modIndex * sin(2 * Double.pi * freq * 3.5 * x))
        add(i, v * min(1, x / 0.004) * exp(-x * 2.6) * level, pan: pan, send: 0.6)
    }
}
// These phrases follow Bm, G, D, A.
let phrases: [[(Double, Double, Double)]] = [
    [(0, 78, 1), (1, 76, 0.5), (1.5, 74, 1), (3, 71, 1)],
    [(0, 74, 1), (1, 71, 0.5), (1.5, 74, 1), (2.5, 79, 1.5)],
    [(0, 78, 1.5), (1.5, 76, 0.5), (2, 74, 2)],
    [(0, 73, 1), (1, 74, 0.5), (1.5, 76, 1), (2.5, 81, 1.5)],
]
// Each bar's phrase matches the chord that the cycle has reached there. Bars with a chime stay clear.
for at in [25.0, 27, 35, 37, 53, 55, 57, 59] {
    let phrase = phrases[Int((at - start) / bar) % 4]
    for n in phrase { bell(at: at + n.0 * beat, note: n.1, beats: n.2, pan: n.1.truncatingRemainder(dividingBy: 2) == 0 ? -0.2 : 0.2) }
}
for (delay, note) in [(0.0, 74.0), (0.25, 78), (0.5, 81), (0.75, 86)] { bell(at: finale + delay, note: note, beats: 6, level: 0.11, pan: 0) }
// The pop-up arrives, then is answered: the same two notes, the second time a step higher.
bell(at: 29.0, note: 81, level: 0.15, pan: 0.35); bell(at: 29.25, note: 86, level: 0.13, pan: 0.35)
bell(at: 33.0, note: 86, level: 0.15, pan: 0.35); bell(at: 33.25, note: 90, level: 0.13, pan: 0.35)
// Each source lights up during the search, and the answer's sources appear with it.
for (at, note) in [(44.1, 74.0), (44.5, 78), (44.9, 81), (45.3, 78)] { bell(at: at, note: note + 12, level: 0.05, pan: -0.25) }

// MARK: Interface sounds, on the pointer's actions in promo.swift
func click(at time: Double, level: Double = 0.2, pan: Double = 0) {
    var filter = Filter()
    let first = index(time)
    for i in first..<min(count, first + Int(0.05 * rate)) {
        let x = Double(i - first) / rate
        let n = filter.run(noise.next(), cutoff: 3200, q: 2).band
        add(i, (n + sin(2 * Double.pi * 1500 * x) * 0.4) * exp(-x * 120) * level, pan: pan, send: 0.08)
    }
}
func pop(at time: Double, from a: Double, to b: Double, level: Double, pan: Double = 0) {
    let first = index(time)
    var phase = 0.0
    for i in first..<min(count, first + Int(0.12 * rate)) {
        let x = Double(i - first) / rate
        phase += 2 * Double.pi * (b + (a - b) * exp(-x * 30)) / rate
        add(i, sin(phase) * exp(-x * 30) * level, pan: pan, send: 0.1)
    }
}
for at in [13.0, 36.0, 40.0, 49.5] { click(at: at, level: 0.32, pan: 0.15) }
// Keys while the two questions are typed; the send lifts away.
for (from, to, chars) in [(41.0, 43.0, 50), (52.6, 53.8, 48)] {
    for k in 0..<chars where k % 2 == 0 {
        click(at: from + (to - from) * Double(k) / Double(chars), level: 0.06 + 0.03 * hash01(k), pan: -0.15 + 0.3 * hash01(k + 7))
    }
}
func hash01(_ i: Int) -> Double { let x = sin(Double(i) * 12.9898) * 43758.5453; return x - floor(x) }
pop(at: 43.2, from: 500, to: 1100, level: 0.14)
pop(at: 53.9, from: 500, to: 1100, level: 0.14)
// The filler phrases get crossed out one by one, each lower than the last.
for (at, pitch) in [(27.15, 620.0), (27.75, 520), (28.35, 440)] { pop(at: at, from: pitch, to: pitch * 0.55, level: 0.16, pan: -0.3) }
// The figure's slider: a thin tone climbing with the signal's speed.
var sliderPhase = 0.0
for i in index(57.0)..<index(59.4) {
    let x = (Double(i) / rate - 57.0) / 2.4
    sliderPhase += 2 * Double.pi * midi(62 + 24 * x * x * (3 - 2 * x)) / rate
    add(i, sin(sliderPhase) * min(1, x * 8) * min(1, (1 - x) * 8) * 0.05, send: 0.5)
}

// MARK: Effects: risers, whooshes, reverse cymbal, impacts
func riser(from a: Double, to b: Double, level: Double) {
    var filter = Filter()
    var phase = 0.0
    for i in index(a)..<index(b) {
        let x = max(0, (Double(i) / rate - a) / (b - a))  // rounding can put the first sample just before a
        let cutoff = 300 + 9000 * pow(x, 2.5)
        let n = filter.run(noise.next(), cutoff: cutoff, q: 2.5).band
        phase += 2 * Double.pi * (200 + 1400 * pow(x, 2)) / rate
        add(i, (n * 0.8 + sin(phase) * 0.12) * pow(x, 1.6) * level, send: 0.3)
    }
}
func whoosh(at time: Double, length: Double = 0.7, level: Double = 0.35) {
    var filter = Filter()
    let first = index(time - length * 0.6)
    for i in first..<min(count, first + Int(length * rate)) {
        let x = Double(i - first) / rate / length
        let env = sin(Double.pi * pow(x, 0.8))
        let cutoff = 400 + 5000 * sin(Double.pi * x)
        add(i, filter.run(noise.next(), cutoff: cutoff, q: 1.5).band * env * level, pan: -0.8 + 1.6 * x, send: 0.3)
    }
}
func impact(at time: Double, level: Double) {
    var filter = Filter()
    let first = index(time)
    for i in first..<min(count, first + Int(2.4 * rate)) {
        let x = Double(i - first) / rate
        let crash = filter.run(noise.next(), cutoff: 5000, q: 0.5).high * exp(-x * 2.2) * 0.35
        let boom = sin(2 * Double.pi * (38 + 30 * exp(-x * 6)) * x) * exp(-x * 1.4) * 0.5
        add(i, (crash + boom) * level, send: 0.5)
    }
}
func reverseCymbal(endingAt time: Double, length: Double) {
    var filter = Filter()
    let first = index(time - length)
    for i in first..<index(time) {
        let x = (Double(i - first) / rate) / length
        add(i, filter.run(noise.next(), cutoff: 6000, q: 0.6).high * pow(x, 3) * 0.4, send: 0.2)
    }
}

riser(from: 4.6, to: 6.8, level: 0.3)
reverseCymbal(endingAt: bloom, length: 1.4)
impact(at: bloom, level: 0.85)
whoosh(at: 9.95, length: 0.9, level: 0.22)    // the leaf lands in the app
impact(at: start, level: 0.28)                 // Start Transcription
// The camera's moves in the take.
for (at, length, level) in [(17.6, 1.0, 0.14), (25.4, 0.9, 0.14), (31.1, 0.9, 0.14), (34.2, 0.8, 0.14), (46.5, 0.9, 0.14), (52.1, 0.8, 0.12), (57.5, 0.9, 0.12), (62.0, 0.7, 0.14)] {
    whoosh(at: at, length: length, level: level)
}
riser(from: 45.0, to: answer, level: 0.14)     // into the answer
reverseCymbal(endingAt: answer, length: 0.8)
riser(from: 61.2, to: finale - 0.03, level: 0.3)
whoosh(at: 62.9, length: 0.7, level: 0.3)      // through the leaf
impact(at: finale, level: 1.0)

// MARK: - Reverb (Freeverb-style combs and allpasses, slightly different per side)
func reverb(_ input: [Double], spread: Int) -> [Double] {
    let combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617].map { $0 + spread }
    let allpasses = [556, 441, 341, 225].map { $0 + spread }
    var out = [Double](repeating: 0, count: input.count)
    for size in combs {
        var buffer = [Double](repeating: 0, count: size)
        var position = 0, store = 0.0
        for i in 0..<input.count {
            let y = buffer[position]
            store = y * 0.75 + store * 0.25  // damping
            buffer[position] = input[i] + store * 0.86
            position = (position + 1) % size
            out[i] += y
        }
    }
    for size in allpasses {
        var buffer = [Double](repeating: 0, count: size)
        var position = 0
        for i in 0..<out.count {
            let b = buffer[position]
            buffer[position] = out[i] + b * 0.5
            out[i] = b - out[i]
            position = (position + 1) % size
        }
    }
    return out
}
let wetL = reverb(reverbSendL, spread: 0)
let wetR = reverb(reverbSendR, spread: 23)

// MARK: - Master
var peak = 0.0
for i in 0..<count {
    let time = Double(i) / rate
    let fadeOut = time > 68.6 ? max(0, 1 - (time - 68.6) / 1.4) : 1
    let fadeIn = min(1, time / 0.05)
    left[i] = tanh((left[i] + wetL[i] * 0.07) * 1.15) * fadeOut * fadeIn
    right[i] = tanh((right[i] + wetR[i] * 0.07) * 1.15) * fadeOut * fadeIn
    peak = max(peak, abs(left[i]), abs(right[i]))
}
let gain = 0.89 / peak  // about -1 dBFS

// MARK: - WAV (16-bit stereo PCM)
var data = Data()
func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + count * 4))
data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(2))
append(UInt32(rate)); append(UInt32(rate * 4)); append(UInt16(4)); append(UInt16(16))
data.append(contentsOf: Array("data".utf8)); append(UInt32(count * 4))
for i in 0..<count {
    append(Int16(max(-1, min(1, left[i] * gain)) * 32767))
    append(Int16(max(-1, min(1, right[i] * gain)) * 32767))
}
let output = CommandLine.arguments.dropFirst().first ?? "promo-music.wav"
try data.write(to: URL(fileURLWithPath: output))
print("wrote \(output), peak before gain \(String(format: "%.2f", peak))")
