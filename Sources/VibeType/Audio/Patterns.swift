import Foundation

enum DrumVoice { case kick, snare, hat, openHat, perc }

struct DrumHit {
    let voice: DrumVoice
    let gain: Double
}

struct PitchedHit {
    let midi: Int
    let duration: Double
    let gain: Double
}

enum Patterns {
    static func drumHits(forStep step: Int, barInPhrase: Int, barsPerPhrase: Int, mood: Mood) -> [DrumHit] {
        let beat16 = ((step % 16) + 16) % 16
        let isFillBar = barInPhrase == barsPerPhrase - 1
        switch mood {
        case .happy:     return happyDrums(beat16: beat16, isFillBar: isFillBar)
        case .romantic:  return romanticDrums(beat16: beat16, isFillBar: isFillBar)
        case .neutral:   return neutralDrums(beat16: beat16, isFillBar: isFillBar)
        case .sad:       return sadDrums(beat16: beat16)
        case .depressed: return depressedDrums(beat16: beat16)
        case .angry:     return angryDrums(beat16: beat16)
        }
    }

    static func bassHits(forStep step: Int, chord: Chord, barInPhrase: Int, mood: Mood) -> [PitchedHit] {
        let beat16 = ((step % 16) + 16) % 16
        let root = chord.rootMidi(octave: 2)
        let fifth = 7

        switch mood {
        case .happy:
            switch beat16 {
            case 0:  return [PitchedHit(midi: root,         duration: 0.30, gain: 0.55)]
            case 6:  return [PitchedHit(midi: root,         duration: 0.18, gain: 0.35)]
            case 8:  return [PitchedHit(midi: root + fifth, duration: 0.22, gain: 0.45)]
            case 12: return [PitchedHit(midi: root + 12,    duration: 0.22, gain: 0.45)]
            case 14: return [PitchedHit(midi: root + fifth, duration: 0.18, gain: 0.35)]
            default: return []
            }
        case .romantic:
            switch beat16 {
            case 0: return [PitchedHit(midi: root,         duration: 0.95, gain: 0.45)]
            case 8: return [PitchedHit(midi: root + fifth, duration: 0.95, gain: 0.4)]
            default: return []
            }
        case .neutral:
            switch beat16 {
            case 0:  return [PitchedHit(midi: root,         duration: 0.45, gain: 0.5)]
            case 10: return [PitchedHit(midi: root + fifth, duration: 0.30, gain: 0.45)]
            case 12: return [PitchedHit(midi: root + 12,    duration: 0.30, gain: 0.45)]
            default: return []
            }
        case .sad:
            switch beat16 {
            case 0: return [PitchedHit(midi: root, duration: 0.75, gain: 0.5)]
            case 8: return [PitchedHit(midi: root, duration: 0.75, gain: 0.45)]
            default: return []
            }
        case .depressed:
            if beat16 == 0 {
                // A whole-bar drone: varies the register slightly across bars
                let octaveAdjust = (barInPhrase % 2 == 0) ? 0 : -12
                return [PitchedHit(midi: root + octaveAdjust, duration: 1.6, gain: 0.55)]
            }
            return []
        case .angry:
            if beat16 % 2 == 0 {
                let accent = (beat16 == 0 || beat16 == 8) ? 0.6 : 0.42
                return [PitchedHit(midi: root, duration: 0.12, gain: accent)]
            }
            return []
        }
    }

    static func arpHits(forStep step: Int, chord: Chord, barInPhrase: Int, mood: Mood) -> [PitchedHit] {
        let beat16 = ((step % 16) + 16) % 16
        let triad = chord.triadNotes(octave: 4)
        guard triad.count >= 3 else { return [] }
        let root = triad[0]
        let third = triad[1]
        let fifth = triad[2]

        switch mood {
        case .happy:
            let contours: [[Int]] = [
                [root, third, fifth, third + 12, fifth, third],
                [fifth + 12, third + 12, fifth, third, root, third],
                [root, fifth, third, fifth + 12, third, root + 12],
                [third, fifth, third + 12, root + 12, fifth, third],
            ]
            let note = contours[barInPhrase % contours.count][beat16 % 6]
            return [PitchedHit(midi: note, duration: 0.14, gain: 0.28)]

        case .romantic:
            guard beat16 % 4 == 0 else { return [] }
            let sequences: [[Int]] = [
                [root, third, fifth, third + 12],
                [fifth, third + 12, fifth, third],
                [third, fifth, root + 12, fifth],
                [root, fifth, third + 12, root + 12],
            ]
            let note = sequences[barInPhrase % sequences.count][beat16 / 4 % 4]
            return [PitchedHit(midi: note, duration: 0.55, gain: 0.30)]

        case .neutral:
            let contours: [[Int]] = [
                [root, third, fifth, third + 12, fifth, third],
                [third, fifth, third + 12, fifth, third, root],
                [fifth, third + 12, fifth, third, root, third],
                [third + 12, fifth, third, root, third, fifth],
            ]
            let note = contours[barInPhrase % contours.count][beat16 % 6]
            return [PitchedHit(midi: note, duration: 0.18, gain: 0.28)]

        case .sad:
            guard beat16 % 4 == 0 else { return [] }
            let sequences: [[Int]] = [
                [fifth, third, root, third],
                [third + 12, fifth, third, root],
                [fifth, root, third, fifth],
                [third, root, third, fifth],
            ]
            let note = sequences[barInPhrase % sequences.count][beat16 / 4 % 4]
            return [PitchedHit(midi: note, duration: 0.45, gain: 0.25)]

        case .depressed:
            guard beat16 == 0 else { return [] }
            let notes: [Int] = [root - 12, third - 12, root - 12, fifth - 12]
            return [PitchedHit(midi: notes[barInPhrase % notes.count], duration: 1.7, gain: 0.22)]

        case .angry:
            // Rapid 16ths with a tritone (+6) for bite; contour rotates so it doesn't feel loopy
            let tritone = root + 6
            let contours: [[Int]] = [
                [root, tritone, third, fifth, tritone, third, fifth, root],
                [fifth, tritone, root, fifth, root, tritone, fifth, third],
                [third, root + 12, tritone, fifth, third, tritone, fifth, root],
                [root + 12, fifth, tritone, third, fifth, tritone, root, third],
            ]
            let note = contours[barInPhrase % contours.count][beat16 % 8]
            return [PitchedHit(midi: note, duration: 0.08, gain: 0.26)]
        }
    }

    // MARK: - Drum pattern helpers

    private static func happyDrums(beat16: Int, isFillBar: Bool) -> [DrumHit] {
        if isFillBar && beat16 >= 12 {
            let gains: [Double] = [0.6, 0.75, 0.9, 1.0]
            var hits = [DrumHit(voice: .snare, gain: gains[beat16 - 12])]
            if beat16 == 15 { hits.append(DrumHit(voice: .perc, gain: 0.7)) }
            return hits
        }
        var hits: [DrumHit] = []
        if beat16 % 4 == 0 { hits.append(DrumHit(voice: .kick, gain: 1.0)) }
        if beat16 == 4 || beat16 == 12 { hits.append(DrumHit(voice: .snare, gain: 0.95)) }
        if beat16 == 14 { hits.append(DrumHit(voice: .snare, gain: 0.45)) }
        // Busy 16th hats, softer on the "e" and "a"
        let onBeat = beat16 % 2 == 0
        let offBeat = beat16 % 2 == 1 && (beat16 == 3 || beat16 == 7 || beat16 == 11 || beat16 == 15)
        if onBeat || offBeat {
            let voice: DrumVoice = (beat16 == 14) ? .openHat : .hat
            let gain = onBeat ? 0.6 : 0.3
            hits.append(DrumHit(voice: voice, gain: gain))
        }
        if beat16 == 6 { hits.append(DrumHit(voice: .perc, gain: 0.4)) }
        return hits
    }

    private static func romanticDrums(beat16: Int, isFillBar: Bool) -> [DrumHit] {
        var hits: [DrumHit] = []
        if beat16 == 0 || beat16 == 8 { hits.append(DrumHit(voice: .kick, gain: 0.7)) }
        if beat16 == 4 || beat16 == 12 { hits.append(DrumHit(voice: .snare, gain: 0.5)) }
        if beat16 % 2 == 0 { hits.append(DrumHit(voice: .hat, gain: 0.35)) }
        if isFillBar && beat16 == 14 { hits.append(DrumHit(voice: .perc, gain: 0.5)) }
        return hits
    }

    private static func neutralDrums(beat16: Int, isFillBar: Bool) -> [DrumHit] {
        if isFillBar && beat16 >= 12 {
            let rollGains: [Double] = [0.55, 0.7, 0.85, 1.0]
            var hits = [DrumHit(voice: .snare, gain: rollGains[beat16 - 12])]
            if beat16 == 15 { hits.append(DrumHit(voice: .perc, gain: 0.65)) }
            return hits
        }
        var hits: [DrumHit] = []
        if beat16 % 4 == 0 { hits.append(DrumHit(voice: .kick, gain: 1.0)) }
        if beat16 == 4 || beat16 == 12 { hits.append(DrumHit(voice: .snare, gain: 0.9)) }
        if !isFillBar && (beat16 == 7 || beat16 == 11) {
            hits.append(DrumHit(voice: .snare, gain: 0.22))
        }
        if beat16 % 2 == 0 {
            let open = (beat16 == 14)
            hits.append(DrumHit(voice: open ? .openHat : .hat, gain: open ? 0.7 : 0.6))
        }
        return hits
    }

    private static func sadDrums(beat16: Int) -> [DrumHit] {
        var hits: [DrumHit] = []
        if beat16 == 0 { hits.append(DrumHit(voice: .kick, gain: 0.85)) }
        if beat16 == 8 { hits.append(DrumHit(voice: .snare, gain: 0.75)) }
        if beat16 % 2 == 0 { hits.append(DrumHit(voice: .hat, gain: 0.4)) }
        return hits
    }

    private static func depressedDrums(beat16: Int) -> [DrumHit] {
        if beat16 == 0 { return [DrumHit(voice: .kick, gain: 0.6)] }
        if beat16 == 8 { return [DrumHit(voice: .snare, gain: 0.45)] }
        if beat16 == 4 || beat16 == 12 { return [DrumHit(voice: .hat, gain: 0.25)] }
        return []
    }

    private static func angryDrums(beat16: Int) -> [DrumHit] {
        var hits: [DrumHit] = []
        if beat16 % 4 == 0 { hits.append(DrumHit(voice: .kick, gain: 1.1)) }
        if beat16 == 4 || beat16 == 12 { hits.append(DrumHit(voice: .snare, gain: 1.0)) }
        if beat16 == 2 || beat16 == 6 || beat16 == 10 { hits.append(DrumHit(voice: .snare, gain: 0.55)) }
        let hatGain: Double = beat16 % 2 == 0 ? 0.55 : 0.35
        let voice: DrumVoice = (beat16 == 14 || beat16 == 6) ? .openHat : .hat
        hits.append(DrumHit(voice: voice, gain: hatGain))
        if beat16 == 7 || beat16 == 15 { hits.append(DrumHit(voice: .perc, gain: 0.5)) }
        return hits
    }
}
