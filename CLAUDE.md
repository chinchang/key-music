# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

VibeType is a macOS SwiftUI app that turns typing into music in real time. A base drum loop always plays; typing layers in bass, arps, leads and accents, all quantized to a 16th-note grid. A menu-bar extra lets the user toggle enable/disable or quit.

Swift Package (`Package.swift`), Swift 5.9, `.macOS(.v14)`, single executable target `VibeType` rooted at `Sources/VibeType`. No tests. The repo directory is still named `key-music/` from before the rename — only the module/executable name changed.

## Commands

- Build: `swift build`
- Run: `swift run VibeType` (opens the SwiftUI window and adds a menu-bar item)
- Release build: `swift build -c release`
- Clean: `swift package clean`

## Architecture

The app is small but has one non-obvious timing model. Read these together:

- `Audio/AudioEngine.swift` — The heart. Owns an `AVAudioEngine`, five `AVAudioPlayerNode`s (drum/bass/arp/lead/accent), and composes `Progression`, `Patterns`, `Groove`, and `Effects` into the scheduler. A `DispatchSourceTimer` fires every 20 ms (`tick()`) and schedules any 16th-note steps inside a ~250 ms look-ahead. Key-triggered events are placed in `pending[step]` (guarded by `pendingQueue`) and drained when that step is scheduled; their MIDI is re-quantized to the current chord via `progression.quantize(...)`. Intensity thresholds in `refreshLayers()` toggle `bass>0.2`, `arp>0.5`, `lead>0.8`. An `isEnabled` flag gates `tick()` and `handleCharacters` — when false, no scheduling happens and keystrokes are ignored (soft mute without tearing down the audio graph). On mood change, the bar-boundary code cycles a transpose rotation when the bass layer has been silent ≥2 bars, so each restart sounds like a fresh key.
- `Audio/Clock.swift` — Sample-accurate conversion between step index and `AVAudioTime`. `secondsPerStep = 60 / bpm / 4` (16th note). Step times are absolute from engine start, which is why `drumPlayer.play(at:)` is called with `sampleTime: 0` and `lastRenderTime` is only used to read "now".
- `Audio/Progression.swift` — Six mood-specific chord banks (happy/romantic/neutral/sad/depressed/angry). Happy = I-V-vi-IV in C major; romantic = ii7-V7-Imaj7-vi7 in C major (jazz 7ths); neutral = i-VI-III-VII in C natural minor; sad = i-iv-v-i in C minor; depressed = i-iv-i-iv in C minor (static); angry = i-♭II-i-♭VII in C Phrygian. `setMood` atomically swaps the active bank (AudioEngine calls it only at bar boundaries). `setTranspose(_:)` stores a semitone offset applied to `chord()`, `quantize(...)`, and the scale used for snapping typed notes. `Mood.classify(valence:arousal:)` is the shared 2D classifier.
- `Audio/Patterns.swift` — Per-mood pattern data. Each mood has its own drum feel (happy=busy 16th hats, romantic=half-time soft, neutral=4-on-floor with bar-4 fill, sad=slow heavy, depressed=kick+snare only, angry=aggressive 8th snares), its own bass rhythm, and its own arp with 4 per-bar contour rotations so the same chord bank doesn't loop bit-identically.
- `Audio/Groove.swift` — Swing on odd 16ths (default 12% of a step), deterministic-per-step timing jitter (±2 ms) and velocity jitter (±12%). Bar downbeats (`beat16 == 0`) are never offset, so the bar boundary stays locked.
- `Audio/Effects.swift` — Builds the aux-send graph. Per-voice chain = player → [dry mixer, reverb-send mixer, delay-send mixer] via `connect(_:to:[points]...)`. Shared `AVAudioUnitReverb(.mediumHall)` and `AVAudioUnitDelay` (0.375 s = dotted-8th @ 96 BPM, feedback 30%) each fed by a bus mixer, returning into `mainMixerNode`. Per-voice dry level and pan are set at construction; `apply(mood:)` retunes arp/lead reverb+delay sends per mood (angry is driest, romantic/depressed are wettest).
- `Audio/Synth.swift` — Offline-rendered `AVAudioPCMBuffer` factories. Drums (`kick`/`snare`/`hat`/`perc`) take a `gain:` and re-render per hit so ghost/fill gain variations work. Pitched `tone(...)` supports an optional `ToneFilter` (one-pole lowpass with exponential cutoff sweep) and `ToneEnvelope` (AD). `bassTone`/`arpTone`/`leadTone` are preset callers with voice-appropriate defaults and a `brightness:` multiplier that scales cutoffs for mood-driven timbral shifts (happy=1.6×, depressed=0.45×).
- `Audio/Layers.swift` — Thread-safe `Set<Layer>` plus a UI-facing joined string.
- `Input/KeyMapper.swift` — Maps a character to an `Event` (`pitched`, `bass`, `accent`, `kick`). Letters index into a 2-octave C minor pentatonic, digits into a bass scale, space → kick, newline/punct/symbol → accent. `intensity` is `min(1, (keys in last 2s) / 5)` — ~10 keys in 2 s saturates.
- `Input/MoodAnalyzer.swift` — Two hand-tuned lexicons (valence + arousal, both normalized to [-1, +1]) scoring typed words on Russell's circumplex. Valence and arousal use an EMA (α=0.5) for the UI numbers. A separate 6-slot FIFO of per-word mood classifications drives `dominantMood` via exponentially-recency-weighted vote (decay 0.6) — 2 consecutive opposing words are enough to flip directly to a new mood, skipping intermediate thresholds. AudioEngine reads `dominantMood` at bar boundaries to commit mood changes.
- `ContentView.swift` — `TextEditor` for typing plus a status bar (BPM, intensity, colored mood label, live valence+arousal, active layers, global-listening indicator).
- `VibeTypeApp.swift` — `@main`. Creates a single `AudioEngine` as `@StateObject`, starts it in `.onAppear`. Also declares a `MenuBarExtra` scene that shows a `music.note` / `music.note.slash` icon in the system menu bar with an Enable/Disable toggle and a Quit item.

### Key input — two monitors

`AudioEngine.installGlobalKeyMonitor()` installs **both** a global and a local `NSEvent` keyDown monitor:

- Global monitor (`NSEvent.addGlobalMonitorForEvents`) fires for keystrokes in *other* apps and requires Accessibility permission. `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt=true` triggers the system prompt on first run; `globalListening` reflects trust state in the UI.
- Local monitor (`NSEvent.addLocalMonitorForEvents`) is required too, because the global monitor does **not** fire when our own window is key. The local monitor returns `event` so typing still reaches the `TextEditor`.

Both handlers funnel into `handleCharacters(_:)`, which converts to a `PendingEvent` quantized to `clock.nextStepIndex(currentFrame:)`.

### Timing invariant

All scheduling uses absolute sample times from engine start. Do not pass relative/"now + offset" times to `scheduleBuffer(at:)` — the look-ahead scheduler assumes step N always maps to frame `N * samplesPerStep`. Groove's swing/jitter is applied on top of that nominal time via `AudioEngine.groovedTime(forStep:)`, never by shifting the step index itself; `Clock`'s step→frame identity stays pure. If you change BPM at runtime you must also rethink `scheduledThroughStep` and the mapping in `Clock`, since the existing code does not re-quantize already-scheduled frames.
