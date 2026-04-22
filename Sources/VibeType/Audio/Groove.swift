import Foundation

/// Humanizes the otherwise-gridlocked sequencer output: swing on odd 16ths, tiny timing
/// jitter on non-downbeat steps, and per-step velocity variance. Everything is deterministic
/// per step so scheduling the same step twice produces the same offset.
struct Groove {
    var swing: Double = 0.12
    var timingJitterMs: Double = 2.0
    var velocityJitter: Double = 0.12

    /// Extra frames to add to the step's scheduled time.
    func frameOffset(forStep step: Int, samplesPerStep: Double, sampleRate: Double) -> Double {
        let beat16 = ((step % 16) + 16) % 16
        if beat16 == 0 { return 0 }

        var offset: Double = 0
        if beat16 % 2 == 1 {
            offset += swing * samplesPerStep
        }
        if timingJitterMs > 0 {
            let r = unit(step, salt: 0x5A17)
            offset += (r * 2 - 1) * timingJitterMs / 1000.0 * sampleRate
        }
        return offset
    }

    /// Scale a base gain by a step-deterministic factor around 1.0.
    func velocity(base: Double, forStep step: Int, salt: UInt64 = 0) -> Double {
        let r = unit(step, salt: 0xF001 &+ salt)
        return base * (1 + (r * 2 - 1) * velocityJitter)
    }

    private func unit(_ step: Int, salt: UInt64) -> Double {
        var x = UInt64(bitPattern: Int64(step)) &+ salt
        x ^= (x &>> 33)
        x &*= 0xff51afd7ed558ccd
        x ^= (x &>> 33)
        x &*= 0xc4ceb9fe1a85ec53
        x ^= (x &>> 33)
        return Double(x & 0xFFFFFF) / Double(0x1000000)
    }
}
