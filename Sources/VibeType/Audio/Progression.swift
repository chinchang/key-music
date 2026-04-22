import Foundation

enum Mood: Hashable, CaseIterable {
    case happy, romantic, neutral, sad, depressed, angry

    /// Map a (valence, arousal) point on Russell's circumplex to one of six moods.
    static func classify(valence v: Double, arousal a: Double) -> Mood {
        if v <= -0.20 && a >= 0.25 { return .angry }
        if v <= -0.45 && a <= 0.05 { return .depressed }
        if v <= -0.20 { return .sad }
        if v >= 0.35 && a >= 0.20 { return .happy }
        if v >= 0.20 { return .romantic }
        return .neutral
    }
}

struct Chord {
    let rootPitchClass: Int
    let intervals: [Int]

    func rootMidi(octave: Int) -> Int {
        12 * (octave + 1) + rootPitchClass
    }

    func triadNotes(octave: Int) -> [Int] {
        let base = rootMidi(octave: octave)
        return intervals.map { base + $0 }
    }
}

final class Progression {
    struct Bank {
        let chords: [Chord]
        let scalePitchClasses: Set<Int>
    }

    private let banks: [Mood: Bank]
    private var currentMood: Mood = .neutral
    private var currentTranspose: Int = 0
    private let queue = DispatchQueue(label: "keymusic.progression")

    init(banks: [Mood: Bank]) {
        for m in Mood.allCases {
            precondition(banks[m] != nil, "bank for \(m) required")
        }
        self.banks = banks
    }

    static let `default`: Progression = {
        let minor: [Int] = [0, 3, 7]
        let major: [Int] = [0, 4, 7]
        let maj7: [Int]  = [0, 4, 7, 11]
        let min7: [Int]  = [0, 3, 7, 10]
        let dom7: [Int]  = [0, 4, 7, 10]

        let cMajor: Set<Int>        = [0, 2, 4, 5, 7, 9, 11]
        let cNaturalMinor: Set<Int> = [0, 2, 3, 5, 7, 8, 10]
        let cPhrygian: Set<Int>     = [0, 1, 3, 5, 7, 8, 10]

        // I – V – vi – IV in C major (classic upbeat pop)
        let happy = Bank(chords: [
            Chord(rootPitchClass: 0, intervals: major),
            Chord(rootPitchClass: 7, intervals: major),
            Chord(rootPitchClass: 9, intervals: minor),
            Chord(rootPitchClass: 5, intervals: major),
        ], scalePitchClasses: cMajor)

        // ii7 – V7 – Imaj7 – vi7 in C major (jazz, warm, intimate)
        let romantic = Bank(chords: [
            Chord(rootPitchClass: 2, intervals: min7),
            Chord(rootPitchClass: 7, intervals: dom7),
            Chord(rootPitchClass: 0, intervals: maj7),
            Chord(rootPitchClass: 9, intervals: min7),
        ], scalePitchClasses: cMajor)

        // i – VI – III – VII in C natural minor (brooding but moving)
        let neutral = Bank(chords: [
            Chord(rootPitchClass: 0,  intervals: minor),
            Chord(rootPitchClass: 8,  intervals: major),
            Chord(rootPitchClass: 3,  intervals: major),
            Chord(rootPitchClass: 10, intervals: major),
        ], scalePitchClasses: cNaturalMinor)

        // i – iv – v – i in C minor (traditional sad ballad)
        let sad = Bank(chords: [
            Chord(rootPitchClass: 0, intervals: minor),
            Chord(rootPitchClass: 5, intervals: minor),
            Chord(rootPitchClass: 7, intervals: minor),
            Chord(rootPitchClass: 0, intervals: minor),
        ], scalePitchClasses: cNaturalMinor)

        // i – iv – i – iv in C minor (endless, resigned, nothing resolves)
        let depressed = Bank(chords: [
            Chord(rootPitchClass: 0, intervals: minor),
            Chord(rootPitchClass: 5, intervals: minor),
            Chord(rootPitchClass: 0, intervals: minor),
            Chord(rootPitchClass: 5, intervals: minor),
        ], scalePitchClasses: cNaturalMinor)

        // i – bII – i – bVII in C Phrygian (flattened-second Spanish/metal tension)
        let angry = Bank(chords: [
            Chord(rootPitchClass: 0,  intervals: minor),
            Chord(rootPitchClass: 1,  intervals: major),
            Chord(rootPitchClass: 0,  intervals: minor),
            Chord(rootPitchClass: 10, intervals: major),
        ], scalePitchClasses: cPhrygian)

        return Progression(banks: [
            .happy:     happy,
            .romantic:  romantic,
            .neutral:   neutral,
            .sad:       sad,
            .depressed: depressed,
            .angry:     angry,
        ])
    }()

    func setMood(_ mood: Mood) {
        queue.sync { currentMood = mood }
    }

    func mood() -> Mood {
        queue.sync { currentMood }
    }

    func setTranspose(_ semitones: Int) {
        queue.sync { currentTranspose = ((semitones % 12) + 12) % 12 }
    }

    func transpose() -> Int {
        queue.sync { currentTranspose }
    }

    var barsPerPhrase: Int {
        queue.sync { banks[currentMood]!.chords.count }
    }

    func chord(forStep step: Int) -> Chord {
        let (bank, trans) = queue.sync { (banks[currentMood]!, currentTranspose) }
        let n = bank.chords.count
        let bar = ((step / 16) % n + n) % n
        let base = bank.chords[bar]
        return Chord(
            rootPitchClass: ((base.rootPitchClass + trans) % 12 + 12) % 12,
            intervals: base.intervals
        )
    }

    func barInPhrase(forStep step: Int) -> Int {
        let bank = queue.sync { banks[currentMood]! }
        let n = bank.chords.count
        return ((step / 16) % n + n) % n
    }

    func snapToScale(midi: Int) -> Int {
        let (scale, trans) = queue.sync {
            (banks[currentMood]!.scalePitchClasses, currentTranspose)
        }
        let transposed = Set(scale.map { (($0 + trans) % 12 + 12) % 12 })
        return Self.snap(midi: midi, scale: transposed)
    }

    func quantize(midi: Int, toChordAtStep step: Int, chordBias: Int = 2) -> Int {
        let (bank, trans) = queue.sync { (banks[currentMood]!, currentTranspose) }
        let n = bank.chords.count
        let bar = ((step / 16) % n + n) % n
        let base = bank.chords[bar]
        let transposedRoot = ((base.rootPitchClass + trans) % 12 + 12) % 12

        for delta in 0...chordBias {
            for sign in [1, -1] {
                let candidate = midi + sign * delta
                let pc = ((candidate % 12) + 12) % 12
                let interval = ((pc - transposedRoot) % 12 + 12) % 12
                if base.intervals.contains(interval) { return candidate }
            }
        }
        let transposedScale = Set(bank.scalePitchClasses.map { (($0 + trans) % 12 + 12) % 12 })
        return Self.snap(midi: midi, scale: transposedScale)
    }

    private static func snap(midi: Int, scale: Set<Int>) -> Int {
        var best = midi
        var bestDist = Int.max
        for delta in -6...6 {
            let candidate = midi + delta
            let pc = ((candidate % 12) + 12) % 12
            if scale.contains(pc) && abs(delta) < bestDist {
                best = candidate
                bestDist = abs(delta)
            }
        }
        return best
    }
}
