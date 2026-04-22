# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

KeyMusic is a macOS SwiftUI app that turns typing into music in real time. A base drum loop always plays; typing layers in bass, arps, leads and accents, all quantized to a 16th-note grid.

Swift Package (`Package.swift`), Swift 5.9, `.macOS(.v14)`, single executable target `KeyMusic` rooted at `Sources/KeyMusic`. No tests.

## Commands

- Build: `swift build`
- Run: `swift run KeyMusic` (opens the SwiftUI window)
- Release build: `swift build -c release`
- Clean: `swift package clean`

## Architecture

The app is small but has one non-obvious timing model. Read these together:

- `Audio/AudioEngine.swift` — The heart. Owns an `AVAudioEngine`, five `AVAudioPlayerNode`s (drum/bass/arp/lead/accent), and composes `Progression`, `Patterns`, `Groove`, and `Effects` into the scheduler. A `DispatchSourceTimer` fires every 20 ms (`tick()`) and schedules any 16th-note steps inside a ~250 ms look-ahead. Key-triggered events are placed in `pending[step]` (guarded by `pendingQueue`) and drained when that step is scheduled; their MIDI is re-quantized to the current chord via `progression.quantize(...)`. Intensity thresholds in `refreshLayers()` toggle `bass>0.2`, `arp>0.5`, `lead>0.8`.
- `Audio/Clock.swift` — Sample-accurate conversion between step index and `AVAudioTime`. `secondsPerStep = 60 / bpm / 4` (16th note). Step times are absolute from engine start, which is why `drumPlayer.play(at:)` is called with `sampleTime: 0` and `lastRenderTime` is only used to read "now".
- `Audio/Progression.swift` — Three 4-bar chord banks keyed by `Mood` (positive/neutral/negative). Neutral = i–VI–III–VII in C natural minor (Cm/A♭/E♭/B♭); positive = I–V–vi–IV in C major (C/G/Am/F); negative = i–iv–v–VI in C minor (Cm/Fm/Gm/A♭). `setMood` atomically swaps the active bank (AudioEngine calls this only at bar boundaries so transitions don't clip a phrase mid-chord). `chord(forStep:)` and `quantize(...)` always read the current bank — including its scale, so typed notes re-quantize to C major when positive.
- `Audio/Patterns.swift` — Pure data for drum/bass/arp hits. Four-bar phrase with the last bar replacing steps 12–15 with a snare-roll **fill**; ghost snares on 7/11 in non-fill bars. Bass/arp pattern functions take a `Chord` so root/fifth/triad notes follow the progression.
- `Audio/Groove.swift` — Swing on odd 16ths (default 12% of a step), deterministic-per-step timing jitter (±2 ms) and velocity jitter (±12%). Bar downbeats (`beat16 == 0`) are never offset, so the bar boundary stays locked.
- `Audio/Effects.swift` — Builds the aux-send graph. Per-voice chain = player → [dry mixer, reverb-send mixer, delay-send mixer] via `connect(_:to:[points]...)`. Shared `AVAudioUnitReverb(.mediumHall)` and `AVAudioUnitDelay` (0.375 s = dotted-8th @ 96 BPM, feedback 30%) each fed by a bus mixer, returning into `mainMixerNode`. Per-voice dry level and pan are set at construction; `apply(mood:)` retunes arp/lead reverb+delay sends per mood (airier when positive, drier when negative).
- `Audio/Synth.swift` — Offline-rendered `AVAudioPCMBuffer` factories. Drums (`kick`/`snare`/`hat`/`perc`) take a `gain:` and re-render per hit so ghost/fill gain variations work. Pitched `tone(...)` supports an optional `ToneFilter` (one-pole lowpass with exponential cutoff sweep from `cutoffStart` → `cutoffEnd` over `tau`) and `ToneEnvelope` (AD). `bassTone`/`arpTone`/`leadTone` are preset callers with voice-appropriate filter+envelope defaults and a `brightness:` multiplier that scales cutoffs for mood-driven timbral shifts.
- `Audio/Layers.swift` — Thread-safe `Set<Layer>` plus a UI-facing joined string.
- `Input/KeyMapper.swift` — Maps a character to an `Event` (`pitched`, `bass`, `accent`, `kick`). Letters index into a 2-octave C minor pentatonic, digits into a bass scale, space → kick, newline/punct/symbol → accent. `intensity` is `min(1, (keys in last 2s) / 5)` — ~10 keys in 2 s saturates. The raw MIDI is re-quantized to the current chord downstream in `AudioEngine.handleCharacters`.
- `Input/MoodAnalyzer.swift` — Embedded ~200-word AFINN-inspired valence lexicon (raw −5…+5, normalized to [−1, +1]). Accumulates letters into words on word boundaries (anything non-letter), scores each completed word, and keeps a rolling window of the last 12 scored words; `valence` is that window's mean. All state stays in RAM and is serialized through a private queue. AudioEngine feeds every typed character in via `handleCharacters`, reads `valence` each tick, and applies a hysteresis-banded discrete `Mood` (entry ±0.25, exit ±0.10) at the next bar boundary.
- `ContentView.swift` — `TextEditor` for typing plus a status bar (BPM, intensity, active layers, global-listening indicator).
- `KeyMusicApp.swift` — `@main`. Creates a single `AudioEngine` as `@StateObject`, calls `engine.start()` in `.onAppear`.

### Key input — two monitors

`AudioEngine.installGlobalKeyMonitor()` installs **both** a global and a local `NSEvent` keyDown monitor:

- Global monitor (`NSEvent.addGlobalMonitorForEvents`) fires for keystrokes in *other* apps and requires Accessibility permission. `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt=true` triggers the system prompt on first run; `globalListening` reflects trust state in the UI.
- Local monitor (`NSEvent.addLocalMonitorForEvents`) is required too, because the global monitor does **not** fire when our own window is key. The local monitor returns `event` so typing still reaches the `TextEditor`.

Both handlers funnel into `handleCharacters(_:)`, which converts to a `PendingEvent` quantized to `clock.nextStepIndex(currentFrame:)`.

### Timing invariant

All scheduling uses absolute sample times from engine start. Do not pass relative/"now + offset" times to `scheduleBuffer(at:)` — the look-ahead scheduler assumes step N always maps to frame `N * samplesPerStep`. Groove's swing/jitter is applied on top of that nominal time via `AudioEngine.groovedTime(forStep:)`, never by shifting the step index itself; `Clock`'s step→frame identity stays pure. If you change BPM at runtime you must also rethink `scheduledThroughStep` and the mapping in `Clock`, since the existing code does not re-quantize already-scheduled frames.
