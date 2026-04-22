import AVFoundation
import Foundation

enum Synth {
    static let sampleRate: Double = 44_100

    static func format() -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    }

    private static func makeBuffer(seconds: Double, _ fill: (Int, Double) -> Float) -> AVAudioPCMBuffer {
        let fmt = format()
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
        buf.frameLength = frames
        let l = buf.floatChannelData![0]
        let r = buf.floatChannelData![1]
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let s = fill(i, t)
            l[i] = s
            r[i] = s
        }
        return buf
    }

    private static func decay(_ t: Double, _ tau: Double) -> Double {
        exp(-t / tau)
    }

    static func kick(gain: Double = 1.0) -> AVAudioPCMBuffer {
        makeBuffer(seconds: 0.35) { _, t in
            let pitch = 120.0 * exp(-t * 18.0) + 45.0
            let env = decay(t, 0.12)
            let s = sin(2 * .pi * pitch * t) * env
            return Float(s * 0.9 * gain)
        }
    }

    static func snare(gain: Double = 1.0) -> AVAudioPCMBuffer {
        makeBuffer(seconds: 0.25) { _, t in
            let noise = Double.random(in: -1...1)
            let tone = sin(2 * .pi * 220 * t)
            let env = decay(t, 0.09)
            return Float((noise * 0.7 + tone * 0.3) * env * 0.6 * gain)
        }
    }

    static func hat(open: Bool = false, gain: Double = 1.0) -> AVAudioPCMBuffer {
        let dur = open ? 0.18 : 0.06
        let tau = open ? 0.06 : 0.02
        return makeBuffer(seconds: dur) { _, t in
            let n = Double.random(in: -1...1)
            let env = decay(t, tau)
            return Float(n * env * 0.35 * gain)
        }
    }

    static func perc(gain: Double = 1.0) -> AVAudioPCMBuffer {
        makeBuffer(seconds: 0.12) { _, t in
            let f = 800.0 + 600.0 * exp(-t * 30)
            let s = sin(2 * .pi * f * t) * decay(t, 0.04)
            return Float(s * 0.5 * gain)
        }
    }

    struct ToneFilter: Hashable {
        var cutoffStart: Double
        var cutoffEnd: Double
        var tau: Double
    }

    struct ToneEnvelope: Hashable {
        var attack: Double
        var decay: Double
    }

    /// Pitched tone with optional lowpass sweep + AD envelope. Defaults match the original behavior.
    static func tone(
        midi: Int,
        duration: Double = 0.35,
        wave: Wave = .triangle,
        gain: Double = 0.4,
        filter: ToneFilter? = nil,
        envelope: ToneEnvelope? = nil
    ) -> AVAudioPCMBuffer {
        let freq = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
        let env = envelope ?? ToneEnvelope(attack: 0.005, decay: duration * 0.4)
        var y: Double = 0
        return makeBuffer(seconds: duration) { _, t in
            let phase = (t * freq).truncatingRemainder(dividingBy: 1.0)
            let raw: Double
            switch wave {
            case .sine:     raw = sin(2 * .pi * phase)
            case .triangle: raw = 2 * abs(2 * (phase - floor(phase + 0.5))) - 1
            case .saw:      raw = 2 * (phase - floor(phase + 0.5))
            case .square:   raw = phase < 0.5 ? 1 : -1
            }
            let a = min(1.0, t / max(0.0001, env.attack))
            let amp = a * decay(t, max(0.0001, env.decay))
            let x: Double
            if let f = filter {
                let u = 1 - exp(-t / max(0.0001, f.tau))
                let fc = f.cutoffStart + (f.cutoffEnd - f.cutoffStart) * u
                let alpha = 1 - exp(-2 * .pi * fc / sampleRate)
                y += alpha * (raw - y)
                x = y
            } else {
                x = raw
            }
            return Float(x * amp * gain)
        }
    }

    /// Preset voices used by the sequencer and key events.
    /// `brightness` multiplies filter cutoffs — >1 opens up, <1 darkens.
    static func bassTone(midi: Int, duration: Double, gain: Double, brightness: Double = 1.0) -> AVAudioPCMBuffer {
        tone(
            midi: midi,
            duration: duration,
            wave: .saw,
            gain: gain,
            filter: ToneFilter(cutoffStart: 1800 * brightness, cutoffEnd: 350 * brightness, tau: duration * 0.35),
            envelope: ToneEnvelope(attack: 0.004, decay: duration * 0.5)
        )
    }

    static func arpTone(midi: Int, duration: Double, gain: Double, brightness: Double = 1.0) -> AVAudioPCMBuffer {
        tone(
            midi: midi,
            duration: duration,
            wave: .triangle,
            gain: gain,
            filter: ToneFilter(cutoffStart: 4200 * brightness, cutoffEnd: 1600 * brightness, tau: duration * 0.4),
            envelope: ToneEnvelope(attack: 0.003, decay: duration * 0.45)
        )
    }

    static func leadTone(midi: Int, duration: Double, gain: Double, brightness: Double = 1.0) -> AVAudioPCMBuffer {
        tone(
            midi: midi,
            duration: duration,
            wave: .square,
            gain: gain,
            filter: ToneFilter(cutoffStart: 3200 * brightness, cutoffEnd: 1100 * brightness, tau: duration * 0.4),
            envelope: ToneEnvelope(attack: 0.006, decay: duration * 0.55)
        )
    }

    enum Wave: Hashable { case sine, triangle, saw, square }
}
