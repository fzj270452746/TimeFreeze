import SpriteKit
import UIKit

/// A gallery of tile skins. Each row shows a sample tile, its name, and its
/// state — equipped, ready to equip, or locked behind a star count. Equipping
/// writes to `GameSettings`, so every tile in the game restyles immediately.
final class SkinsScene: BaseScene {

    fileprivate enum Layout {
        static let rowHeight: CGFloat = 72
        static let rowGap: CGFloat = 12
    }

    private let listWorld = SKNode()

    private var rows: [SkinRowNode] = []
    private var scrollOffset: CGFloat = 0
    private var scrollMinY: CGFloat = 0
    private var scrollMaxY: CGFloat = 0
    private var dragStartY: CGFloat = 0
    private var dragLastY: CGFloat = 0
    private var isScrollGesture = false
    private var pressedRow: SkinRowNode?
    private var isBuilt = false

    private var rowPitch: CGFloat { Layout.rowHeight + Layout.rowGap }
    private var listWidth: CGFloat { min(348, size.width - 32) }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        addChild(listWorld)
        addHeader(title: GameText.skins, subtitle: GameText.skinsSubtitle)
        buildRows()
        isBuilt = true
        transitionIn()
    }

    override func layoutDidChange() {
        guard isBuilt else { return }
        buildRows()
    }

    private func buildRows() {
        pressedRow = nil
        rows.removeAll()
        listWorld.removeAllChildren()
        let totalStars = SaveStore.shared.progress.totalStars
        let equipped = SaveStore.shared.settings.tileSkin
        // The first row clears the header's lowest edge by a small gutter. Unlike
        // the settings list the rows here are 72pt tall, so the 26pt inset that
        // works for its 53pt toggles would let the row's top overrun the subtitle.
        var y = headerBottomY - Layout.rowHeight / 2 - 10
        for skin in TileSkin.allCases {
            let row = SkinRowNode(
                skin: skin,
                equipped: skin == equipped,
                totalStars: totalStars,
                width: listWidth
            )
            row.position = CGPoint(x: 0, y: y)
            listWorld.addChild(row)
            rows.append(row)
            y -= rowPitch
        }
        // Mirrors `SettingsScene`: the scroll range is the gap between the fixed
        // band's bottom and where the last row left off, so six rows that fit
        // simply cannot scroll.
        let contentBottom = y
        let bandBottom = safeBottom + 14
        scrollMaxY = max(0, bandBottom - contentBottom)
        scrollOffset = ScalarMath.clamp(scrollOffset, scrollMinY, scrollMaxY)
        applyScroll()
    }

    private func applyScroll() {
        scrollOffset = ScalarMath.clamp(scrollOffset, scrollMinY, scrollMaxY)
        listWorld.position = CGPoint(x: 0, y: scrollOffset)
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let local = touch.location(in: listWorld)
        pressedRow = rows.first { $0.containsScenePoint(local) }
        pressedRow?.beginPress()
        dragStartY = point.y
        dragLastY = dragStartY
        isScrollGesture = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let y = touch.location(in: self).y
        let delta = y - dragLastY
        if !isScrollGesture, abs(y - dragStartY) > 9 {
            isScrollGesture = true
            pressedRow?.cancelPress()
            pressedRow = nil
        }
        guard isScrollGesture else { return }
        scrollOffset += delta
        applyScroll()
        dragLastY = y
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let pressed = pressedRow
        let wasScroll = isScrollGesture
        pressedRow = nil
        isScrollGesture = false
        pressed?.cancelPress()
        guard !wasScroll, let pressed else { return }
        equip(pressed.skin)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        pressedRow?.cancelPress()
        pressedRow = nil
        isScrollGesture = false
    }

    // MARK: - Equip

    private func equip(_ skin: TileSkin) {
        guard skin.isUnlocked(given: SaveStore.shared.progress.totalStars) else {
            HapticService.shared.play(.warning)
            return
        }
        SaveStore.shared.updateSettings { $0.tileSkin = skin }
        HapticService.shared.play(.success)
        AudioService.shared.play(.switchOn)
        buildRows()
    }
}

/// One skin row: a sample tile, the skin's name, and its state.
private final class SkinRowNode: SKNode {
    let skin: TileSkin
    private let panel: SKShapeNode
    private let unlocked: Bool

    init(skin: TileSkin, equipped: Bool, totalStars: Int, width: CGFloat) {
        self.skin = skin
        unlocked = skin.isUnlocked(given: totalStars)
        panel = GameTheme.roundedPanel(
            size: CGSize(width: width, height: SkinsScene.Layout.rowHeight),
            fill: equipped ? GameTheme.board : GameTheme.panel
        )
        super.init()
        if equipped {
            panel.strokeColor = skin.accent.withAlphaComponent(0.7)
        }
        addChild(panel)
        alpha = unlocked ? 1 : 0.5

        let tile = MahjongTileRenderer.makeFaceNode(
            suit: .dots,
            face: .five,
            team: .ivory,
            size: CGSize(width: 42, height: 56),
            skin: skin
        )
        tile.position = CGPoint(x: -width / 2 + 42, y: -2)
        panel.addChild(tile)

        let title = GameTheme.label(
            skin.title,
            size: 13,
            color: unlocked ? GameTheme.textPrimary : GameTheme.textSecondary,
            weight: .bold,
            alignment: .left
        )
        title.position = CGPoint(x: -width / 2 + 80, y: 8)
        panel.addChild(title)

        let status = Self.statusText(skin: skin, equipped: equipped, unlocked: unlocked)
        let statusLabel = GameTheme.label(status.0, size: 9, color: status.1, weight: .bold, alignment: .left)
        statusLabel.position = CGPoint(x: -width / 2 + 80, y: -11)
        panel.addChild(statusLabel)

        if equipped {
            let mark = Self.checkmark()
            mark.position = CGPoint(x: width / 2 - 26, y: 0)
            panel.addChild(mark)
        } else if !unlocked {
            let lock = Self.lockMark()
            lock.position = CGPoint(x: width / 2 - 26, y: 0)
            panel.addChild(lock)
        }

        accessibilityLabel = "\(skin.title) skin, \(status.0)"
    }

    required init?(coder aDecoder: NSCoder) { nil }

    private static func statusText(skin: TileSkin, equipped: Bool, unlocked: Bool) -> (String, UIColor) {
        if equipped { return (GameText.equipped, skin.accent) }
        if unlocked { return (GameText.tapToEquip, GameTheme.textSecondary) }
        return ("\(GameText.locked) · \(skin.starRequirement) STARS", GameTheme.textSecondary)
    }

    private static func checkmark() -> SKNode {
        if let check = GameAssets.sprite(GameAssets.Icon.check, fitting: CGSize(width: 20, height: 20)) {
            return check
        }
        return GameTheme.label("\u{2713}", size: 18, color: GameTheme.jade, weight: .bold)
    }

    private static func lockMark() -> SKNode {
        if let lock = GameAssets.sprite(GameAssets.Icon.lock, fitting: CGSize(width: 15, height: 15)) {
            lock.alpha = 0.6
            return lock
        }
        return GameTheme.label("\u{1F512}", size: 13, color: GameTheme.textSecondary)
    }

    func containsScenePoint(_ point: CGPoint) -> Bool {
        calculateAccumulatedFrame().insetBy(dx: -4, dy: -4).contains(point)
    }

    func beginPress() {
        guard !SaveStore.shared.settings.reduceMotion else { return }
        run(.scale(to: 0.97, duration: 0.06))
    }

    func cancelPress() {
        removeAllActions()
        setScale(1)
    }
}
