import SpriteKit
import UIKit

/// A single station on a chapter's vertical path.
///
/// The stop reads as a place rather than a list row: a chamfered plate carrying
/// the level's number and its stars, wrapped in a collar whose colour says where
/// the player stands with it. Locked stops sit dim behind a padlock, cleared
/// stops wear a brass collar, and the stop the player is up to pulses in freeze
/// blue with a marker pointing up at it.
///
/// It stays a `PressableNode` with the same `level-<id>` identifier the grid
/// used, so the coordinator's activation path is untouched.
final class LevelStopNode: PressableNode {

    enum State {
        case locked
        case cleared
        case current
    }

    /// The collar's size, which is what a stop's own footprint has to be
    /// measured by: it is wider than the plate and it is drawn outside it.
    static let collarSize = CGSize(width: 78, height: 78)
    /// How far a stop reaches from its centre, collar included. Scenes that
    /// park a stop against fixed furniture keep this much clear of it.
    static var clearanceRadius: CGFloat { max(collarSize.width, collarSize.height) / 2 }

    init(levelID: Int, indexInChapter: Int, progress: LevelProgress?, state: State) {
        super.init(
            identifier: "level-\(levelID)",
            title: "",
            size: CGSize(width: 62, height: 62),
            style: .secondary,
            showsRail: false
        )
        setEnabled(state != .locked)
        // The scene owns the gesture on this screen so it can tell a scroll from
        // a tap; the stop is activated through `activateFromContainer()`.
        isUserInteractionEnabled = false
        buildCollar(for: state)
        buildContents(indexInChapter: indexInChapter, progress: progress, state: state)
        accessibilityLabel = "Level \(indexInChapter)"
    }

    required init?(coder aDecoder: NSCoder) { nil }

    private func buildCollar(for state: State) {
        let color: UIColor
        switch state {
        case .locked: color = GameTheme.divider
        case .cleared: color = GameTheme.brassLight
        case .current: color = GameTheme.freezeBlue
        }
        // The collar is wider than the plate and hollow, so it reads as a ring
        // around the stop whether it is drawn under the plate or over it.
        let collar = SKShapeNode(path: GameTheme.chamferedPath(size: Self.collarSize, cut: 13))
        collar.fillColor = .clear
        collar.strokeColor = color.withAlphaComponent(state == .locked ? 0.34 : 0.88)
        collar.lineWidth = state == .current ? 2 : 1.2
        collar.glowWidth = state == .current ? 3 : 0
        addChild(collar)

        guard state == .current else { return }
        guard !SaveStore.shared.settings.reduceMotion else { return }
        let pulse = SKAction.sequence([
            .group([.scale(to: 1.09, duration: 0.95), .fadeAlpha(to: 0.36, duration: 0.95)]),
            .group([.scale(to: 1.0, duration: 0.95), .fadeAlpha(to: 1.0, duration: 0.95)])
        ])
        collar.run(.repeatForever(pulse))
    }

    private func buildContents(indexInChapter: Int, progress: LevelProgress?, state: State) {
        if state == .current {
            // Points up at the plate so the current stop stays legible even when
            // the pulse is switched off for reduced motion.
            let marker = SKShapeNode(path: Self.markerPath())
            marker.fillColor = GameTheme.freezeBlue
            marker.strokeColor = .clear
            marker.glowWidth = 1.5
            marker.position.y = -52
            addChild(marker)
        }

        let number = GameTheme.label(
            String(format: "%02d", indexInChapter),
            size: 18,
            color: state == .locked ? GameTheme.textSecondary : GameTheme.textPrimary,
            weight: .bold
        )
        number.position.y = state == .locked ? 7 : 10
        addChild(number)

        if state == .locked {
            if let lock = GameAssets.sprite(GameAssets.Icon.lock, fitting: CGSize(width: 15, height: 15)) {
                lock.position.y = -15
                lock.alpha = 0.75
                addChild(lock)
            }
            return
        }
        let row = StarRowNode(count: progress?.stars ?? 0, size: 10, spacing: 14)
        row.position.y = -15
        addChild(row)
    }

    /// A small upward chevron, drawn as a path so it needs no delivered art.
    private static func markerPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -7, y: -5))
        path.addLine(to: CGPoint(x: 7, y: -5))
        path.addLine(to: CGPoint(x: 0, y: 5))
        path.closeSubpath()
        return path
    }
}

/// The landmark a chapter's path climbs toward.
///
/// Deliberately not interactive — it is a place, not a button. It lights up once
/// every level in the chapter has been cleared, which is what gives the path its
/// sense of arrival.
final class ChapterDestinationNode: SKNode {

    init(chapter: Int, stars: Int, totalStars: Int, width: CGFloat) {
        super.init()
        let complete = stars >= totalStars
        let accent = complete ? GameTheme.brassLight : GameTheme.freezeBlue
        let panelWidth = min(228, width)

        // Added before the panel so tree order puts the halo behind it.
        let halo = SKShapeNode(path: GameTheme.chamferedPath(size: CGSize(width: panelWidth + 18, height: 96), cut: 18))
        halo.fillColor = .clear
        halo.strokeColor = accent.withAlphaComponent(complete ? 0.34 : 0.16)
        halo.lineWidth = complete ? 2 : 1
        halo.glowWidth = complete ? 4 : 0
        addChild(halo)

        let panel = GameTheme.roundedPanel(size: CGSize(width: panelWidth, height: 84))
        panel.strokeColor = accent.withAlphaComponent(0.55)
        addChild(panel)

        if let badge = GameAssets.sprite(GameAssets.ChapterArt.badge(chapter), fitting: CGSize(width: 46, height: 46)) {
            badge.position = CGPoint(x: -panelWidth / 2 + 36, y: 0)
            if !complete {
                badge.color = .black
                badge.colorBlendFactor = 0.35
            }
            addChild(badge)
        }

        let caption = GameTheme.label("DESTINATION", size: 9, color: accent, weight: .bold, alignment: .left)
        caption.position = CGPoint(x: -panelWidth / 2 + 68, y: 20)
        addChild(caption)

        let title = GameTheme.label(
            GameText.chapterNames[max(0, min(9, chapter - 1))],
            size: 13,
            color: GameTheme.textPrimary,
            weight: .bold,
            alignment: .left
        )
        title.position = CGPoint(x: -panelWidth / 2 + 68, y: -1)
        addChild(title)

        let status = GameTheme.label(
            complete ? "CHAPTER COMPLETE" : "\(stars) / \(totalStars) STARS",
            size: 9,
            color: complete ? GameTheme.jade : GameTheme.textSecondary,
            weight: .medium,
            alignment: .left
        )
        status.position = CGPoint(x: -panelWidth / 2 + 68, y: -21)
        addChild(status)
    }

    required init?(coder aDecoder: NSCoder) { nil }
}

/// Draws the road between the stops.
///
/// Each span is a dark bed with a thinner travelled overlay, so progress up the
/// chapter is readable from the colour of the road itself rather than only from
/// the state of the plates. Cross ties every quarter span are what make it read
/// as a route instead of a connector line.
///
/// The scene runs with `ignoresSiblingOrder`, which sorts the whole tree by
/// `zPosition`, so nothing here uses a negative one: the bed, the overlay and
/// the ties are added in that order and rely on tree order within a single
/// depth. A negative value would drop the road behind the scene's own backdrop.
enum PathTrail {

    /// - Parameter clearedIndices: 1-based chapter indices of finished levels. A
    ///   span counts as travelled once the stop below it is cleared, which also
    ///   makes the final span to the destination depend on the last level.
    static func build(points: [CGPoint], clearedIndices: Set<Int>, stopCount: Int) -> SKNode {
        let container = SKNode()
        guard points.count >= 2 else { return container }

        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let travelled = clearedIndices.contains(min(index + 1, stopCount))
            let accent = travelled ? GameTheme.brassLight : GameTheme.divider

            let path = CGMutablePath()
            path.move(to: start)
            path.addLine(to: end)

            let bed = SKShapeNode(path: path)
            bed.strokeColor = GameTheme.background.withAlphaComponent(0.92)
            bed.lineWidth = 15
            bed.lineCap = .round
            container.addChild(bed)

            let overlay = SKShapeNode(path: path)
            overlay.strokeColor = accent.withAlphaComponent(travelled ? 0.78 : 0.42)
            overlay.lineWidth = travelled ? 4.5 : 3
            overlay.lineCap = .round
            overlay.glowWidth = travelled ? 1.2 : 0
            container.addChild(overlay)

            let angle = atan2(end.y - start.y, end.x - start.x)
            for fraction in [0.25, 0.5, 0.75] {
                let tie = SKShapeNode(rectOf: CGSize(width: 2, height: 12), cornerRadius: 1)
                tie.fillColor = accent.withAlphaComponent(travelled ? 0.55 : 0.28)
                tie.strokeColor = .clear
                tie.position = start.lerped(to: end, t: CGFloat(fraction))
                tie.zRotation = angle + .pi / 2
                container.addChild(tie)
            }
        }
        return container
    }
}
