import AVFoundation
import Foundation

/// Sample-accurate musical clock. 16th-note grid.
final class Clock {
    let sampleRate: Double
    var bpm: Double
    private(set) var startHostTime: AVAudioTime?

    init(sampleRate: Double, bpm: Double) {
        self.sampleRate = sampleRate
        self.bpm = bpm
    }

    var secondsPerStep: Double { 60.0 / bpm / 4.0 } // 16th note
    var samplesPerStep: Double { secondsPerStep * sampleRate }

    func start(at time: AVAudioTime) { startHostTime = time }

    /// Sample frame (relative to engine start) of step index `i`.
    func sampleFrame(forStep i: Int) -> AVAudioFramePosition {
        AVAudioFramePosition(Double(i) * samplesPerStep)
    }

    /// Given current sample frame, return next 16th step index >= now.
    func nextStepIndex(currentFrame: AVAudioFramePosition) -> Int {
        let step = Double(currentFrame) / samplesPerStep
        return Int(ceil(step + 0.001))
    }

    func time(forStep i: Int) -> AVAudioTime {
        AVAudioTime(sampleTime: sampleFrame(forStep: i), atRate: sampleRate)
    }
}
