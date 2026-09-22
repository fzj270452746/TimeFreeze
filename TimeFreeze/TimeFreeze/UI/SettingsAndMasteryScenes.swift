import QuartzCore
import SpriteKit
import UIKit

final class SettingsScene: BaseScene {

    private enum Layout {
        static let rowHeight: CGFloat = 53
        static let controlGap: CGFloat = 10
    }

    private var resetButton: PressableNode?
    private var deleteButton: PressableNode?

    /// How long one of the two destructive controls has to be held down before
    /// it commits. Matches the `HOLD TO ...` copy on the control itself.
    private static let holdDuration: TimeInterval = 1.2

    /// The press currently down on a destructive control, if any.
    private var hold: Hold?

    /// A press on a control that confirms by being held rather than tapped.
    ///
    /// The press has to survive from `touchesBegan` until either the timer in
    /// `update` commits it or the finger comes up and cancels it, which is why
    /// the target and its start time travel together: a press that has already
    /// fired must not be read as an ordinary tap when the finger finally lifts.
    private struct Hold {
        let target: PressableNode
        let start: TimeInterval
        var didFire = false
    }

    /// The resting and the held title for a control, or nil when the identifier
    /// does not belong to a hold-to-confirm control.
    private static func holdTitles(for identifier: String) -> (resting: String, holding: String)? {
        switch identifier {
        case "reset": return (GameText.resetProgress, GameText.confirmReset)
        case "deleteCloud": return (GameText.deleteCloudData, GameText.confirmDeleteCloud)
        default: return nil
        }
    }

    /// The list scrolls, because the toggles, the volume row and the two
    /// destructive controls together are taller than a short phone. It is only
    /// scrollable when it needs to be: `scrollMaxY` stays zero on a tall screen.
    private let listWorld = SKNode()
    private var toggles: [ToggleNode] = []
    private var volumeButtons: [PressableNode] = []
    private var scrollOffset: CGFloat = 0
    private var scrollMinY: CGFloat = 0
    private var scrollMaxY: CGFloat = 0
    private var dragStartY: CGFloat = 0
    private var dragLastY: CGFloat = 0
    private var dragLastTimestamp: TimeInterval = 0
    private var dragVelocity: CGFloat = 0
    private var isScrollGesture = false
    private var pressedToggle: ToggleNode?
    private var pressedButton: PressableNode?
    /// Set once the list exists, so a resize can tell "not built yet" from the
    /// size it was built at. Testing the header's edge for a non-zero value
    /// would do the same job only by accident.
    private var isBuilt = false

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        addChild(listWorld)
        addHeader(title: GameText.settings, subtitle: "PLAY YOUR WAY")
        buildSettings()
        isBuilt = true
        transitionIn()
    }

    override func layoutDidChange() {
        guard isBuilt else { return }
        listWorld.removeAllChildren()
        toggles.removeAll()
        volumeButtons.removeAll()
        // The controls that were mid-press no longer exist, so any hold in
        // progress has to be dropped with them.
        pressedToggle = nil
        pressedButton = nil
        hold = nil
        buildSettings()
    }

    private func buildSettings() {
        // Rebuilt from scratch, so the references are cleared first: leaving a
        // stale one behind would have `performCloudDeletion` driving a node that
        // is no longer in the tree.
        resetButton = nil
        deleteButton = nil
        let settings = SaveStore.shared.settings
        let definitions: [(String, String, Bool, (Bool) -> Void)] = [
            ("sound", GameText.sound, settings.soundEnabled, { value in
                SaveStore.shared.updateSettings { $0.soundEnabled = value }
                if value { AudioService.shared.play(.switchOn) }
            }),
            ("ambient", GameText.music, settings.ambientEnabled, { value in
                SaveStore.shared.updateSettings { $0.ambientEnabled = value }
                AudioService.shared.setAmbientEnabled(value)
            }),
            ("haptics", GameText.haptics, settings.hapticsEnabled, { value in
                SaveStore.shared.updateSettings { $0.hapticsEnabled = value }
                if value { HapticService.shared.play(.mechanism) }
            }),
            ("motion", GameText.reduceMotion, settings.reduceMotion, { value in
                SaveStore.shared.updateSettings { $0.reduceMotion = value }
            }),
            ("contrast", GameText.highContrast, settings.highContrast, { value in
                SaveStore.shared.updateSettings { $0.highContrast = value }
            }),
            ("tutorial", GameText.tutorial, settings.tutorialHints, { value in
                SaveStore.shared.updateSettings { $0.tutorialHints = value }
            }),
            ("leftHand", "LEFT-HANDED CONTROLS", settings.leftHandedControls, { value in
                SaveStore.shared.updateSettings { $0.leftHandedControls = value }
            })
        ]
        let width = min(338, size.width - 42)
        var y = headerBottomY - 26
        for (index, definition) in definitions.enumerated() {
            let toggle = ToggleNode(identifier: definition.0, title: definition.1, isOn: definition.2, width: width)
            toggle.position = CGPoint(x: 0, y: y)
            toggle.valueChanged = definition.3
            // The scene owns the gesture so a drag can become a scroll, exactly
            // as `LevelSelectScene` does for its stops.
            toggle.isUserInteractionEnabled = false
            listWorld.addChild(toggle)
            toggles.append(toggle)
            if index < definitions.count - 1 {
                let line = SKShapeNode(rectOf: CGSize(width: width, height: 1))
                line.fillColor = GameTheme.divider
                line.strokeColor = .clear
                line.position = CGPoint(x: 0, y: y - Layout.rowHeight / 2)
                listWorld.addChild(line)
            }
            y -= Layout.rowHeight
        }
        y -= Layout.controlGap
        buildVolumeSlider(y: y, width: width)
        y -= 52

        let reset = PressableNode(
            identifier: "reset",
            title: GameText.resetProgress,
            icon: "\u{21BB}",
            size: CGSize(width: width, height: 48),
            style: .danger
        )
        reset.position = CGPoint(x: 0, y: y)
        reset.delegate = self
        reset.isUserInteractionEnabled = false
        listWorld.addChild(reset)
        resetButton = reset
        y -= 48 + Layout.controlGap

        if let button = buildDeleteCloudButton(y: y, width: width) {
            y = button - 34
        }

        // Content is laid out top-down from the header, so the list's own origin
        // is the top of the band it may scroll inside.
        let contentBottom = y
        let bandBottom = safeBottom + 14
        scrollMaxY = max(0, bandBottom - contentBottom)
        scrollOffset = ScalarMath.clamp(scrollOffset, scrollMinY, scrollMaxY)
        applyScroll()
    }

    /// Adds the delete control and returns the y of its detail text, so the
    /// caller can account for the space it consumed.
    private func buildDeleteCloudButton(y: CGFloat, width: CGFloat) -> CGFloat? {
        guard SyncEngine.shared.isEnabled else { return nil }
        let button = PressableNode(
            identifier: "deleteCloud",
            title: GameText.deleteCloudData,
            size: CGSize(width: width, height: 44),
            style: .quiet,
            showsRail: false
        )
        button.position = CGPoint(x: 0, y: y)
        button.delegate = self
        button.isUserInteractionEnabled = false
        listWorld.addChild(button)
        deleteButton = button
        let detail = GameTheme.label(GameText.deleteCloudDetail, size: 9, color: GameTheme.textSecondary, weight: .regular)
        detail.numberOfLines = 0
        detail.preferredMaxLayoutWidth = width - 12
        detail.position = CGPoint(x: 0, y: y - 34)
        listWorld.addChild(detail)
        return y - 34
    }

    private func buildVolumeSlider(y: CGFloat, width: CGFloat) {
        let label = GameTheme.label("VOLUME", size: 13, weight: .medium, alignment: .left)
        label.position = CGPoint(x: -width / 2, y: y)
        listWorld.addChild(label)
        let values = ["25", "50", "75", "100"]
        let current = SaveStore.shared.settings.audioVolume
        for (index, value) in values.enumerated() {
            let isSelected = abs(current - CGFloat(index + 1) * 0.25) < 0.13
            let button = PressableNode(identifier: "volume-\(value)", title: value, size: CGSize(width: 48, height: 44), style: isSelected ? .primary : .quiet)
            button.position = CGPoint(x: -60 + CGFloat(index) * 56, y: y)
            button.delegate = self
            button.isUserInteractionEnabled = false
            listWorld.addChild(button)
            volumeButtons.append(button)
        }
    }

    private func applyScroll() {
        scrollOffset = ScalarMath.clamp(scrollOffset, scrollMinY, scrollMaxY)
        listWorld.position = CGPoint(x: 0, y: scrollOffset)
    }

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        guard let hold, !hold.didFire else { return }
        // Timed off the wall clock rather than the frame clock: `currentTime`
        // counts from the scene's first frame, so a press registered on the
        // opening frames would be measured against a baseline still near zero
        // and the hold would commit the instant it began.
        guard CACurrentMediaTime() - hold.start >= Self.holdDuration else { return }
        self.hold?.didFire = true
        commitHold(hold.target)
    }

    // MARK: - Holds

    /// Starts tracking a press, when it landed on one of the destructive controls.
    private func beginHold(for node: PressableNode?) {
        guard let node, let titles = Self.holdTitles(for: node.identifier) else { return }
        hold = Hold(target: node, start: CACurrentMediaTime())
        node.setTitle(titles.holding)
    }

    /// Drops the press without committing it, returning the control to its
    /// resting title. A press that already fired keeps the result it produced.
    private func cancelHold() {
        guard let hold else { return }
        self.hold = nil
        if !hold.didFire, let titles = Self.holdTitles(for: hold.target.identifier) {
            hold.target.setTitle(titles.resting)
        }
        hold.target.cancelPress()
    }

    private func commitHold(_ target: PressableNode) {
        // The pressed look goes now rather than on release: the finger is still
        // down, and lifting it must not be read as a second activation.
        target.cancelPress()
        switch target.identifier {
        case "reset": performReset()
        case "deleteCloud": performCloudDeletion()
        default: break
        }
    }

    private func performReset() {
        SaveStore.shared.resetProgress()
        // Keeps the player's identity but clears their leaderboard entry, so a
        // reset does not leave stale totals standing on the board.
        SyncEngine.shared.reportReset()
        resetButton?.setTitle(GameText.resetDone)
        HapticService.shared.play(.success)
        AudioService.shared.play(.success)
        run(.sequence([.wait(forDuration: 1), .run { [weak self] in
            self?.resetButton?.setTitle(GameText.resetProgress)
        }]))
    }

    private func performCloudDeletion() {
        deleteButton?.setEnabled(false)
        deleteButton?.setTitle(GameText.deleteCloudDone)
        HapticService.shared.play(.success)
        AudioService.shared.play(.success)
        // The button keeps its confirmation title and stays disabled. The
        // identity is gone, so there is nothing left on the service belonging to
        // this device to delete, and restoring "DELETE CLOUD DATA" made a spent
        // control read as one that could be pressed again.
        Task {
            await SyncEngine.shared.deleteCloudData()
        }
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        // Hit tests run in `listWorld`'s space: a child's frame is expressed in
        // its parent's coordinates, and the parent is the scrolling layer, so
        // scene coordinates would be off by the scroll.
        let local = touch.location(in: listWorld)
        pressedToggle = toggles.first { $0.containsScenePoint(local) }
        pressedToggle?.beginPressFromContainer()
        if pressedToggle == nil {
            pressedButton = listWorld.children
                .compactMap { $0 as? PressableNode }
                .first { $0.containsScenePoint(local) }
            pressedButton?.beginPressFromContainer()
            beginHold(for: pressedButton)
        }
        dragStartY = point.y
        dragLastY = dragStartY
        dragLastTimestamp = touch.timestamp
        dragVelocity = 0
        isScrollGesture = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let y = touch.location(in: self).y
        let delta = y - dragLastY
        if !isScrollGesture, abs(y - dragStartY) > 9 {
            isScrollGesture = true
            // Hand the gesture to the scroll and take the press back off
            // whatever control is under the finger.
            cancelHold()
            pressedToggle?.cancelPress()
            pressedToggle = nil
            pressedButton?.cancelPress()
            pressedButton = nil
        }
        guard isScrollGesture else { return }
        let elapsed = max(1.0 / 240.0, touch.timestamp - dragLastTimestamp)
        dragVelocity = delta / CGFloat(elapsed)
        scrollOffset += delta
        applyScroll()
        dragLastY = y
        dragLastTimestamp = touch.timestamp
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let toggle = pressedToggle
        let button = pressedButton
        let wasScroll = isScrollGesture
        pressedToggle = nil
        pressedButton = nil
        isScrollGesture = false
        guard !wasScroll else { return }
        if let toggle {
            toggle.activateFromContainer()
        } else if hold != nil {
            // A hold-to-confirm press commits from `update` while the finger is
            // still down, so releasing either cancels it or simply ends a press
            // that has already fired. Neither is a tap, so neither should play
            // the tap feedback `activateFromContainer` would.
            cancelHold()
        } else {
            button?.activateFromContainer()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelHold()
        pressedToggle?.cancelPress()
        pressedToggle = nil
        pressedButton?.cancelPress()
        pressedButton = nil
        isScrollGesture = false
    }

    // MARK: - Actions

    override func pressableNodeDidActivate(_ node: PressableNode) {
        // "reset" and "deleteCloud" are absent here on purpose: they confirm by
        // being held, and the hold is driven from `touchesBegan` and `update`
        // rather than from an activation.
        if node.identifier.hasPrefix("volume-"), let value = Int(node.identifier.dropFirst(7)) {
            SaveStore.shared.updateSettings { $0.audioVolume = CGFloat(value) / 100 }
            AudioService.shared.setVolume(CGFloat(value) / 100)
            AudioService.shared.play(.switchOn)
            // Restyled in place rather than by rebuilding the scene, which would
            // throw away the scroll position the player may have just set.
            for button in volumeButtons {
                button.setStyle(button === node ? .primary : .quiet)
            }
        } else {
            super.pressableNodeDidActivate(node)
        }
    }
}

final class MasteryScene: BaseScene {
    /// The overview panel. It is positioned from `safeTop`, so unlike the
    /// scrolling catalogue below it cannot simply be left where the old size put
    /// it, and is rebuilt whenever the scene's size changes.
    private let content = SKNode()
    /// The catalogue scrolls inside a crop node. Without it the rows would draw
    /// over the header and the overview panel as they pass beneath them, which
    /// SpriteKit does not clip on its own.
    private let listCrop = SKCropNode()
    private let listMask = SKShapeNode()
    private let listWorld = SKNode()
    /// The button under the finger. The scene owns the gesture so a drag can
    /// become a scroll, exactly as `LeaderboardScene` does for its rows: a node
    /// that tracked the touch itself would swallow the drag before the scene
    /// could read it as a scroll.
    private var pressedButton: PressableNode?

    private var listTopY: CGFloat = 0
    private var listBottomY: CGFloat = 0

    private var scrollOffset: CGFloat = 0
    private var scrollMinY: CGFloat = 0
    private var scrollMaxY: CGFloat = 0
    private var dragStartY: CGFloat = 0
    private var dragLastY: CGFloat = 0
    private var dragLastTimestamp: TimeInterval = 0
    private var dragVelocity: CGFloat = 0
    private var isScrollGesture = false
    /// Set once the first pass has run, so a later relayout can tell "not built
    /// yet" from the size the panels were placed at.
    private var isBuilt = false

    private enum Layout {
        static let rowHeight: CGFloat = 65
        static let rowGap: CGFloat = 9
        static let groupHeaderHeight: CGFloat = 34
        /// Extra room between one category's last row and the next heading, so a
        /// heading does not read as part of the block above it.
        static let groupGap: CGFloat = 10
        static let panelHeight: CGFloat = 144
        /// How far below `safeTop` the overview panel's centre sits.
        static let panelCentreDrop: CGFloat = 160
    }

    private var rowPitch: CGFloat { Layout.rowHeight + Layout.rowGap }
    private var listWidth: CGFloat { min(348, size.width - 32) }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        addChild(content)
        listMask.fillColor = .white
        listMask.strokeColor = .clear
        listCrop.maskNode = listMask
        listCrop.addChild(listWorld)
        // Added after the panel so the catalogue draws over it, though the mask
        // keeps the two from ever meeting.
        addChild(listCrop)
        addHeader(title: GameText.achievements, subtitle: "YOUR COMMAND OF TIME")
        buildContent()
        isBuilt = true
        transitionIn()
    }

    override func layoutDidChange() {
        guard isBuilt else { return }
        buildContent()
    }

    private func buildContent() {
        // The button that was mid-press no longer exists, so any hold in
        // progress is dropped with it.
        pressedButton = nil
        content.removeAllChildren()
        buildOverview()
        layoutBand()
        rebuildCatalogue()
    }

    // MARK: - Overview

    private func buildOverview() {
        let progress = SaveStore.shared.progress
        let engine = AchievementEngine.shared
        let unlocked = engine.unlockedCount(progress: progress)
        let panel = GameTheme.roundedPanel(size: CGSize(width: listWidth, height: Layout.panelHeight), fill: GameTheme.boardDark.withAlphaComponent(0.95))
        panel.position = CGPoint(x: 0, y: safeTop - Layout.panelCentreDrop)
        content.addChild(panel)
        let star = GameTheme.label("\u{2605}", size: 34, color: GameTheme.brassLight)
        star.position = CGPoint(x: -panel.frame.width / 2 + 44, y: 26)
        panel.addChild(star)
        let count = GameTheme.label("\(progress.totalStars)", size: 31, weight: .heavy, alignment: .left)
        count.position = CGPoint(x: -panel.frame.width / 2 + 75, y: 28)
        panel.addChild(count)
        let caption = GameTheme.label("OF 600 CAMPAIGN STARS", size: 9, color: GameTheme.textSecondary, weight: .medium, alignment: .left)
        caption.position = CGPoint(x: -panel.frame.width / 2 + 76, y: 0)
        panel.addChild(caption)
        let bar = ProgressBarNode(width: panel.frame.width - 38, height: 7)
        bar.position = CGPoint(x: 0, y: -38)
        panel.addChild(bar)
        bar.setTint(GameTheme.brass)
        bar.setProgress(CGFloat(progress.totalStars) / 600, animated: true)
        // Levels on the left, marks on the right. The mark count previously
        // existed only in the accessibility label, so the one number that
        // answers "how much of the catalogue have I got" was invisible on screen.
        let completed = GameTheme.label("\(progress.completedLevels) / 200 LEVELS", size: 10, color: GameTheme.textSecondary, weight: .bold, alignment: .left)
        completed.position = CGPoint(x: -panel.frame.width / 2 + 20, y: -58)
        panel.addChild(completed)
        let marks = GameTheme.label(
            "\(unlocked) / \(engine.catalog.count) \(LeaderboardBoard.achievements.metric)",
            size: 10,
            color: GameTheme.brassLight,
            weight: .bold,
            alignment: .right
        )
        marks.position = CGPoint(x: panel.frame.width / 2 - 20, y: -58)
        panel.addChild(marks)
        panel.accessibilityLabel = "\(progress.totalStars) stars, \(progress.completedLevels) levels, \(unlocked) of \(engine.catalog.count) mastery marks"

        // Entry point to the marks board, in the panel's free top-right corner.
        // It sits here rather than under the catalogue because that list fills
        // the rest of the screen, and this costs no height. A sibling of the
        // panel, not a child: the panel carries its own accessibility label, and
        // nesting would bury the button under it.
        let boardButton = PressableNode(
            identifier: "marks-board",
            title: "\(LeaderboardBoard.achievements.title) BOARD",
            size: CGSize(width: 118, height: 34),
            style: .freeze
        )
        boardButton.position = CGPoint(x: panel.frame.width / 2 - 67, y: panel.position.y + 28)
        boardButton.delegate = self
        // Driven from the scene's own touches, like the rows below it. Note the
        // node's real height is 44 whatever is asked for here: `PressableNode`
        // raises either side to `LayoutMetrics.minimumTouch`.
        boardButton.isUserInteractionEnabled = false
        content.addChild(boardButton)
    }

    // MARK: - Catalogue

    /// The whole catalogue, grouped by category, as one scrolling list.
    ///
    /// This used to be six "featured" entries picked by progress. That read as a
    /// full screen while the catalogue held 29 marks and hides almost all of
    /// them now it holds 73, so every mark is laid out and the player scrolls.
    private func rebuildCatalogue() {
        listWorld.removeAllChildren()
        let progress = SaveStore.shared.progress
        let engine = AchievementEngine.shared
        let width = listWidth
        var top = listTopY
        for category in AchievementCategory.allCases {
            let marks = engine.evaluations(category: category, progress: progress)
            guard !marks.isEmpty else { continue }
            if top < listTopY { top -= Layout.groupGap }
            let heading = groupHeading(
                category: category,
                unlocked: marks.filter(\.isUnlocked).count,
                total: marks.count,
                width: width
            )
            heading.position = CGPoint(x: 0, y: top - Layout.groupHeaderHeight / 2)
            listWorld.addChild(heading)
            top -= Layout.groupHeaderHeight
            for mark in marks {
                let row = markRow(mark, width: width)
                row.position = CGPoint(x: 0, y: top - Layout.rowHeight / 2)
                listWorld.addChild(row)
                top -= rowPitch
            }
        }
        // `top` now sits one row gap below the last row, and that gap is slack
        // the list should not be able to scroll into.
        let contentHeight = listTopY - top - Layout.rowGap
        scrollMaxY = max(0, contentHeight - (listTopY - listBottomY))
        scrollOffset = ScalarMath.clamp(scrollOffset, scrollMinY, scrollMaxY)
        applyScroll()
    }

    private func groupHeading(category: AchievementCategory, unlocked: Int, total: Int, width: CGFloat) -> SKNode {
        let node = SKNode()
        let title = GameTheme.label(category.title, size: 11, color: GameTheme.brassLight, weight: .bold, alignment: .left)
        title.position = CGPoint(x: -width / 2, y: 2)
        node.addChild(title)
        let count = GameTheme.label("\(unlocked)/\(total)", size: 10, color: GameTheme.textSecondary, weight: .bold, alignment: .right)
        count.position = CGPoint(x: width / 2, y: 2)
        node.addChild(count)
        // Same 1pt `divider` rule the settings list uses between its rows.
        let rule = SKShapeNode(rectOf: CGSize(width: width, height: 1))
        rule.fillColor = GameTheme.divider
        rule.strokeColor = .clear
        rule.position = CGPoint(x: 0, y: -Layout.groupHeaderHeight / 2 + 6)
        node.addChild(rule)
        return node
    }

    /// One mark. An unearned hidden mark keeps both its name and its condition
    /// to itself: the detail states what to do, so showing it greyed out would
    /// give the secret away.
    private func markRow(_ mark: AchievementEvaluation, width: CGFloat) -> SKNode {
        let definition = mark.definition
        let isMasked = definition.hidden && !mark.isUnlocked
        let panel = GameTheme.roundedPanel(
            size: CGSize(width: width, height: Layout.rowHeight),
            fill: mark.isUnlocked ? GameTheme.board : GameTheme.panel
        )
        // The tick is a delivered asset; the unearned state stays a drawn ring so
        // an earned and an unearned mark still read as the same shape.
        if mark.isUnlocked, let check = GameAssets.sprite(GameAssets.Icon.check, fitting: CGSize(width: 22, height: 22)) {
            check.position = CGPoint(x: -panel.frame.width / 2 + 25, y: 7)
            panel.addChild(check)
        } else {
            let glyph = isMasked ? "?" : (mark.isUnlocked ? "\u{2713}" : "\u{25CB}")
            let glyphColor = mark.isUnlocked && !isMasked ? GameTheme.jade : GameTheme.textSecondary
            let symbol = GameTheme.label(glyph, size: 18, color: glyphColor, weight: .bold)
            symbol.position = CGPoint(x: -panel.frame.width / 2 + 25, y: 7)
            panel.addChild(symbol)
        }
        let title = GameTheme.label(
            isMasked ? GameText.hiddenMarkTitle : definition.title,
            size: 11,
            color: mark.isUnlocked ? GameTheme.textPrimary : GameTheme.textSecondary,
            weight: .bold,
            alignment: .left
        )
        title.position = CGPoint(x: -panel.frame.width / 2 + 50, y: 10)
        panel.addChild(title)
        let detail = GameTheme.label(
            isMasked ? GameText.hiddenMarkDetail : definition.detail,
            size: 9,
            color: GameTheme.textSecondary,
            weight: .regular,
            alignment: .left
        )
        detail.position = CGPoint(x: -panel.frame.width / 2 + 50, y: -10)
        panel.addChild(detail)
        let meter = ProgressBarNode(width: 62, height: 4)
        meter.position = CGPoint(x: panel.frame.width / 2 - 47, y: -7)
        panel.addChild(meter)
        meter.setProgress(mark.progress, animated: false)
        panel.accessibilityLabel = isMasked
            ? "\(GameText.hiddenMarkDetail), \(mark.current) of \(mark.target)"
            : "\(definition.title), \(definition.detail), \(mark.current) of \(mark.target)"
        return panel
    }

    // MARK: - Band

    /// Recomputes the band the catalogue scrolls inside, and the mask that keeps
    /// scrolled rows off the header and the overview panel.
    private func layoutBand() {
        let panelBottom = safeTop - Layout.panelCentreDrop - Layout.panelHeight / 2
        listTopY = panelBottom - 14
        listBottomY = safeBottom + 14
        let bandHeight = max(1, listTopY - listBottomY)
        listMask.path = CGPath(
            rect: CGRect(
                x: -size.width / 2,
                y: listBottomY,
                width: size.width,
                height: bandHeight
            ),
            transform: nil
        )
    }

    private func applyScroll() {
        scrollOffset = ScalarMath.clamp(scrollOffset, scrollMinY, scrollMaxY)
        // Rows are laid out downwards from `listTopY`, so scrolling further down
        // the catalogue moves the layer up: a child at local `y` is drawn at
        // `y + scrollOffset`.
        listWorld.position = CGPoint(x: 0, y: scrollOffset)
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        pressedButton = content.children
            .compactMap { $0 as? PressableNode }
            .first { $0.containsScenePoint(point) }
        pressedButton?.beginPressFromContainer()
        dragStartY = point.y
        dragLastY = dragStartY
        dragLastTimestamp = touch.timestamp
        dragVelocity = 0
        isScrollGesture = false
        // A new touch stops any in-flight flick. The layer is snapped to the
        // stored offset first, because cancelling an animation leaves the node
        // wherever it had got to while `scrollOffset` already held the target.
        listWorld.removeAllActions()
        applyScroll()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let y = touch.location(in: self).y
        let delta = y - dragLastY
        if !isScrollGesture, abs(y - dragStartY) > 9 {
            isScrollGesture = true
            // Hand the gesture to the scroll and take the press back off the
            // button under the finger.
            pressedButton?.cancelPress()
            pressedButton = nil
        }
        guard isScrollGesture else { return }
        let elapsed = max(1.0 / 240.0, touch.timestamp - dragLastTimestamp)
        dragVelocity = delta / CGFloat(elapsed)
        // A finger moving up (negative delta) scrolls further down the catalogue.
        scrollOffset -= delta
        applyScroll()
        dragLastY = y
        dragLastTimestamp = touch.timestamp
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let button = pressedButton
        let wasScroll = isScrollGesture
        pressedButton = nil
        isScrollGesture = false
        guard !wasScroll else {
            guard !SaveStore.shared.settings.reduceMotion else { return }
            // A short projection of the release velocity reads as a flick without
            // carrying the list several screens past where the finger left it.
            let target = ScalarMath.clamp(scrollOffset - dragVelocity * 0.12, scrollMinY, scrollMaxY)
            scrollOffset = target
            listWorld.run(.moveTo(y: target, duration: 0.28))
            return
        }
        button?.activateFromContainer()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        pressedButton?.cancelPress()
        pressedButton = nil
        isScrollGesture = false
    }

    override func pressableNodeDidActivate(_ node: PressableNode) {
        guard node.identifier == "marks-board" else {
            super.pressableNodeDidActivate(node)
            return
        }
        GameCoordinator.shared.showLeaderboard(board: .achievements)
    }
}
