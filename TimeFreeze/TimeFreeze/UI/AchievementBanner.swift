import SpriteKit
import UIKit

/// The card that drops in under the safe area when a mark is earned.
///
/// Purely a display layer. Nothing in here turns on `isUserInteractionEnabled`,
/// so a card never stops the player tapping what is underneath it and nothing
/// has to be threaded into `GameScene`'s touch handling for it to behave.
///
/// One card plays at a time and the rest wait in `queue`; each card's cycle ends
/// by asking for the next. Every step is an `SKAction` bound to this node, so a
/// scene that goes away mid-batch takes the pending cards with it — there is no
/// timer to cancel and no closure holding a dead scene alive.
///
/// Deliberately silent. The moment a board is cleared already plays
/// `bgm_level_success`, `sfx_success` and a success haptic; the card is part of
/// that same beat, not a fourth thing on top of it. It also keeps the card off
/// the one stinger slot `AudioService` has, which `playTag` stops before every
/// use — a card that chimed would cut the level's own fanfare short.
final class AchievementBannerNode: SKNode {

    private enum Layout {
        static let width: CGFloat = 348
        static let height: CGFloat = 62
        /// How far below `safeTop` the card comes to rest.
        static let topInset: CGFloat = 14
        /// Breathing room between the card and the result panel under it.
        static let panelGap: CGFloat = 10
        static let slideIn: TimeInterval = 0.26
        /// Long enough to read a title and a one-line detail, short enough that
        /// a board earning several marks does not turn the result screen into a
        /// slideshow.
        static let hold: TimeInterval = 1.8
        static let slideOut: TimeInterval = 0.2
        static let fade: TimeInterval = 0.16
        /// Cards played for one batch. A chapter's closing board can trip four
        /// or five marks at once, and playing every one of them would outlast
        /// the panel they belong to. Whatever is left over is folded into a
        /// single closing card that points at the list.
        static let maximumCards = 3
    }

    private static let moreMarksTitle = "MORE MARKS"

    private let card = SKNode()
    private let panel = SKShapeNode()
    private let titleLabel = GameTheme.label("", size: 12.5, weight: .bold, alignment: .left)
    private let detailLabel = GameTheme.label("", size: 9, color: GameTheme.textSecondary, weight: .regular, alignment: .left)
    private let countLabel = GameTheme.label("", size: 10, color: GameTheme.brassLight, weight: .bold, alignment: .right)

    /// Marks still waiting for their turn.
    private var queue: [AchievementDefinition] = []
    /// Marks cut from the batch by `Layout.maximumCards`, shown as one closing
    /// card rather than dropped without a word.
    private var overflow = 0
    /// The count stated on the card. Read when a card is presented rather than
    /// when it is queued, so every card in a batch states the same total — none
    /// of them can know which of its siblings the player counts first.
    private var marks = 0
    private var total = 0
    private var isShowing = false

    /// Where the card sits while it is on screen, and where it hides when it is
    /// not. Both come from the safe area, so `layout` recomputes them.
    private var restY: CGFloat = 0
    private var hiddenY: CGFloat = 0

    init(sceneSize: CGSize) {
        super.init()
        // Above `ResultPanel` (1_100) so a mark earned by the run that just ended
        // is read over the panel rather than behind it. The view runs with
        // `ignoresSiblingOrder`, so this is an absolute rank in the whole tree,
        // not one among siblings.
        zPosition = 1_200
        build(width: min(Layout.width, sceneSize.width - 32))
        // Invisible until something is earned. The card is nearly as wide as the
        // screen, so without this an empty frame would sit there all level.
        card.alpha = 0
        addChild(card)
    }

    required init?(coder aDecoder: NSCoder) { nil }

    // MARK: - Building

    private func build(width: CGFloat) {
        panel.path = GameTheme.chamferedPath(size: CGSize(width: width, height: Layout.height), cut: 8)
        panel.fillColor = GameTheme.board
        panel.strokeColor = GameTheme.divider
        panel.lineWidth = 1.2
        card.addChild(panel)

        // The delivered tick carries the two-tone line art, so it is left
        // untinted; the drawn fallback marks the same spot when it is missing.
        if let tick = GameAssets.sprite(GameAssets.Icon.check, fitting: CGSize(width: 20, height: 20)) {
            tick.position = CGPoint(x: -width / 2 + 27, y: 0)
            card.addChild(tick)
        } else {
            let glyph = GameTheme.label("\u{2713}", size: 18, color: GameTheme.jade, weight: .bold)
            glyph.position = CGPoint(x: -width / 2 + 27, y: 0)
            card.addChild(glyph)
        }

        titleLabel.position = CGPoint(x: -width / 2 + 50, y: 9)
        card.addChild(titleLabel)
        detailLabel.position = CGPoint(x: -width / 2 + 50, y: -11)
        card.addChild(detailLabel)
        countLabel.position = CGPoint(x: width / 2 - 16, y: 0)
        card.addChild(countLabel)
    }

    /// Re-seats the card against the current safe area. Called from
    /// `GameScene.layoutGeometry`, which runs again when the insets arrive, so
    /// the card is never left resting under the notch.
    func layout(in scene: SKScene) {
        // The result panel is centred and fixed in height, so its top edge sits
        // at a constant. On a 568pt screen the safe area alone cannot clear it,
        // and the card is pushed down to the panel's edge instead — tight, but
        // never on top of the panel's title.
        let panelTop = max(ResultPanel.successHeight, ResultPanel.failureHeight) / 2
        restY = max(
            scene.safeTop - Layout.topInset - Layout.height / 2,
            panelTop + Layout.height / 2 + Layout.panelGap
        )
        hiddenY = scene.size.height / 2 + Layout.height / 2 + 2
        guard !isShowing else { return }
        card.removeAllActions()
        card.position = CGPoint(x: 0, y: hiddenY)
    }

    // MARK: - Playing

    func enqueue(_ definitions: [AchievementDefinition], marks: Int, total: Int) {
        guard !definitions.isEmpty else { return }
        self.marks = marks
        self.total = total
        guard !isShowing else {
            // A second batch while one is playing cannot come out of
            // `levelDidComplete` — a level ends once per scene — so it is queued
            // whole rather than re-trimmed against a batch already counted.
            queue.append(contentsOf: definitions)
            return
        }
        overflow = max(0, definitions.count - Layout.maximumCards)
        queue = overflow > 0 ? Array(definitions.prefix(Layout.maximumCards)) : definitions
        presentNext()
    }

    private func presentNext() {
        let definition: AchievementDefinition?
        if !queue.isEmpty {
            definition = queue.removeFirst()
        } else if overflow > 0 {
            definition = nil
        } else {
            isShowing = false
            return
        }
        isShowing = true

        if let definition {
            // Hidden marks are named in full once earned. The `???` the catalogue
            // uses stands for a condition the player has not met yet; withholding
            // the name of a mark they have just been awarded would only read as a
            // bug.
            titleLabel.text = definition.title
            detailLabel.text = definition.detail
            card.accessibilityLabel =
                "\(definition.title). \(definition.detail). \(marks) of \(total) marks"
        } else {
            let folded = overflow
            overflow = 0
            titleLabel.text = "\(folded) \(Self.moreMarksTitle)"
            detailLabel.text = GameText.moreMarksDetail
            card.accessibilityLabel =
                "\(folded) more marks. \(GameText.moreMarksDetail). \(marks) of \(total) marks"
        }
        countLabel.text = "\(marks) / \(total) \(LeaderboardBoard.achievements.metric)"

        card.removeAllActions()
        if SaveStore.shared.settings.reduceMotion {
            card.position = CGPoint(x: 0, y: restY)
            card.alpha = 0
            card.run(.sequence([
                .fadeIn(withDuration: Layout.fade),
                .wait(forDuration: Layout.hold),
                .fadeOut(withDuration: Layout.fade),
                .run { [weak self] in self?.presentNext() }
            ]))
        } else {
            card.position = CGPoint(x: 0, y: hiddenY)
            card.alpha = 1
            card.run(.sequence([
                .moveTo(y: restY, duration: Layout.slideIn),
                .wait(forDuration: Layout.hold),
                .moveTo(y: hiddenY, duration: Layout.slideOut),
                .run { [weak self] in self?.presentNext() }
            ]))
        }
    }
}
