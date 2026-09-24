import SpriteKit
import UIKit

final class LaunchScene: BaseScene {
    override func didMove(to view: SKView) {
        super.didMove(to: view)
        let accent = SaveStore.shared.settings.tileSkin.accent
        let emblem = ClockEmblemNode(radius: 64)
        emblem.position = CGPoint(x: 0, y: 76)
        addChild(emblem)
        let time = GameTheme.label("TIME", size: 18, color: GameTheme.textSecondary, weight: .bold)
        time.fontName = GameTheme.titleFont(size: 18).fontName
        time.position = CGPoint(x: 0, y: -25)
        addChild(time)
        let freeze = GameTheme.label("FREEZE", size: 40, color: GameTheme.textPrimary, weight: .black)
        freeze.fontName = GameTheme.titleFont(size: 40).fontName
        freeze.position = CGPoint(x: 0, y: -65)
        addChild(freeze)
        let subtitle = GameTheme.label("CHRONO MAHJONG  //  SYSTEM 01", size: 9, color: accent, weight: .bold)
        subtitle.position = CGPoint(x: 0, y: -105)
        addChild(subtitle)
        if !SaveStore.shared.settings.reduceMotion {
            emblem.setScale(0.82)
            emblem.alpha = 0
            emblem.run(.group([.fadeIn(withDuration: 0.3), .scale(to: 1, duration: 0.36)]))
        }
        run(.sequence([
            .wait(forDuration: SaveStore.shared.settings.reduceMotion ? 0.1 : 0.75),
            .run { GameCoordinator.shared.showMenu() }
        ]))
    }
}

final class ClockEmblemNode: SKNode {
    init(radius: CGFloat) {
        super.init()
        let accent = SaveStore.shared.settings.tileSkin.accent
        let outer = SKShapeNode(circleOfRadius: radius)
        outer.fillColor = GameTheme.panel
        outer.strokeColor = accent
        outer.lineWidth = 2
        outer.glowWidth = 3
        addChild(outer)
        let inner = SKShapeNode(circleOfRadius: radius - 9)
        inner.fillColor = GameTheme.background
        inner.strokeColor = GameTheme.vermilion.withAlphaComponent(0.72)
        inner.lineWidth = 1.2
        addChild(inner)
        let core = SKShapeNode(circleOfRadius: radius - 18)
        core.fillColor = GameTheme.boardDark
        core.strokeColor = accent.withAlphaComponent(0.22)
        core.lineWidth = 1
        addChild(core)
        for index in 0..<12 {
            let tick = SKShapeNode(rectOf: CGSize(width: index % 3 == 0 ? 3 : 1.5, height: index % 3 == 0 ? 11 : 6), cornerRadius: 0.8)
            tick.fillColor = index % 4 == 0 ? GameTheme.vermilion : accent
            tick.strokeColor = .clear
            tick.position = CGPoint(x: 0, y: radius - 17).rotated(by: -CGFloat(index) * .pi / 6)
            tick.zRotation = -CGFloat(index) * .pi / 6
            addChild(tick)
        }
        for index in 0..<8 {
            let segment = SKShapeNode(rectOf: CGSize(width: radius * 0.30, height: 3))
            segment.fillColor = index % 3 == 0 ? GameTheme.vermilion : accent
            segment.strokeColor = .clear
            segment.position = CGPoint(x: 0, y: radius + 7).rotated(by: CGFloat(index) * .pi / 4)
            segment.zRotation = -CGFloat(index) * .pi / 4
            segment.alpha = index % 2 == 0 ? 0.82 : 0.34
            addChild(segment)
        }
        let tile = MahjongTileRenderer.makeFaceNode(
            suit: .dragon,
            face: .redDragon,
            team: .ivory,
            size: CGSize(width: radius * 0.62, height: radius * 0.82),
            compact: true,
            skin: SaveStore.shared.settings.tileSkin
        )
        tile.setScale(0.92)
        addChild(tile)
        let hand = SKShapeNode(rectOf: CGSize(width: 2.5, height: radius * 0.56), cornerRadius: 1.2)
        hand.fillColor = GameTheme.freezeWhite
        hand.strokeColor = .clear
        hand.glowWidth = 2
        hand.position.y = radius * 0.24
        hand.zRotation = -.pi / 5
        addChild(hand)
        let lock = SKShapeNode(circleOfRadius: 4)
        lock.fillColor = GameTheme.vermilion
        lock.strokeColor = GameTheme.freezeWhite
        lock.lineWidth = 1
        addChild(lock)
    }

    required init?(coder aDecoder: NSCoder) { nil }
}

final class MainMenuScene: BaseScene {
    /// Set once the first pass has run, so a relayout cannot build the menu a
    /// second time on top of itself.
    private var isBuilt = false

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        buildTitle()
        buildMenu()
        buildProgressSummary()
        isBuilt = true
        transitionIn()
    }

    override func layoutDidChange() {
        guard isBuilt else { return }
        // The title block hangs off `safeTop` and the summary panel off
        // `safeBottom`, so an inset that arrives or changes later moves both.
        removeSceneContent()
        buildTitle()
        buildMenu()
        buildProgressSummary()
    }

    private func buildTitle() {
        let accent = SaveStore.shared.settings.tileSkin.accent
        let emblem = ClockEmblemNode(radius: 43)
        emblem.position = CGPoint(x: 106, y: safeTop - 125)
        addChild(emblem)
        let system = GameTheme.label("CHRONO MAHJONG  //  01", size: 9, color: accent, weight: .bold, alignment: .left)
        system.position = CGPoint(x: -145, y: safeTop - 70)
        addChild(system)
        let time = GameTheme.label("TIME", size: 20, color: GameTheme.textSecondary, weight: .bold, alignment: .left)
        time.fontName = GameTheme.titleFont(size: 20).fontName
        time.position = CGPoint(x: -145, y: safeTop - 108)
        addChild(time)
        let freeze = GameTheme.label("FREEZE", size: 39, color: GameTheme.textPrimary, weight: .black, alignment: .left)
        freeze.fontName = GameTheme.titleFont(size: 39).fontName
        freeze.position = CGPoint(x: -145, y: safeTop - 151)
        addChild(freeze)
        let subtitle = GameTheme.label(GameText.subtitle, size: 11, color: GameTheme.textSecondary, weight: .regular)
        subtitle.position = CGPoint(x: 0, y: safeTop - 202)
        addChild(subtitle)

        let axis = SKShapeNode(rectOf: CGSize(width: min(330, size.width - 40), height: 1))
        axis.fillColor = GameTheme.divider
        axis.strokeColor = .clear
        axis.position = CGPoint(x: 0, y: safeTop - 224)
        addChild(axis)
        let signal = SKShapeNode(rectOf: CGSize(width: 58, height: 2))
        signal.fillColor = GameTheme.vermilion
        signal.strokeColor = .clear
        signal.position = CGPoint(x: min(330, size.width - 40) / 2 - 29, y: safeTop - 224)
        addChild(signal)
    }

    private func buildMenu() {
        let hasProgress = SaveStore.shared.progress.completedLevels > 0
        let verticalShift: CGFloat = size.height < 750 ? -24 : 0
        let first = PressableNode(
            identifier: hasProgress ? "continue" : "play",
            title: hasProgress ? GameText.continueGame : GameText.play,
            icon: "\u{25B6}",
            size: CGSize(width: min(330, size.width - 40), height: 54),
            style: .primary
        )
        first.position = CGPoint(x: 0, y: 74 + verticalShift)
        first.delegate = self
        addChild(first)

        let items = [
            ("chapters", GameText.chapters, "\u{25A6}"),
            ("daily", GameText.dailyPuzzle, "\u{25C9}"),
            ("endless", GameText.endless, "\u{221E}"),
            ("leaderboard", GameText.leaderboard, "trophy.fill"),
            ("mastery", GameText.achievements, "\u{2605}"),
            ("settings", GameText.settings, "\u{2699}"),
            ("skins", GameText.skins, "paintpalette.fill")
        ]
        let buttonWidth = (min(340, size.width - 40) - 10) / 2
        for (index, item) in items.enumerated() {
            // The last two share a row, so an even count leaves nothing full-width.
            let fullWidth = items.count % 2 == 1 && index == items.count - 1
            let button = PressableNode(
                identifier: item.0,
                title: item.1,
                icon: item.2,
                size: CGSize(width: fullWidth ? buttonWidth * 2 + 10 : buttonWidth, height: 52),
                style: .secondary
            )
            let row = index / 2
            let x: CGFloat = fullWidth ? 0 : (index % 2 == 0 ? -(buttonWidth + 10) / 2 : (buttonWidth + 10) / 2)
            button.position = CGPoint(x: x, y: 5 + verticalShift - CGFloat(row) * 64)
            button.delegate = self
            addChild(button)
        }
    }

    private func buildProgressSummary() {
        let progress = SaveStore.shared.progress
        let panel = GameTheme.roundedPanel(size: CGSize(width: min(340, size.width - 40), height: 74))
        panel.position = CGPoint(x: 0, y: safeBottom + 58)
        addChild(panel)
        // Counted off the engine rather than through `PlayerStatisticsCalculator`,
        // which would build ten chapter summaries and do date arithmetic for one
        // integer. The heading comes from the leaderboard board so the menu and
        // the MARKS board cannot drift apart on what the number is called.
        let engine = AchievementEngine.shared
        let values = [
            ("\(progress.completedLevels)/200", "LEVELS"),
            ("\(progress.totalStars)/600", "STARS"),
            ("\(progress.endlessBestStage)", "ENDLESS"),
            ("\(engine.unlockedCount(progress: progress))/\(engine.catalog.count)", LeaderboardBoard.achievements.metric)
        ]
        let column = panel.frame.width / CGFloat(values.count)
        for (index, value) in values.enumerated() {
            let x = -column * CGFloat(values.count - 1) / 2 + column * CGFloat(index)
            let number = GameTheme.label(value.0, size: 16, color: index == 1 ? GameTheme.brassLight : GameTheme.textPrimary, weight: .bold)
            number.position = CGPoint(x: x, y: 11)
            panel.addChild(number)
            let caption = GameTheme.label(value.1, size: 9, color: GameTheme.textSecondary, weight: .medium)
            caption.position = CGPoint(x: x, y: -14)
            panel.addChild(caption)
        }
    }

    override func pressableNodeDidActivate(_ node: PressableNode) {
        switch node.identifier {
        case "play", "continue": GameCoordinator.shared.continueCampaign()
        case "chapters": GameCoordinator.shared.showChapters()
        case "daily": GameCoordinator.shared.startDaily()
        case "endless": GameCoordinator.shared.startEndless()
        case "leaderboard": GameCoordinator.shared.showLeaderboard()
        case "mastery": GameCoordinator.shared.showMastery()
        case "settings": GameCoordinator.shared.showSettings()
        case "skins": GameCoordinator.shared.showSkins()
        default: break
        }
    }
}

final class ChapterSelectScene: BaseScene {
    /// Set once the first pass has run, so a relayout cannot stack a second set
    /// of chapter rows on the first.
    private var isBuilt = false

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        addHeader(title: "CHAPTERS", subtitle: "Ten lessons in mastering time")
        buildChapters()
        isBuilt = true
        transitionIn()
    }

    override func layoutDidChange() {
        guard isBuilt else { return }
        // The rows start below `safeTop`, and their height is derived from what
        // the safe bottom leaves, so both ends move with the insets.
        removeSceneContent()
        buildChapters()
    }

    private func buildChapters() {
        let availableHeight = size.height - 150 - max(view?.safeAreaInsets.bottom ?? 0, 12)
        let rowHeight = min(64, availableHeight / 10)
        let startY = safeTop - 93
        let width = min(350, size.width - 28)
        for chapter in 1...10 {
            let unlocked = SaveStore.shared.progress.isChapterUnlocked(chapter)
            let panel = ChapterRowNode(chapter: chapter, width: width, unlocked: unlocked)
            panel.position = CGPoint(x: 0, y: startY - CGFloat(chapter - 1) * rowHeight)
            panel.delegate = self
            addChild(panel)
        }
    }

    override func pressableNodeDidActivate(_ node: PressableNode) {
        if node.identifier.hasPrefix("chapter-"), let value = Int(node.identifier.dropFirst(8)) {
            GameCoordinator.shared.showLevels(chapter: value)
        } else {
            super.pressableNodeDidActivate(node)
        }
    }
}

private final class ChapterRowNode: PressableNode {
    init(chapter: Int, width: CGFloat, unlocked: Bool) {
        super.init(
            identifier: "chapter-\(chapter)",
            title: "",
            size: CGSize(width: width, height: 55),
            style: .secondary
        )
        setEnabled(unlocked)
        let number = GameTheme.label(String(format: "%02d", chapter), size: 17, color: unlocked ? GameTheme.brassLight : GameTheme.textSecondary, weight: .bold)
        number.position = CGPoint(x: -width / 2 + 28, y: 8)
        addChild(number)
        let title = GameTheme.label(GameText.chapterNames[chapter - 1], size: 12, color: unlocked ? GameTheme.textPrimary : GameTheme.textSecondary, weight: .bold, alignment: .left)
        title.position = CGPoint(x: -width / 2 + 55, y: 9)
        addChild(title)
        let subtitle = GameTheme.label(GameText.chapterDescriptions[chapter - 1], size: 9, color: GameTheme.textSecondary, weight: .regular, alignment: .left)
        subtitle.position = CGPoint(x: -width / 2 + 55, y: -11)
        addChild(subtitle)
        if let badge = GameAssets.sprite(GameAssets.ChapterArt.badge(chapter), fitting: CGSize(width: 34, height: 34)) {
            badge.position = CGPoint(x: width / 2 - 25, y: 0)
            badge.alpha = unlocked ? 1 : 0.34
            if !unlocked { badge.color = .black; badge.colorBlendFactor = 0.55 }
            addChild(badge)
        }
        let stars = SaveStore.shared.progress.chapterStars(chapter)
        let status = GameTheme.label(unlocked ? "\(stars)/60" : "LOCKED", size: 10, color: unlocked ? GameTheme.brassLight : GameTheme.textSecondary, weight: .bold, alignment: .right)
        status.position = CGPoint(x: width / 2 - 47, y: 0)
        addChild(status)
        if !unlocked, let lock = GameAssets.sprite(GameAssets.Icon.lock, fitting: CGSize(width: 13, height: 13)) {
            lock.position = CGPoint(x: width / 2 - 47 - status.frame.width - 9, y: 0)
            lock.alpha = 0.6
            addChild(lock)
        }
    }

    required init?(coder aDecoder: NSCoder) { nil }
}

final class LevelSelectScene: BaseScene {

    private enum Band {
        /// Half of the widest thing a stop carries — its collar, not its plate.
        /// The band keeps this much clear of both pieces of fixed furniture so
        /// a stop can never be parked half under either of them.
        static var stopClearance: CGFloat { LevelStopNode.clearanceRadius }
        static let legendHeight: CGFloat = 34
        static let legendOffset: CGFloat = 40
    }

    private let chapter: Int

    /// The highest edge of the legend, captured from the node itself when it is
    /// built. The band the path scrolls inside is derived from this and from
    /// the header's edge rather than from constants that have to be kept in
    /// step with two other pieces of layout by hand.
    private var legendTopY: CGFloat = 0

    /// Everything that scrolls: the trail, the stops and the destination. The
    /// header and the legend are siblings added after it, so tree order keeps
    /// them on top without needing a camera.
    private let pathWorld = SKNode()
    private let legend = SKNode()
    private var stopPositions: [CGPoint] = []
    private var scrollMinY: CGFloat = 0
    private var scrollMaxY: CGFloat = 0
    private var scrollOffset: CGFloat = 0

    private var dragStartY: CGFloat = 0
    private var dragLastY: CGFloat = 0
    private var dragLastTimestamp: TimeInterval = 0
    private var dragVelocity: CGFloat = 0
    private var isScrollGesture = false
    private var pressedStop: LevelStopNode?

    init(size: CGSize, chapter: Int) {
        self.chapter = chapter
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) { nil }

    /// Each chapter pins its own illustration behind the path, so the twenty
    /// levels of chapter six read as one place rather than a generic list.
    override var backdropAsset: String? { GameAssets.ChapterArt.illustration(chapter) }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        addChild(pathWorld)
        // Added after `pathWorld` so they are drawn over it and never scroll.
        addHeader(title: GameText.chapterNames[chapter - 1], subtitle: "CHAPTER \(chapter)  /  \(CampaignCopy.levelsPerChapter) LEVELS")
        addChild(legend)
        // Both pieces of fixed furniture are built before the path, because the
        // path's scroll band is derived from the edges they report.
        buildLegend()
        buildPath()
        centerOnCurrentProgress()
        transitionIn()
    }

    override func layoutDidChange() {
        // A resize invalidates every stop position and the scroll limits derived
        // from them, so the path is rebuilt rather than merely re-laid out.
        guard !stopPositions.isEmpty else { return }
        layoutLegend()
        pathWorld.removeAllChildren()
        buildPath()
        centerOnCurrentProgress()
    }

    private func buildPath() {
        let width = min(300, size.width - 90)
        let firstLevelID = (chapter - 1) * CampaignCopy.levelsPerChapter + 1
        let lastLevelID = chapter * CampaignCopy.levelsPerChapter
        let currentID = ScalarMath.clamp(SaveStore.shared.progress.lastLevelID, firstLevelID, lastLevelID)

        // The map lays level 1 at y = 0 and grows upward; the whole run is
        // shifted into the scrollable band afterwards rather than per stop.
        let stops = LevelPathMap.stops(chapter: chapter, width: width, originY: 0)
        let destination = LevelPathMap.destination(chapter: chapter, width: width, originY: 0)
        let contentHeight = LevelPathMap.contentHeight

        // The band is the gap the fixed furniture leaves, pulled in by half a
        // collar at each end so a stop parked at either limit still clears it.
        let bandBottom = legendTopY + Band.stopClearance
        let bandTop = headerBottomY - Band.stopClearance
        let yShift = (bandBottom + bandTop) / 2 - contentHeight / 2

        var points: [CGPoint] = []
        var clearedIndices: Set<Int> = []
        for stop in stops {
            let levelID = stop.levelID(chapter: chapter)
            let progress = SaveStore.shared.progressForLevel(levelID)
            if (progress?.stars ?? 0) > 0 { clearedIndices.insert(stop.indexInChapter) }

            let state: LevelStopNode.State
            if !SaveStore.shared.progress.isLevelUnlocked(levelID) {
                state = .locked
            } else if levelID == currentID {
                state = .current
            } else {
                state = .cleared
            }
            let node = LevelStopNode(
                levelID: levelID,
                indexInChapter: stop.indexInChapter,
                progress: progress,
                state: state
            )
            node.position = CGPoint(x: stop.position.x, y: stop.position.y + yShift)
            node.delegate = self
            pathWorld.addChild(node)
            points.append(node.position)
        }

        let destinationPoint = CGPoint(x: destination.x, y: destination.y + yShift)
        points.append(destinationPoint)
        stopPositions = points

        // The trail goes in first so the plates sit on top of the road.
        pathWorld.insertChild(
            PathTrail.build(
                points: points,
                clearedIndices: clearedIndices,
                stopCount: CampaignCopy.levelsPerChapter
            ),
            at: 0
        )

        let landmark = ChapterDestinationNode(
            chapter: chapter,
            stars: SaveStore.shared.progress.chapterStars(chapter),
            totalStars: CampaignCopy.levelsPerChapter * 3,
            width: width
        )
        landmark.position = destinationPoint
        pathWorld.addChild(landmark)

        // `scrollOffset` is the world's own y offset, and a stop at world y = p
        // lands on screen at `p - scrollOffset`. So the travel limits are the
        // stop coordinates relative to the band edges, not the edges relative to
        // the stops: the lowest offset parks the first stop on `bandBottom`, the
        // highest parks the destination on `bandTop`. Negating these collapses
        // the range to a single point and the path silently stops scrolling.
        scrollMinY = points[0].y - bandBottom
        scrollMaxY = destinationPoint.y - bandTop
        if scrollMinY > scrollMaxY {
            let middle = (scrollMinY + scrollMaxY) / 2
            scrollMinY = middle
            scrollMaxY = middle
        }
        scrollOffset = ScalarMath.clamp(scrollOffset, scrollMinY, scrollMaxY)
        applyScroll()
    }

    /// A footer note that names the three plate states the path introduces.
    private func buildLegend() {
        legend.removeAllChildren()

        let panel = GameTheme.roundedPanel(size: CGSize(width: min(300, size.width - 60), height: Band.legendHeight))
        legend.addChild(panel)

        let items = [
            (GameTheme.brassLight, "CLEARED"),
            (GameTheme.freezeBlue, "UP NEXT"),
            (GameTheme.divider, "LOCKED")
        ]
        let column = panel.frame.width / CGFloat(items.count)
        for (index, item) in items.enumerated() {
            let x = -panel.frame.width / 2 + column * (CGFloat(index) + 0.5)
            let dot = SKShapeNode(circleOfRadius: 4)
            dot.fillColor = item.0
            dot.strokeColor = .clear
            dot.position = CGPoint(x: x - 25, y: 0)
            legend.addChild(dot)
            let label = GameTheme.label(item.1, size: 8, color: GameTheme.textSecondary, weight: .bold, alignment: .left)
            label.position = CGPoint(x: x - 17, y: 0)
            legend.addChild(label)
        }
        layoutLegend()
    }

    /// Places the legend and records the y its panel reaches up to, which is
    /// what the path's band has to stay above. Split out from `buildLegend`
    /// because a resize moves it without rebuilding its contents.
    private func layoutLegend() {
        legend.position = CGPoint(x: 0, y: safeBottom + Band.legendOffset)
        legendTopY = legend.position.y + Band.legendHeight / 2
    }

    /// Opens the chapter at the stop the player is up to rather than at the top
    /// of the path, so arriving from the campaign always shows the next thing to
    /// do. The offset is placed directly rather than animated: the scene is
    /// still fading in, and a scroll under a fade reads as a glitch.
    private func centerOnCurrentProgress() {
        let firstLevelID = (chapter - 1) * CampaignCopy.levelsPerChapter + 1
        let localIndex = ScalarMath.clamp(
            SaveStore.shared.progress.lastLevelID - firstLevelID + 1,
            1,
            CampaignCopy.levelsPerChapter
        )
        guard stopPositions.indices.contains(localIndex - 1) else { return }
        scrollOffset = ScalarMath.clamp(stopPositions[localIndex - 1].y, scrollMinY, scrollMaxY)
        applyScroll()
    }

    private func applyScroll() {
        scrollOffset = ScalarMath.clamp(scrollOffset, scrollMinY, scrollMaxY)
        pathWorld.position = CGPoint(x: 0, y: -scrollOffset)
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        // A drag that starts on a stop must not become a tap, so the stop is
        // remembered here and only honoured if the gesture stays a tap.
        //
        // The hit test is done in `pathWorld`'s space, not the scene's: a stop's
        // frame is expressed in its parent's coordinates, and the parent is the
        // scrolling layer, so scene coordinates would be off by the scroll.
        pressedStop = stopNode(at: touch.location(in: pathWorld))
        pressedStop?.beginPressFromContainer()
        dragStartY = point.y
        dragLastY = dragStartY
        dragLastTimestamp = touch.timestamp
        dragVelocity = 0
        isScrollGesture = false
        pathWorld.removeAllActions()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let y = touch.location(in: self).y
        let delta = y - dragLastY

        if !isScrollGesture, abs(y - dragStartY) > 9 {
            isScrollGesture = true
            // Hand the gesture to the scroll and take the press back off
            // whatever plate is under the finger.
            pressedStop?.cancelPress()
            pressedStop = nil
        }
        guard isScrollGesture else { return }

        let elapsed = max(1.0 / 240.0, touch.timestamp - dragLastTimestamp)
        dragVelocity = delta / CGFloat(elapsed)
        scrollOffset += delta
        applyScroll()
        dragLastY = y
        dragLastTimestamp = touch.timestamp
    }

    /// A tap that never became a scroll activates the stop the finger went down
    /// on. The press feedback is driven from here rather than from the node's own
    /// touch handling, because a node that tracked touches itself would swallow
    /// the drag before the scene could read it as a scroll.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let stop = pressedStop
        let wasScroll = isScrollGesture
        pressedStop = nil
        isScrollGesture = false
        if wasScroll {
            glideAndSettle()
            return
        }
        stop?.activateFromContainer()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        pressedStop?.cancelPress()
        pressedStop = nil
        isScrollGesture = false
    }

    private func stopNode(at point: CGPoint) -> LevelStopNode? {
        pathWorld.children
            .compactMap { $0 as? LevelStopNode }
            .first { $0.containsScenePoint(point) }
    }

    /// Carries the scroll on after release and snaps to the nearest stop, so the
    /// path always comes to rest on a station rather than between two.
    private func glideAndSettle() {
        guard !SaveStore.shared.settings.reduceMotion else {
            settle()
            return
        }
        // A short projection of the release velocity is enough to feel like a
        // flick without overshooting several stops.
        let projected = scrollOffset + dragVelocity * 0.12
        let target = ScalarMath.clamp(nearestStopY(to: projected), scrollMinY, scrollMaxY)
        let distance = abs(target - scrollOffset)
        let duration = min(0.42, max(0.14, Double(distance) / 1200))
        scrollOffset = target
        pathWorld.run(.moveTo(y: -target, duration: duration))
    }

    private func settle() {
        let target = ScalarMath.clamp(nearestStopY(to: scrollOffset), scrollMinY, scrollMaxY)
        scrollOffset = target
        applyScroll()
    }

    private func nearestStopY(to y: CGFloat) -> CGFloat {
        stopPositions.min { abs($0.y - y) < abs($1.y - y) }?.y ?? y
    }

    override func pressableNodeDidActivate(_ node: PressableNode) {
        if node.identifier.hasPrefix("level-"), let id = Int(node.identifier.dropFirst(6)) {
            GameCoordinator.shared.startCampaignLevel(id: id)
        } else {
            super.pressableNodeDidActivate(node)
        }
    }
}

final class LevelLoadingScene: BaseScene {
    private let definition: LevelDefinition
    private let completion: () -> Void

    init(size: CGSize, definition: LevelDefinition, completion: @escaping () -> Void) {
        self.definition = definition
        self.completion = completion
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) { nil }

    /// The room the level takes place in, so the brief moment before play is
    /// already the right place rather than a black card.
    override var backdropAsset: String? { GameAssets.Environment.forChapter(definition.chapter).assetName }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        let number = GameTheme.label(definition.mode == .daily ? "DAILY" : definition.displayNumber, size: 13, color: GameTheme.brassLight, weight: .bold)
        number.position.y = 80
        addChild(number)
        let title = GameTheme.label(definition.name, size: 24, weight: .bold)
        title.position.y = 42
        addChild(title)
        let subtitle = GameTheme.label(definition.subtitle, size: 11, color: GameTheme.textSecondary, weight: .regular)
        subtitle.position.y = 12
        addChild(subtitle)
        let bar = ProgressBarNode(width: 180, height: 5)
        bar.position.y = -48
        addChild(bar)
        bar.setProgress(1, animated: !SaveStore.shared.settings.reduceMotion)
        run(.sequence([.wait(forDuration: SaveStore.shared.settings.reduceMotion ? 0.05 : 0.36), .run(completion)]))
    }
}
