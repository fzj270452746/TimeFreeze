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

    /// A denser freeze burst for the instant world time stops: the expanding
    /// wave plus a short halo and a scatter of sparks. Kept alongside
    /// `emitFreezeWave` rather than replacing it, so the quieter effect can
    /// still be used where a full burst would be noise.
    func emitFreezeBurst(at position: CGPoint, maximumRadius: CGFloat) {
        guard let container else { return }
        emitFreezeWave(at: position, maximumRadius: maximumRadius)
        guard !SaveStore.shared.settings.reduceMotion else { return }

        let halo = SKShapeNode(circleOfRadius: 12)
        halo.name = Self.waveName
        halo.position = position
        halo.fillColor = GameTheme.freezeBlue.withAlphaComponent(0.20)
        halo.strokeColor = GameTheme.freezeWhite
        halo.lineWidth = 2
        halo.glowWidth = 8
        halo.zPosition = 119
        container.addChild(halo)
        halo.run(.sequence([
            .group([.scale(to: maximumRadius / 12, duration: 0.22), .fadeOut(withDuration: 0.22)]),
            .removeFromParent()
        ]))

        for index in 0..<10 {
            let angle = CGFloat(index) * .pi * 2 / 10
            let spark = SKShapeNode(circleOfRadius: 2.4)
            spark.name = Self.waveName
            spark.position = position
            spark.fillColor = index % 3 == 0 ? GameTheme.freezeWhite : GameTheme.freezeBlue
            spark.strokeColor = .clear
            spark.glowWidth = 2
            spark.zPosition = 121
            container.addChild(spark)
            let distance = maximumRadius * (0.16 + CGFloat(index % 4) * 0.07)
            spark.run(.sequence([
                .group([
                    .move(
                        to: CGPoint(x: position.x + cos(angle) * distance, y: position.y + sin(angle) * distance),
                        duration: 0.30
                    ),
                    .fadeOut(withDuration: 0.30)
                ]),
                .removeFromParent()
            ]))
        }
    }

    /// Cancels any shockwave still in flight so a reset or teardown never leaves
    /// a ring stranded on the board.
    func clear() {
        container?.children
            .filter { $0.name == Self.waveName }
            .forEach { $0.removeAllActions(); $0.removeFromParent() }
    }
}
