import AVFoundation
import Foundation

/// Tracks which layers are currently active and exposes a UI string.
final class Layers {
    enum Layer: String, CaseIterable { case drums, bass, arp, lead }

    private var active: Set<Layer> = [.drums]
    private let queue = DispatchQueue(label: "keymusic.layers")

    func setActive(_ layer: Layer, _ on: Bool) {
        queue.sync {
            if on { active.insert(layer) } else { active.remove(layer) }
        }
    }

    func isActive(_ layer: Layer) -> Bool {
        queue.sync { active.contains(layer) }
    }

    var activeDescription: String {
        queue.sync {
            Layer.allCases.filter { active.contains($0) }.map { $0.rawValue }.joined(separator: "+")
        }
    }
}
