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

    // ADSR-ish exponential decay
    private static func decay(_ t: Double, _ tau: Double) -> Double {
        exp(-t / tau)
    }

    static func kick() -> AVAudioPCMBuffer {
        makeBuffer(seconds: 0.35) { _, t in
            let pitch = 120.0 * exp(-t * 18.0) + 45.0
            let env = decay(t, 0.12)
            let s = sin(2 * .pi * pitch * t) * env
            return Float(s * 0.9)
        }
    }

    static func snare() -> AVAudioPCMBuffer {
        makeBuffer(seconds: 0.25) { _, t in
            let noise = Double.random(in: -1...1)
            let tone = sin(2 * .pi * 220 * t)
            let env = decay(t, 0.09)
            return Float((noise * 0.7 + tone * 0.3) * env * 0.6)
        }
    }

    static func hat(open: Bool = false) -> AVAudioPCMBuffer {
        let dur = open ? 0.18 : 0.06
        let tau = open ? 0.06 : 0.02
        return makeBuffer(seconds: dur) { _, t in
            let n = Double.random(in: -1...1)
            let env = decay(t, tau)
            return Float(n * env * 0.35)
        }
    }

    static func perc() -> AVAudioPCMBuffer {
        makeBuffer(seconds: 0.12) { _, t in
            let f = 800.0 + 600.0 * exp(-t * 30)
            let s = sin(2 * .pi * f * t) * decay(t, 0.04)
            return Float(s * 0.5)
        }
    }

    /// Pitched tone using triangle wave + envelope.
    static func tone(midi: Int, duration: Double = 0.35, wave: Wave = .triangle, gain: Double = 0.4) -> AVAudioPCMBuffer {
        let freq = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
        return makeBuffer(seconds: duration) { _, t in
            let phase = (t * freq).truncatingRemainder(dividingBy: 1.0)
            let raw: Double
            switch wave {
            case .sine:     raw = sin(2 * .pi * phase)
            case .triangle: raw = 2 * abs(2 * (phase - floor(phase + 0.5))) - 1
            case .saw:      raw = 2 * (phase - floor(phase + 0.5))
            case .square:   raw = phase < 0.5 ? 1 : -1
            }
            let attack = min(1.0, t / 0.005)
            let env = attack * decay(t, duration * 0.4)
            return Float(raw * env * gain)
        }
    }

    enum Wave { case sine, triangle, saw, square }
}
