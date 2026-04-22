import AVFoundation
import AppKit
import Combine
import SwiftUI

/// Heart of the app. Owns AVAudioEngine, the clock, player nodes, the effects graph,
/// the progression/groove/mood, and the queue of pending key-triggered events.
final class AudioEngine: ObservableObject, @unchecked Sendable {
    @Published var bpm: Double = 96
    let layers = Layers()
    let mapper = KeyMapper()
    let mood = MoodAnalyzer()
    let progression = Progression.default
    var groove = Groove()

    @Published var moodValence: Double = 0
    @Published var moodArousal: Double = 0
    @Published var moodLabel: String = "neutral"

    private let engine = AVAudioEngine()
    private let drumPlayer = AVAudioPlayerNode()
    private let bassPlayer = AVAudioPlayerNode()
    private let arpPlayer = AVAudioPlayerNode()
    private let leadPlayer = AVAudioPlayerNode()
    private let accentPlayer = AVAudioPlayerNode()
    private let effects: Effects

    private lazy var clock = Clock(sampleRate: Synth.sampleRate, bpm: bpm)

    private var pending: [Int: [PendingEvent]] = [:]
    private let pendingQueue = DispatchQueue(label: "keymusic.pending")

    private var scheduledThroughStep: Int = -1
    private var ticker: DispatchSourceTimer?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    @Published var globalListening: Bool = false

    private var appliedMood: Mood = .neutral
    private var currentBrightness: Double = 1.0

    private var bassInactiveBars: Int = 0
    private var hasBeenActive: Bool = false
    private var restartIndex: Int = 0
    private let transposeRotation: [Int] = [0, 5, 7, 3, 10, 2]

    struct PendingEvent {
        enum Kind { case bass, arp, lead, accent }
        let kind: Kind
        let midi: Int
    }

    init() {
        engine.attach(drumPlayer)
        engine.attach(bassPlayer)
        engine.attach(arpPlayer)
        engine.attach(leadPlayer)
        engine.attach(accentPlayer)
        effects = Effects(
            engine: engine,
            drumPlayer: drumPlayer,
            bassPlayer: bassPlayer,
            arpPlayer: arpPlayer,
            leadPlayer: leadPlayer,
            accentPlayer: accentPlayer
        )
        effects.apply(mood: .neutral)
    }

    func start() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            print("Audio engine failed: \(error)")
            return
        }
        let now = AVAudioTime(sampleTime: 0, atRate: Synth.sampleRate)
        drumPlayer.play(at: now)
        bassPlayer.play(at: now)
        arpPlayer.play(at: now)
        leadPlayer.play(at: now)
        accentPlayer.play(at: now)

        let t = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        t.schedule(deadline: .now(), repeating: .milliseconds(20))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        ticker = t

        installGlobalKeyMonitor()
    }

    func installGlobalKeyMonitor() {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(opts)
        DispatchQueue.main.async { self.globalListening = trusted }

        if globalKeyMonitor == nil {
            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self, let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return }
                self.handleCharacters(chars)
            }
        }
        if localKeyMonitor == nil {
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
                    self?.handleCharacters(chars)
                }
                return event
            }
        }
    }

    private func currentFrame() -> AVAudioFramePosition {
        guard let lr = drumPlayer.lastRenderTime,
              lr.isSampleTimeValid || lr.isHostTimeValid else { return 0 }
        guard let pt = drumPlayer.playerTime(forNodeTime: lr),
              pt.isSampleTimeValid else { return 0 }
        return pt.sampleTime
    }

    private func tick() {
        let lookaheadSeconds = 0.25
        let now = currentFrame()
        let lookaheadFrames = AVAudioFramePosition(lookaheadSeconds * Synth.sampleRate)
        let horizon = now + lookaheadFrames
        let lastStep = Int(Double(horizon) / clock.samplesPerStep)
        let firstStep = max(scheduledThroughStep + 1, clock.nextStepIndex(currentFrame: now))
        if lastStep < firstStep { return }

        refreshLayers()

        for step in firstStep...lastStep {
            if step % 16 == 0 {
                commitMoodIfChanged()
                checkRestartAtBarBoundary()
            }
            scheduleStep(step)
        }
        scheduledThroughStep = lastStep

        publishMood()
    }

    private func checkRestartAtBarBoundary() {
        let bassActive = layers.isActive(.bass)
        if !bassActive {
            bassInactiveBars += 1
            return
        }
        if hasBeenActive && bassInactiveBars >= 2 {
            restartIndex = (restartIndex + 1) % transposeRotation.count
            progression.setTranspose(transposeRotation[restartIndex])
        }
        hasBeenActive = true
        bassInactiveBars = 0
    }

    private func commitMoodIfChanged() {
        let next = mood.dominantMood
        guard next != appliedMood else { return }
        appliedMood = next
        progression.setMood(next)
        effects.apply(mood: next)
        currentBrightness = Self.brightness(for: next)
    }

    private static func brightness(for mood: Mood) -> Double {
        switch mood {
        case .happy:     return 1.6
        case .romantic:  return 1.25
        case .neutral:   return 1.0
        case .sad:       return 0.75
        case .depressed: return 0.45
        case .angry:     return 1.1
        }
    }

    private static func arpOctaveShift(for mood: Mood) -> Int {
        switch mood {
        case .happy:     return 12
        case .romantic:  return 7
        case .neutral:   return 0
        case .sad:       return -7
        case .depressed: return -12
        case .angry:     return 0
        }
    }

    private static func label(for mood: Mood) -> String {
        switch mood {
        case .happy:     return "happy"
        case .romantic:  return "romantic"
        case .neutral:   return "neutral"
        case .sad:       return "sad"
        case .depressed: return "depressed"
        case .angry:     return "angry"
        }
    }

    private func publishMood() {
        let v = mood.valence
        let a = mood.arousal
        let label = Self.label(for: appliedMood)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if abs(self.moodValence - v) > 0.005 { self.moodValence = v }
            if abs(self.moodArousal - a) > 0.005 { self.moodArousal = a }
            if self.moodLabel != label { self.moodLabel = label }
        }
    }

    private func groovedTime(forStep step: Int) -> AVAudioTime {
        let base = Double(clock.sampleFrame(forStep: step))
        let offset = groove.frameOffset(
            forStep: step,
            samplesPerStep: clock.samplesPerStep,
            sampleRate: Synth.sampleRate
        )
        return AVAudioTime(sampleTime: AVAudioFramePosition(base + offset), atRate: Synth.sampleRate)
    }

    private func scheduleStep(_ step: Int) {
        let when = groovedTime(forStep: step)
        let chord = progression.chord(forStep: step)
        let barInPhrase = progression.barInPhrase(forStep: step)
        let brightness = currentBrightness
        let mood = appliedMood

        for hit in Patterns.drumHits(
            forStep: step,
            barInPhrase: barInPhrase,
            barsPerPhrase: progression.barsPerPhrase,
            mood: mood
        ) {
            let g = groove.velocity(base: hit.gain, forStep: step, salt: 0x1)
            let buf = drumBuffer(for: hit.voice, gain: g)
            drumPlayer.scheduleBuffer(buf, at: when, options: [], completionHandler: nil)
        }

        if layers.isActive(.bass) {
            for hit in Patterns.bassHits(forStep: step, chord: chord, barInPhrase: barInPhrase, mood: mood) {
                let g = groove.velocity(base: hit.gain, forStep: step, salt: 0x2)
                let buf = Synth.bassTone(midi: hit.midi, duration: hit.duration, gain: g, brightness: brightness)
                bassPlayer.scheduleBuffer(buf, at: when, options: [], completionHandler: nil)
            }
        }

        if layers.isActive(.arp) {
            let octaveShift = Self.arpOctaveShift(for: mood)
            for hit in Patterns.arpHits(forStep: step, chord: chord, barInPhrase: barInPhrase, mood: mood) {
                let g = groove.velocity(base: hit.gain, forStep: step, salt: 0x3)
                let buf = Synth.arpTone(midi: hit.midi + octaveShift, duration: hit.duration, gain: g, brightness: brightness)
                arpPlayer.scheduleBuffer(buf, at: when, options: [], completionHandler: nil)
            }
        }

        let events: [PendingEvent] = pendingQueue.sync {
            let e = pending[step] ?? []
            pending.removeValue(forKey: step)
            return e
        }
        for (idx, ev) in events.enumerated() {
            let salt = UInt64(0x100 &+ idx)
            switch ev.kind {
            case .bass:
                let g = groove.velocity(base: 0.5, forStep: step, salt: salt)
                bassPlayer.scheduleBuffer(
                    Synth.bassTone(midi: ev.midi, duration: 0.35, gain: g, brightness: brightness),
                    at: when, options: [], completionHandler: nil
                )
            case .arp:
                let g = groove.velocity(base: 0.35, forStep: step, salt: salt)
                arpPlayer.scheduleBuffer(
                    Synth.arpTone(midi: ev.midi, duration: 0.22, gain: g, brightness: brightness),
                    at: when, options: [], completionHandler: nil
                )
            case .lead:
                let g = groove.velocity(base: 0.3, forStep: step, salt: salt)
                leadPlayer.scheduleBuffer(
                    Synth.leadTone(midi: ev.midi, duration: 0.4, gain: g, brightness: brightness),
                    at: when, options: [], completionHandler: nil
                )
            case .accent:
                accentPlayer.scheduleBuffer(
                    Synth.perc(gain: 0.9),
                    at: when, options: [], completionHandler: nil
                )
            }
        }
    }

    private func drumBuffer(for voice: DrumVoice, gain: Double) -> AVAudioPCMBuffer {
        switch voice {
        case .kick:    return Synth.kick(gain: gain)
        case .snare:   return Synth.snare(gain: gain)
        case .hat:     return Synth.hat(open: false, gain: gain)
        case .openHat: return Synth.hat(open: true, gain: gain)
        case .perc:    return Synth.perc(gain: gain)
        }
    }

    func handleKey(_ press: KeyPress) {
        handleCharacters(press.characters)
    }

    func handleCharacters(_ characters: String) {
        mood.append(characters: characters)

        guard let event = mapper.process(characters: characters) else { return }

        let now = currentFrame()
        let step = clock.nextStepIndex(currentFrame: now)

        let pe: PendingEvent
        switch event.kind {
        case .pitched(let midi):
            let quantized = progression.quantize(midi: midi, toChordAtStep: step)
            let kind: PendingEvent.Kind = mapper.intensity > 0.75 ? .lead : .arp
            pe = PendingEvent(kind: kind, midi: quantized)
        case .bass(let midi):
            let quantized = progression.quantize(midi: midi, toChordAtStep: step, chordBias: 3)
            pe = PendingEvent(kind: .bass, midi: quantized)
        case .accent:
            pe = PendingEvent(kind: .accent, midi: 0)
        case .kick:
            pendingQueue.sync {
                pending[step, default: []].append(PendingEvent(kind: .accent, midi: 0))
            }
            return
        }
        pendingQueue.sync {
            pending[step, default: []].append(pe)
        }
    }

    private func refreshLayers() {
        let i = mapper.intensity
        layers.setActive(.bass, i > 0.2)
        layers.setActive(.arp,  i > 0.5)
        layers.setActive(.lead, i > 0.8)
        DispatchQueue.main.async { [weak self] in self?.objectWillChange.send() }
    }
}
