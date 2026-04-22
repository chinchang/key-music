import AVFoundation

/// Aux-send mixing graph: each voice splits into dry, reverb-send, and delay-send mixers.
/// Reverb and delay are single shared nodes that sum all sends and return into the main mixer.
final class Effects {
    struct Voice {
        let dry: AVAudioMixerNode
        let reverbSend: AVAudioMixerNode
        let delaySend: AVAudioMixerNode
    }

    let drum: Voice
    let bass: Voice
    let arp: Voice
    let lead: Voice
    let accent: Voice

    private let reverb: AVAudioUnitReverb
    private let delay: AVAudioUnitDelay
    private let reverbBus: AVAudioMixerNode
    private let delayBus: AVAudioMixerNode

    init(
        engine: AVAudioEngine,
        drumPlayer: AVAudioPlayerNode,
        bassPlayer: AVAudioPlayerNode,
        arpPlayer: AVAudioPlayerNode,
        leadPlayer: AVAudioPlayerNode,
        accentPlayer: AVAudioPlayerNode
    ) {
        let fmt = Synth.format()

        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 100

        let delay = AVAudioUnitDelay()
        delay.delayTime = 0.375
        delay.feedback = 30
        delay.lowPassCutoff = 4000
        delay.wetDryMix = 100

        let reverbBus = AVAudioMixerNode()
        let delayBus = AVAudioMixerNode()

        engine.attach(reverb)
        engine.attach(delay)
        engine.attach(reverbBus)
        engine.attach(delayBus)

        engine.connect(reverbBus, to: reverb, format: fmt)
        engine.connect(delayBus, to: delay, format: fmt)
        engine.connect(reverb, to: engine.mainMixerNode, format: fmt)
        engine.connect(delay, to: engine.mainMixerNode, format: fmt)

        self.reverb = reverb
        self.delay = delay
        self.reverbBus = reverbBus
        self.delayBus = delayBus

        self.drum = Self.makeVoice(
            engine: engine, player: drumPlayer, reverbBus: reverbBus, delayBus: delayBus, fmt: fmt,
            dryLevel: 0.9, pan: 0.0, reverbLevel: 0.08, delayLevel: 0.0
        )
        self.bass = Self.makeVoice(
            engine: engine, player: bassPlayer, reverbBus: reverbBus, delayBus: delayBus, fmt: fmt,
            dryLevel: 0.9, pan: 0.0, reverbLevel: 0.05, delayLevel: 0.0
        )
        self.arp = Self.makeVoice(
            engine: engine, player: arpPlayer, reverbBus: reverbBus, delayBus: delayBus, fmt: fmt,
            dryLevel: 0.7, pan: -0.4, reverbLevel: 0.30, delayLevel: 0.15
        )
        self.lead = Self.makeVoice(
            engine: engine, player: leadPlayer, reverbBus: reverbBus, delayBus: delayBus, fmt: fmt,
            dryLevel: 0.7, pan: 0.3, reverbLevel: 0.40, delayLevel: 0.28
        )
        self.accent = Self.makeVoice(
            engine: engine, player: accentPlayer, reverbBus: reverbBus, delayBus: delayBus, fmt: fmt,
            dryLevel: 0.85, pan: 0.2, reverbLevel: 0.12, delayLevel: 0.0
        )

        engine.mainMixerNode.outputVolume = 0.85
    }

    /// Retune reverb + delay sends on arp/lead according to mood. Dry and pan stay fixed.
    func apply(mood: Mood) {
        switch mood {
        case .happy:
            arp.reverbSend.outputVolume  = 0.32
            arp.delaySend.outputVolume   = 0.20
            lead.reverbSend.outputVolume = 0.45
            lead.delaySend.outputVolume  = 0.30
        case .romantic:
            arp.reverbSend.outputVolume  = 0.55
            arp.delaySend.outputVolume   = 0.35
            lead.reverbSend.outputVolume = 0.70
            lead.delaySend.outputVolume  = 0.45
        case .neutral:
            arp.reverbSend.outputVolume  = 0.30
            arp.delaySend.outputVolume   = 0.15
            lead.reverbSend.outputVolume = 0.40
            lead.delaySend.outputVolume  = 0.28
        case .sad:
            arp.reverbSend.outputVolume  = 0.35
            arp.delaySend.outputVolume   = 0.12
            lead.reverbSend.outputVolume = 0.45
            lead.delaySend.outputVolume  = 0.22
        case .depressed:
            arp.reverbSend.outputVolume  = 0.55
            arp.delaySend.outputVolume   = 0.08
            lead.reverbSend.outputVolume = 0.70
            lead.delaySend.outputVolume  = 0.15
        case .angry:
            arp.reverbSend.outputVolume  = 0.10
            arp.delaySend.outputVolume   = 0.05
            lead.reverbSend.outputVolume = 0.15
            lead.delaySend.outputVolume  = 0.05
        }
    }

    private static func makeVoice(
        engine: AVAudioEngine,
        player: AVAudioPlayerNode,
        reverbBus: AVAudioMixerNode,
        delayBus: AVAudioMixerNode,
        fmt: AVAudioFormat,
        dryLevel: Float,
        pan: Float,
        reverbLevel: Float,
        delayLevel: Float
    ) -> Voice {
        let dry = AVAudioMixerNode()
        let rvb = AVAudioMixerNode()
        let dly = AVAudioMixerNode()
        engine.attach(dry)
        engine.attach(rvb)
        engine.attach(dly)

        let points: [AVAudioConnectionPoint] = [
            AVAudioConnectionPoint(node: dry, bus: 0),
            AVAudioConnectionPoint(node: rvb, bus: 0),
            AVAudioConnectionPoint(node: dly, bus: 0),
        ]
        engine.connect(player, to: points, fromBus: 0, format: fmt)

        dry.outputVolume = dryLevel
        dry.pan = pan
        rvb.outputVolume = reverbLevel
        dly.outputVolume = delayLevel

        engine.connect(dry, to: engine.mainMixerNode, format: fmt)
        engine.connect(rvb, to: reverbBus, format: fmt)
        engine.connect(dly, to: delayBus, format: fmt)

        return Voice(dry: dry, reverbSend: rvb, delaySend: dly)
    }
}
