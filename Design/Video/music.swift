// Synthesizes the showreel soundtrack: 30 seconds at 120 BPM in D major, written as a WAV.
// Build and run: swiftc -O Design/Video/music.swift -o build/showreel-music && build/showreel-music build/showreel-music.wav
// Everything is generated here (oscillators, filters, noise, reverb); no samples or services.
// One beat is 0.5 s and one bar is 2 s, so the scene cuts in render.swift land on beats.
import Foundation

let rate = 44_100.0
let length = 30.0
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

// MARK: - Arrangement

// Chords per bar. Bars 0-1 are the intro, the drop lands at 4 s (bar 2), the final chord at 26 s (bar 13).
let D = [57.0, 62, 66, 69], A = [57.0, 61, 64, 69], Bm = [59.0, 62, 66, 71], G = [55.0, 59, 62, 67]
let chords: [[Double]] = [Bm, G, D, A, Bm, G, D, A, Bm, G, D, A, G, D, D]
let roots: [Double] = [35, 31, 38, 33, 35, 31, 38, 33, 35, 31, 38, 33, 31, 38, 38]
func chord(at time: Double) -> [Double] {
    if time >= 25 && time < 26 { return A }  // the last half bar of the montage leans on A
    return chords[min(Int(time / bar), chords.count - 1)]
}
func root(at time: Double) -> Double {
    if time >= 25 && time < 26 { return 33 }
    return roots[min(Int(time / bar), roots.count - 1)]
}

let drop = 4.0, montageEnd = 26.0
/// Kick times: four on the floor from the drop, a gap before the zoom at 13.5 s, eighths into the finale.
var kicks: [Double] = []
var t = drop
while t < montageEnd - 0.001 {
    if !(t > 12.9 && t < 13.5) { kicks.append(t) }
    if t >= 25.5 { kicks.append(t + 0.25) }
    t += beat
}
kicks.append(montageEnd)

/// Sidechain gain from the kicks, so the pad and bass breathe with the drums.
var duck = [Double](repeating: 1, count: count)
for k in kicks {
    let start = index(k)
    for i in start..<min(count, start + Int(0.3 * rate)) {
        let x = Double(i - start) / rate / 0.3
        duck[i] = min(duck[i], 0.35 + 0.65 * pow(x, 0.6))
    }
}

// MARK: Kick
for (n, k) in kicks.enumerated() {
    let big = k == drop || k == montageEnd
    let start = index(k), dur = big ? 1.6 : 0.42
    var phase = 0.0
    for i in start..<min(count, start + Int(dur * rate)) {
        let x = Double(i - start) / rate
        let freq = 46 + (big ? 140 : 110) * exp(-x * 28)
        phase += 2 * Double.pi * freq / rate
        let body = sin(phase) * exp(-x * (big ? 2.2 : 7.5))
        let click = x < 0.004 ? noise.next() * (1 - x / 0.004) * 0.3 : 0
        add(i, tanh((body + click) * 1.6) * (big ? 0.95 : 0.8))
    }
    _ = n
}

// MARK: Clap
var clapTimes: [Double] = []
t = drop + beat
while t < 25 { if !(t > 12.9 && t < 13.5) { clapTimes.append(t) }; t += 2 * beat }
for c in clapTimes {
    var filter = Filter()
    let start = index(c)
    for i in start..<min(count, start + Int(0.3 * rate)) {
        let x = Double(i - start) / rate
        // Three quick bursts, then a tail, like hands clapping.
        let bursts = (x < 0.03) ? (sin(x / 0.01 * Double.pi) > 0 ? 1.0 : 0.4) : 1.0
        let env = exp(-x * 18) * bursts
        let v = filter.run(noise.next(), cutoff: 1600, q: 1.2).band
        add(i, v * env * 0.55, pan: 0.05, send: 0.25)
    }
}

// MARK: Hats
var hatFilter = Filter()
t = drop
while t < 25.5 {
    for step in 0..<4 {
        let at = t + Double(step) * 0.125
        if at > 12.9 && at < 13.5 { continue }
        let offbeat = step == 2
        let ghost = at >= 16 && !offbeat
        guard offbeat || ghost else { continue }
        let start = index(at), dur = offbeat ? 0.07 : 0.03
        for i in start..<min(count, start + Int(dur * rate)) {
            let x = Double(i - start) / rate
            let v = hatFilter.run(noise.next(), cutoff: 8000, q: 0.8).high
            add(i, v * exp(-x * (offbeat ? 55 : 110)) * (offbeat ? 0.22 : 0.09), pan: step == 1 ? -0.3 : 0.3)
        }
    }
    t += beat
}

// MARK: Snare roll into the finale
t = 24.5
while t < 25.95 {
    let progress = (t - 24.5) / 1.45
    var filter = Filter()
    let start = index(t)
    for i in start..<min(count, start + Int(0.12 * rate)) {
        let x = Double(i - start) / rate
        let tone = sin(2 * Double.pi * 190 * x) * 0.4
        let v = filter.run(noise.next(), cutoff: 2600, q: 0.9).band + tone
        add(i, v * exp(-x * 30) * (0.12 + 0.35 * progress), send: 0.2)
    }
    t += progress < 0.5 ? 0.125 : 0.0625
}

// MARK: Sub bass and offbeat bass
var bassFilter = Filter()
var subPhase = 0.0, bassPhase = 0.0
for i in index(drop)..<index(montageEnd + 3.6) {
    let time = Double(i) / rate
    let note = root(at: min(time, 25.99))
    let final = time >= montageEnd
    subPhase += 2 * Double.pi * midi(note) / rate
    let fade = final ? max(0, 1 - (time - montageEnd) / 3.6) : 1
    var v = sin(subPhase) * 0.32 * (final ? fade : duck[i])
    if !final && !(time > 12.9 && time < 13.5) {
        // Offbeat eighth pluck an octave up.
        let position = time.truncatingRemainder(dividingBy: beat)
        if position >= 0.25 {
            let x = position - 0.25
            bassPhase += midi(note + 12) / rate
            bassPhase -= floor(bassPhase)
            let saw = 2 * bassPhase - 1 - polyBlep(bassPhase, midi(note + 12) / rate)
            let cutoff = 300 + 1800 * exp(-x * 22)
            v += bassFilter.run(saw, cutoff: cutoff, q: 1.1).low * 0.3 * exp(-x * 6)
        }
    }
    add(i, tanh(v * 1.4) * 0.8)
}

// MARK: Pad (detuned saws through a lowpass that opens over the intro)
let detune = [-0.11, -0.05, 0, 0.06, 0.12]
var padFilters = [Filter(), Filter()]
var padPhases = [Double](repeating: 0, count: 4 * detune.count)
for i in 0..<count {
    let time = Double(i) / rate
    let notes = chord(at: time)
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
    // Cutoff: closed and rising in the intro, open in the body, wide in the finale.
    var cutoff: Double
    if time < drop { cutoff = 250 + 2200 * pow(time / drop, 2.2) }
    else if time < montageEnd { cutoff = 1500 + 700 * sin(time * 0.9) + (time > 24 ? (time - 24) * 1500 : 0) }
    else { cutoff = 4200 * exp(-(time - montageEnd) * 0.35) + 600 }
    let level: Double
    if time < 0.4 { level = time / 0.4 * 0.05 }
    else if time < 3.7 { level = 0.05 + 0.03 * time / 3.7 }
    else if time < drop { level = 0.02 }  // the breath before the drop
    else if time < montageEnd { level = 0.055 * duck[i] }
    else { level = 0.085 * max(0, 1 - (time - montageEnd) / 4) }
    let lv = padFilters[0].run(l, cutoff: cutoff, q: 0.9).low * level
    let rv = padFilters[1].run(r, cutoff: cutoff, q: 0.9).low * level
    left[i] += lv; right[i] += rv
    reverbSendL[i] += lv * 0.35; reverbSendR[i] += rv * 0.35
}

// MARK: Arpeggio (sixteenths, filtered square, panned)
let pattern = [0, 1, 2, 3, 4, 3, 2, 1, 0, 2, 4, 5, 4, 2, 1, 3]
var arpFilter = Filter()
t = 8.0
var step = 0
while t < montageEnd - 0.01 {
    defer { t += 0.125; step += 1 }
    if t > 12.9 && t < 13.5 { continue }
    let tones = chord(at: t).map { $0 + 12 }
    let all = tones + tones.map { $0 + 12 }
    let note = all[pattern[step % pattern.count] % all.count]
    let freq = midi(note)
    let start = index(t)
    var phase = 0.0
    let pan = step % 2 == 0 ? -0.45 : 0.45
    let swell = min(1, (t - 8) / 2)
    for i in start..<min(count, start + Int(0.22 * rate)) {
        let x = Double(i - start) / rate
        phase += freq / rate
        phase -= floor(phase)
        let square = (phase < 0.5 ? 1.0 : -1.0)
        let v = arpFilter.run(square, cutoff: 700 + 4200 * exp(-x * 30), q: 1.4).low
        add(i, v * exp(-x * 14) * 0.075 * swell * duck[i], pan: pan, send: 0.45)
    }
}

// MARK: Bell melody (two-operator FM)
struct Note { let at: Double; let midi: Double; let beats: Double }
var melody: [Note] = []
let phrases: [(Double, [(Double, Double, Double)])] = [
    (16, [(0, 78, 1), (1, 76, 0.5), (1.5, 74, 1), (3, 71, 1)]),
    (18, [(0, 74, 1), (1, 71, 0.5), (1.5, 74, 1), (2.5, 79, 1.5)]),
    (20, [(0, 78, 1.5), (1.5, 76, 0.5), (2, 74, 2)]),
    (22, [(0, 73, 1), (1, 74, 0.5), (1.5, 76, 1), (2.5, 81, 1.5)]),
    (26, [(0, 74, 6), (0.25, 78, 6), (0.5, 81, 6), (0.75, 86, 6)]),
]
for (start, notes) in phrases { for n in notes { melody.append(Note(at: start + n.0 * beat, midi: n.1, beats: n.2)) } }
for note in melody {
    let freq = midi(note.midi)
    let start = index(note.at)
    let dur = note.beats * beat + 1.2
    for i in start..<min(count, start + Int(dur * rate)) {
        let x = Double(i - start) / rate
        let modIndex = 2.2 * exp(-x * 5)
        let v = sin(2 * Double.pi * freq * x + modIndex * sin(2 * Double.pi * freq * 3.5 * x))
        let env = min(1, x / 0.004) * exp(-x * 2.6)
        add(i, v * env * 0.11, pan: note.midi.truncatingRemainder(dividingBy: 2) == 0 ? -0.2 : 0.2, send: 0.6)
    }
}

// MARK: Effects: risers, whooshes, reverse cymbal, impacts
func riser(from a: Double, to b: Double, level: Double) {
    var filter = Filter()
    var phase = 0.0
    for i in index(a)..<index(b) {
        let x = (Double(i) / rate - a) / (b - a)
        let cutoff = 300 + 9000 * pow(x, 2.5)
        let n = filter.run(noise.next(), cutoff: cutoff, q: 2.5).band
        phase += 2 * Double.pi * (200 + 1400 * pow(x, 2)) / rate
        add(i, (n * 0.8 + sin(phase) * 0.12) * pow(x, 1.6) * level, send: 0.3)
    }
}
func whoosh(at time: Double, length: Double = 0.7, level: Double = 0.35) {
    var filter = Filter()
    let start = index(time - length * 0.6)
    for i in start..<min(count, start + Int(length * rate)) {
        let x = Double(i - start) / rate / length
        let env = sin(Double.pi * pow(x, 0.8))
        let cutoff = 400 + 5000 * sin(Double.pi * x)
        let pan = -0.8 + 1.6 * x
        add(i, filter.run(noise.next(), cutoff: cutoff, q: 1.5).band * env * level, pan: pan, send: 0.3)
    }
}
func impact(at time: Double, level: Double) {
    var filter = Filter()
    let start = index(time)
    for i in start..<min(count, start + Int(2.4 * rate)) {
        let x = Double(i - start) / rate
        let crash = filter.run(noise.next(), cutoff: 5000, q: 0.5).high * exp(-x * 2.2) * 0.35
        let boom = sin(2 * Double.pi * (38 + 30 * exp(-x * 6)) * x) * exp(-x * 1.4) * 0.5
        add(i, (crash + boom) * level, send: 0.5)
    }
}
func reverseCymbal(endingAt time: Double, length: Double) {
    var filter = Filter()
    let start = index(time - length)
    for i in start..<index(time) {
        let x = (Double(i - start) / rate) / length
        add(i, filter.run(noise.next(), cutoff: 6000, q: 0.6).high * pow(x, 3) * 0.4, send: 0.2)
    }
}

riser(from: 1.6, to: 3.72, level: 0.32)
reverseCymbal(endingAt: drop, length: 1.4)
impact(at: drop, level: 0.9)
whoosh(at: 5.75, length: 0.8, level: 0.4)   // leaf zooms through the camera
whoosh(at: 9.0, length: 0.6, level: 0.3)    // words pulled into the window
riser(from: 12.2, to: 13.5, level: 0.22)    // zoom into the transcript
impact(at: 13.5, level: 0.45)
whoosh(at: 16.0, length: 0.6, level: 0.3)
whoosh(at: 20.0, length: 0.7, level: 0.32)
for at in [24.0, 24.5, 25.0, 25.5] { whoosh(at: at + 0.05, length: 0.3, level: 0.16) }
riser(from: 24.4, to: 25.97, level: 0.3)
impact(at: montageEnd, level: 1.0)

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
    let fadeOut = time > 28.6 ? max(0, 1 - (time - 28.6) / 1.4) : 1
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
let output = CommandLine.arguments.dropFirst().first ?? "showreel-music.wav"
try data.write(to: URL(fileURLWithPath: output))
print("wrote \(output), peak before gain \(String(format: "%.2f", peak))")
