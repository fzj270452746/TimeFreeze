import SpriteKit
import UIKit

/// Visual feedback for the time system.
///
/// Only the freeze shockwave survives: one expanding ring that marks the exact
/// moment world time stops. The pooled dot particles that used to accompany it
/// were removed — they rendered at roughly 8–14 px, so they read as noise
/// rather than light and cost a 64-node pool to maintain.
final class GameEffects {
    weak var container: SKNode?

    private static let waveName = "timeFreezeWave"

    init(container: SKNode? = nil) {
        self.container = container
    }

    func emitFreezeWave(at position: CGPoint, maximumRadius: CGFloat) {
        guard let container else { return }
        let wave = SKShapeNode(circleOfRadius: 8)
        wave.name = Self.waveName
        wave.position = position
        wave.strokeColor = GameTheme.freezeWhite
        wave.fillColor = GameTheme.freezeBlue.withAlphaComponent(0.06)
        wave.lineWidth = 3
        wave.glowWidth = 7
        wave.zPosition = 120
        container.addChild(wave)
        let duration = SaveStore.shared.settings.reduceMotion ? 0.08 : 0.32
        wave.run(.sequence([
            .group([.scale(to: maximumRadius / 8, duration: duration), .fadeOut(withDuration: duration)]),
            .removeFromParent()
        ]))
    }

    /// Cancels any shockwave still in flight so a reset or teardown never leaves
    /// a ring stranded on the board.
    func clear() {
        container?.children
            .filter { $0.name == Self.waveName }
            .forEach { $0.removeAllActions(); $0.removeFromParent() }
    }
}
