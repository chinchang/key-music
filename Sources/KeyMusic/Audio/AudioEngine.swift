import AVFoundation
import AppKit
import Combine
import SwiftUI

/// Heart of the app. Owns AVAudioEngine, the clock, all player nodes,
/// the drum sequencer, and the queue of pending key-triggered events.
final class AudioEngine: ObservableObject, @unchecked Sendable {
    @Published var bpm: Double = 96
    let layers = Layers()
    let mapper = KeyMapper()

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private let drumPlayer = AVAudioPlayerNode()
    private let bassPlayer = AVAudioPlayerNode()
    private let arpPlayer = AVAudioPlayerNode()
    private let leadPlayer = AVAudioPlayerNode()
    private let accentPlayer = AVAudioPlayerNode()

    private lazy var clock = Clock(sampleRate: Synth.sampleRate, bpm: bpm)

    // Pre-rendered buffers
    private let kickBuf = Synth.kick()
    private let snareBuf = Synth.snare()
    private let hatBuf = Synth.hat()
    private let openHatBuf = Synth.hat(open: true)
    private let percBuf = Synth.perc()

    // Pending events keyed by absolute step index (16th note grid)
    private var pending: [Int: [PendingEvent]] = [:]
    private let pendingQueue = DispatchQueue(label: "keymusic.pending")

    private var scheduledThroughStep: Int = -1
    private var ticker: DispatchSourceTimer?
    private var startSampleTime: AVAudioFramePosition = 0
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    @Published var globalListening: Bool = false

    struct PendingEvent {
        enum Kind { case bass, arp, lead, accent }
        let kind: Kind
        let midi: Int
    }

    init() {
        engine.attach(mixer)
        engine.attach(drumPlayer)
        engine.attach(bassPlayer)
        engine.attach(arpPlayer)
        engine.attach(leadPlayer)
        engine.attach(accentPlayer)
        let fmt = Synth.format()
        engine.connect(drumPlayer, to: mixer, format: fmt)
        engine.connect(bassPlayer, to: mixer, format: fmt)
        engine.connect(arpPlayer, to: mixer, format: fmt)
        engine.connect(leadPlayer, to: mixer, format: fmt)
        engine.connect(accentPlayer, to: mixer, format: fmt)
        engine.connect(mixer, to: engine.mainMixerNode, format: fmt)
        mixer.outputVolume = 0.9
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
        startSampleTime = drumPlayer.lastRenderTime?.sampleTime ?? 0

        let t = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        t.schedule(deadline: .now(), repeating: .milliseconds(20))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        ticker = t

        installGlobalKeyMonitor()
    }

    // MARK: - Global key listening

    func installGlobalKeyMonitor() {
        // Prompt for Accessibility permission if not yet granted.
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
            // Also catch keys when our own window is key (global monitor doesn't fire then).
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
                    self?.handleCharacters(chars)
                }
                return event
            }
        }
    }

    // MARK: - Sequencer

    private func currentFrame() -> AVAudioFramePosition {
        guard let lr = drumPlayer.lastRenderTime,
              lr.isSampleTimeValid || lr.isHostTimeValid else { return 0 }
        guard let pt = drumPlayer.playerTime(forNodeTime: lr),
              pt.isSampleTimeValid else { return 0 }
        return pt.sampleTime
    }

    /// Look ahead ~250ms and schedule any unscheduled 16th-note steps.
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
            scheduleStep(step)
        }
        scheduledThroughStep = lastStep
    }

    private func scheduleStep(_ step: Int) {
        let when = clock.time(forStep: step)
        let beat16 = step % 16

        // ---- Drums (always) ----
        // 4-on-the-floor kick on every quarter (steps 0,4,8,12)
        if beat16 % 4 == 0 {
            drumPlayer.scheduleBuffer(kickBuf, at: when, options: [], completionHandler: nil)
        }
        // Snare on 2 and 4 (steps 4 and 12)
        if beat16 == 4 || beat16 == 12 {
            drumPlayer.scheduleBuffer(snareBuf, at: when, options: [], completionHandler: nil)
        }
        // Hats on every 8th, open hat on the &-of-4
        if beat16 % 2 == 0 {
            let buf = (beat16 == 14) ? openHatBuf : hatBuf
            drumPlayer.scheduleBuffer(buf, at: when, options: [], completionHandler: nil)
        }

        // ---- Bass groove ----
        if layers.isActive(.bass) {
            // Root on 1, fifth on the &-of-3, octave on 4
            let root = 36 // C2
            if beat16 == 0 {
                let b = Synth.tone(midi: root, duration: 0.45, wave: .saw, gain: 0.5)
                bassPlayer.scheduleBuffer(b, at: when, options: [], completionHandler: nil)
            } else if beat16 == 10 {
                let b = Synth.tone(midi: root + 7, duration: 0.3, wave: .saw, gain: 0.45)
                bassPlayer.scheduleBuffer(b, at: when, options: [], completionHandler: nil)
            } else if beat16 == 12 {
                let b = Synth.tone(midi: root + 12, duration: 0.3, wave: .saw, gain: 0.45)
                bassPlayer.scheduleBuffer(b, at: when, options: [], completionHandler: nil)
            }
        }

        // ---- Arpeggio ----
        if layers.isActive(.arp) {
            let scale = [60, 63, 65, 67, 70, 72] // C minor pent + b3
            let note = scale[beat16 % scale.count]
            let buf = Synth.tone(midi: note, duration: 0.18, wave: .triangle, gain: 0.28)
            arpPlayer.scheduleBuffer(buf, at: when, options: [], completionHandler: nil)
        }

        // ---- Pending key-triggered events for this step ----
        let events: [PendingEvent] = pendingQueue.sync {
            let e = pending[step] ?? []
            pending.removeValue(forKey: step)
            return e
        }
        for ev in events {
            switch ev.kind {
            case .bass:
                let b = Synth.tone(midi: ev.midi, duration: 0.35, wave: .saw, gain: 0.5)
                bassPlayer.scheduleBuffer(b, at: when, options: [], completionHandler: nil)
            case .arp:
                let b = Synth.tone(midi: ev.midi, duration: 0.22, wave: .triangle, gain: 0.35)
                arpPlayer.scheduleBuffer(b, at: when, options: [], completionHandler: nil)
            case .lead:
                let b = Synth.tone(midi: ev.midi, duration: 0.4, wave: .square, gain: 0.25)
                leadPlayer.scheduleBuffer(b, at: when, options: [], completionHandler: nil)
            case .accent:
                accentPlayer.scheduleBuffer(percBuf, at: when, options: [], completionHandler: nil)
            }
        }
    }

    // MARK: - Key handling

    func handleKey(_ press: KeyPress) {
        handleCharacters(press.characters)
    }

    func handleCharacters(_ characters: String) {
        let event = mapper.process(characters: characters)
        guard let event else { return }

        // Quantize to next 16th step
        let now = currentFrame()
        let step = clock.nextStepIndex(currentFrame: now)

        let pe: PendingEvent
        switch event.kind {
        case .pitched(let midi):
            // Choose voice by current intensity
            let i = mapper.intensity
            let kind: PendingEvent.Kind = i > 0.75 ? .lead : (i > 0.4 ? .arp : .arp)
            pe = PendingEvent(kind: kind, midi: midi)
        case .bass(let midi):
            pe = PendingEvent(kind: .bass, midi: midi)
        case .accent:
            pe = PendingEvent(kind: .accent, midi: 0)
        case .kick:
            // schedule a kick directly on next step
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
