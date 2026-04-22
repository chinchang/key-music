import Foundation
import SwiftUI

/// Translates raw key presses into musical events and tracks typing dynamics.
final class KeyMapper {
    enum Event {
        case pitched(midi: Int)
        case bass(midi: Int)
        case accent
        case kick
    }
    struct Out { let kind: Event }

    // C minor pentatonic across two octaves
    private let scale: [Int] = [60, 63, 65, 67, 70, 72, 75, 77, 79, 82]

    // Rolling window of recent keystroke timestamps
    private var times: [TimeInterval] = []
    private let window: TimeInterval = 2.0
    private let queue = DispatchQueue(label: "keymusic.mapper")

    /// 0...1 typing intensity, decays when idle.
    var intensity: Double {
        queue.sync {
            pruneLocked()
            // ~10 keys in 2s = full intensity
            let rate = Double(times.count) / window
            return min(1.0, rate / 5.0)
        }
    }

    private func pruneLocked() {
        let now = Date().timeIntervalSinceReferenceDate
        times.removeAll { now - $0 > window }
    }

    func process(_ press: KeyPress) -> Out? {
        return process(characters: press.characters)
    }

    func process(characters: String) -> Out? {
        let now = Date().timeIntervalSinceReferenceDate
        queue.sync {
            times.append(now)
            pruneLocked()
        }

        guard let ch = characters.first else { return nil }

        if ch == " " { return Out(kind: .kick) }
        if ch.isNewline { return Out(kind: .accent) }
        if ch.isPunctuation || ch.isSymbol { return Out(kind: .accent) }
        if ch.isNumber {
            let n = Int(String(ch)) ?? 0
            return Out(kind: .bass(midi: 36 + [0,2,3,5,7,8,10,12,14,15][n]))
        }
        if ch.isLetter {
            let v = Int(ch.lowercased().unicodeScalars.first!.value)
            let idx = (v - Int(("a" as Character).asciiValue!) + 1000) % scale.count
            return Out(kind: .pitched(midi: scale[idx]))
        }
        return nil
    }
}
