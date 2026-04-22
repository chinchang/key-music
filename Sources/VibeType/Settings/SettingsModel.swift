import Foundation
import ServiceManagement

/// User-tunable settings backed by `UserDefaults`. Shared between the Settings UI and AudioEngine.
final class SettingsModel: ObservableObject {
    @Published var bpm: Double {
        didSet {
            let clamped = min(140, max(60, bpm))
            if clamped != bpm { bpm = clamped; return } // re-enter didSet with clamp, then persist
            UserDefaults.standard.set(bpm, forKey: Keys.bpm)
        }
    }

    @Published var masterVolume: Double {
        didSet {
            let clamped = min(1, max(0, masterVolume))
            if clamped != masterVolume { masterVolume = clamped; return }
            UserDefaults.standard.set(masterVolume, forKey: Keys.volume)
        }
    }

    @Published var openAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(openAtLogin, forKey: Keys.openAtLogin)
            applyOpenAtLogin(openAtLogin)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        self.bpm = defaults.object(forKey: Keys.bpm) as? Double ?? 96
        self.masterVolume = defaults.object(forKey: Keys.volume) as? Double ?? 0.85
        // Trust the OS as the ground truth for login-item state, then mirror to our stored flag.
        let storedFlag = defaults.object(forKey: Keys.openAtLogin) as? Bool ?? false
        self.openAtLogin = (SMAppService.mainApp.status == .enabled) ? true : storedFlag
    }

    private func applyOpenAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
        } catch {
            // Fails when the binary isn't launched from a proper .app bundle (e.g. `swift run`).
            // Not a crash; the toggle becomes inert until the installed DMG is used.
            print("[VibeType] open-at-login \(on ? "register" : "unregister") failed: \(error)")
        }
    }

    private enum Keys {
        static let bpm = "vibetype.bpm"
        static let volume = "vibetype.volume"
        static let openAtLogin = "vibetype.openAtLogin"
    }
}
