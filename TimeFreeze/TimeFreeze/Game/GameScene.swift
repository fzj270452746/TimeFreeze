import SpriteKit
import UIKit

final class GameScene: SKScene,
                       GameWorldDelegate,
                       GameInputControllerDelegate,
                       GameplayHUDDelegate,
                       PausePanelDelegate,
                       ResultPanelDelegate {
    let definition: LevelDefinition
    private let world: GameWorld
    private let hud: GameplayHUD
    private let inputController: GameInputController
    private let tutorialBanner = TutorialBannerNode()
    private var tutorialManager: TutorialManager?
    private var pausePanel: PausePanel?
    private var resultPanel: ResultPanel?
    private var achievementBanner: AchievementBannerNode?
    private var eventToken: GameEventBus.Token?
    private var isInterrupted = false
    private var lastHUDUpdate: TimeInterval = 0
    private var startedAt = Date()
    private var recorder: ReplayRecorder?
    private var ghostReplay: GhostReplayNode?
    private let chronoFrame = SKShapeNode()
    private let freezeVeil = SKShapeNode()
    private let scanline = SKShapeNode()

    init(size: CGSize, definition: LevelDefinition) {
        self.definition = definition
        world = GameWorld(definition: definition)
        hud = GameplayHUD(definition: definition)
        inputController = GameInputController(world: world)
        super.init(size: size)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        scaleMode = .resizeFill
        backgroundColor = GameTheme.background
        world.delegate = self
        inputController.delegate = self
        hud.delegate = self
        buildScene()
        configureTutorial()
        configureReplay()
    }

    required init?(coder aDecoder: NSCoder) { nil }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        layoutScene()
        tutorialManager?.start()
        startedAt = Date()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutScene()
    }

    override func update(_ currentTime: TimeInterval) {
        world.update(timestamp: currentTime)
        ghostReplay?.update(deltaTime: world.timeController.clock.realDelta)
        recorder?.update(world: world)
        if currentTime - lastHUDUpdate > 0.08 {
            lastHUDUpdate = currentTime
            hud.updateMetrics(
                freezes: world.timeController.freezeCount,
                worldTime: world.timeController.clock.worldTime
            )
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard pausePanel == nil, resultPanel == nil, let touch = touches.first else { return }
        let point = touch.location(in: world.worldContent)
        guard world.boardRect.insetBy(dx: -12, dy: -12).contains(point) else { return }
        inputController.touchesBegan(at: point, timestamp: touch.timestamp)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard pausePanel == nil, resultPanel == nil, let touch = touches.first else { return }
        inputController.touchesMoved(to: touch.location(in: world.worldContent))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard pausePanel == nil, resultPanel == nil, let touch = touches.first else { return }
        let interacted = inputController.touchesEnded(at: touch.location(in: world.worldContent))
        if interacted {
            tutorialManager?.recordDrag()
            tutorialManager?.recordTileInteraction()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        inputController.cancel()
    }

    func showResult(_ result: LevelResult) {
        guard resultPanel == nil else { return }
        let panel = ResultPanel(sceneSize: size, result: result, failure: nil)
        panel.delegate = self
        addChild(panel)
        resultPanel = panel
    }

    func showFailure(_ reason: FailureKind) {
        guard resultPanel == nil else { return }
        let panel = ResultPanel(sceneSize: size, result: nil, failure: reason)
        panel.delegate = self
        addChild(panel)
        resultPanel = panel
    }

    /// Slides in the marks the run that just ended has earned.
    ///
    /// Called after `showResult`, so the card arrives over a panel that is
    /// already on screen rather than racing it. It takes no part in touch
    /// handling: the world is held by the same `resultPanel` guards it always
    /// was, and the card itself is inert.
    func showAchievements(_ definitions: [AchievementDefinition]) {
        guard !definitions.isEmpty else { return }
        // Built on demand. A run that earns nothing should not carry a node it
        // will never show, and this is the only moment one is ever needed.
        if achievementBanner == nil {
            let banner = AchievementBannerNode(sceneSize: size)
            addChild(banner)
            banner.layout(in: self)
            achievementBanner = banner
        }
        achievementBanner?.enqueue(
            definitions,
            marks: AchievementEngine.shared.unlockedCount(),
            total: AchievementEngine.shared.catalog.count
        )
    }

    func pauseForInterruption() {
        guard !isInterrupted, resultPanel == nil else { return }
        isInterrupted = true
        showPause()
    }

    func resumeFromInterruption() {
        isInterrupted = false
        world.timeController.clock.suspend()
    }

    func tearDown() {
        recorder?.finish(world: world)
        world.tearDown()
        removeAllActions()
        removeAllChildren()
    }

    func gameWorld(_ world: GameWorld, timeStateChanged state: TimeState) {
        hud.update(state: state)
        updateChronoState(state)
        recorder?.recordTimeState(state, worldTime: world.timeController.clock.worldTime)
    }

    func gameWorld(_ world: GameWorld, energyChanged energy: CGFloat) {
        hud.updateEnergy(energy)
    }

    func gameWorld(_ world: GameWorld, objectiveProgressChanged progress: CGFloat) {
        hud.updateObjective(progress: progress)
    }

    func gameWorld(_ world: GameWorld, didFail reason: FailureKind) {
        recorder?.recordFailure(reason, worldTime: world.timeController.clock.worldTime)
        GameCoordinator.shared.levelDidFail(reason)
    }

    func gameWorldDidComplete(_ world: GameWorld) {
        let freezes = world.timeController.freezeCount
        let worldTime = CGFloat(world.timeController.clock.worldTime)
        let stars = definition.starThresholds.stars(freezes: freezes, time: worldTime)
        let result = LevelResult(
            levelID: definition.id,
            completed: true,
            stars: stars,
            freezeCount: freezes,
            worldTime: worldTime,
            realTime: CGFloat(Date().timeIntervalSince(startedAt)),
            interactions: world.interactionCount,
            rewinds: world.timeController.rewindCount,
            completedAt: Date(),
            mode: definition.mode,
            score: LevelResult.score(stars: stars, freezes: freezes, worldTime: worldTime, difficulty: definition.difficulty)
        )
        recorder?.recordCompletion(result, worldTime: world.timeController.clock.worldTime)
        recorder?.finish(world: world)
        GameCoordinator.shared.levelDidComplete(result)
    }

    func inputControllerRequestedFreeze(at point: CGPoint) {
        _ = world.toggleFreeze(at: point)
    }

    func inputControllerBeganRewind() { _ = world.beginRewind() }
    func inputControllerEndedRewind() { world.endRewind() }

    func gameplayHUDRequestedPause() { showPause() }
    func gameplayHUDRequestedRestart() {
        // A `PressableNode` takes its own touches, so the HUD's restart button is
        // live whether or not a panel is up — the result panel's dim is an
        // `SKShapeNode` and swallows nothing. That was survivable while the
        // corner it sits in looked inert, but the achievement card now lands
        // right on top of it, and a player reaching for the card would restart
        // the level they have just finished.
        guard pausePanel == nil, resultPanel == nil else { return }
        GameCoordinator.shared.restartLevel()
    }
    func gameplayHUDRequestedFreeze(at point: CGPoint) { _ = world.toggleFreeze(at: point) }
    func gameplayHUDRequestedRewind(began: Bool) {
        if began { _ = world.beginRewind() }
        else { world.endRewind() }
    }

    func pausePanelDidResume() {
        pausePanel?.removeFromParent()
        pausePanel = nil
        world.setPaused(false)
    }

    func pausePanelDidRestart() { GameCoordinator.shared.restartLevel() }
    func pausePanelDidQuit() { GameCoordinator.shared.exitLevel() }
    func resultPanelRequestedNext() { GameCoordinator.shared.advanceAfterResult() }
    func resultPanelRequestedRetry() { GameCoordinator.shared.restartLevel() }
    func resultPanelRequestedMenu() { GameCoordinator.shared.exitLevel() }

    private func buildScene() {
        addBackground()
        addChild(world)
        addChild(hud)
        addChild(tutorialBanner)
    }

    private func addBackground() {
        let hasBackdrop = addEnvironmentBackdrop()
        let background = SKShapeNode(rectOf: CGSize(width: max(size.width, 430), height: max(size.height, 900)))
        background.fillColor = hasBackdrop ? .clear : GameTheme.background
        background.strokeColor = .clear
        background.zPosition = -100
        addChild(background)
        let arenaSize = CGSize(width: max(0, size.width - 18), height: max(0, size.height - 26))
        let arena = SKShapeNode(path: GameTheme.chamferedPath(size: arenaSize, cut: 14))
        arena.fillColor = hasBackdrop ? GameTheme.boardDark.withAlphaComponent(0.62) : GameTheme.boardDark
        arena.strokeColor = GameTheme.freezeBlue.withAlphaComponent(0.24)
        arena.lineWidth = 1
        arena.zPosition = -99
        addChild(arena)
        for index in 0..<20 {
            let line = SKShapeNode(rectOf: CGSize(width: size.width - 34, height: 0.7))
            line.fillColor = GameTheme.freezeBlue.withAlphaComponent(index % 5 == 0 ? 0.07 : 0.025)
            line.strokeColor = .clear
            line.position.y = -size.height / 2 + 22 + CGFloat(index) * max(22, size.height / 20)
            line.zPosition = -98
            addChild(line)
        }
        for index in 0..<7 {
            let path = CGMutablePath()
            let x = -size.width / 2 + CGFloat(index) * size.width / 6
            path.move(to: CGPoint(x: x, y: -size.height / 2 + 14))
            path.addLine(to: CGPoint(x: x * 0.20, y: size.height * 0.18))
            let ray = SKShapeNode(path: path)
            ray.strokeColor = GameTheme.vermilion.withAlphaComponent(0.035)
            ray.lineWidth = 0.8
            ray.zPosition = -97
            addChild(ray)
        }
        freezeVeil.fillColor = GameTheme.freezeBlue
        freezeVeil.strokeColor = .clear
        freezeVeil.alpha = 0
        freezeVeil.zPosition = 450
        addChild(freezeVeil)
        chronoFrame.fillColor = .clear
        chronoFrame.strokeColor = GameTheme.divider
        chronoFrame.lineWidth = 1.4
        chronoFrame.zPosition = 480
        addChild(chronoFrame)
        scanline.fillColor = GameTheme.freezeBlue
        scanline.strokeColor = .clear
        scanline.alpha = 0
        scanline.zPosition = 481
        addChild(scanline)
        updateChronoState(.running)
    }

    /// The room the chapter takes place in, drawn behind the arena and then
    /// dimmed. Returns whether art was found so the caller can fall back to the
    /// flat background and keep the arena opaque when the folder is incomplete.
    private func addEnvironmentBackdrop() -> Bool {
        let asset = GameAssets.Environment.forChapter(definition.chapter).assetName
        guard let texture = GameAssets.backdrop(asset) else { return false }
        let source = texture.size()
        guard source.width > 0, source.height > 0 else { return false }
        let cover = max(size.width / source.width, size.height / source.height)
        let art = SKSpriteNode(texture: texture)
        art.size = CGSize(width: source.width * cover, height: source.height * cover)
        art.alpha = 0.5
        art.zPosition = -99.9
        addChild(art)
        let scrim = SKShapeNode(rectOf: CGSize(width: max(size.width, 430), height: max(size.height, 900)))
        scrim.fillColor = GameTheme.background.withAlphaComponent(0.42)
        scrim.strokeColor = .clear
        scrim.zPosition = -99.8
        addChild(scrim)
        return true
    }

    private func layoutScene() {
        layoutGeometry()
        if let step = tutorialManager?.currentStep { showTutorial(step) }
    }

    /// Re-applies the geometry after the view's safe area arrives.
    ///
    /// The insets are unknown while the scene is being built, so the first pass
    /// places the board and the HUD against the fallback inset. The tutorial is
    /// deliberately left out here: it is already on screen, and routing through
    /// `layoutScene` would restart the step the player is midway through.
    func relayoutForSafeArea() {
        layoutGeometry()
    }

    private func layoutGeometry() {
        let safeTop = size.height / 2 - max(view?.safeAreaInsets.top ?? 0, 16)
        let safeBottom = -size.height / 2 + max(view?.safeAreaInsets.bottom ?? 0, 10)
        let availableTop = safeTop - 106
        let availableBottom = safeBottom + 112
        let availableHeight = availableTop - availableBottom
        let scaleX = (size.width - 22) / definition.boardSize.width
        let scaleY = availableHeight / definition.boardSize.height
        let scale = min(1, scaleX, scaleY)
        world.setScale(scale)
        world.position = CGPoint(x: 0, y: (availableTop + availableBottom) / 2)
        hud.layout(in: self)
        let overlaySize = CGSize(width: max(0, size.width - 12), height: max(0, size.height - 18))
        chronoFrame.path = GameTheme.chamferedPath(size: overlaySize, cut: 12)
        freezeVeil.path = CGPath(rect: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height), transform: nil)
        scanline.path = CGPath(rect: CGRect(x: -(size.width - 24) / 2, y: -0.5, width: size.width - 24, height: 1), transform: nil)
        // The card is seated from the safe area too, and it is built before the
        // insets are known when a run earns its first mark on the opening level.
        achievementBanner?.layout(in: self)
    }

    private func updateChronoState(_ state: TimeState) {
        scanline.removeAllActions()
        chronoFrame.removeAllActions()
        chronoFrame.glowWidth = 0
        scanline.alpha = 0
        switch state {
        case .running:
            freezeVeil.alpha = 0
            chronoFrame.strokeColor = GameTheme.divider
        case .frozen:
            freezeVeil.fillColor = GameTheme.freezeBlue
            freezeVeil.alpha = 0.035
            chronoFrame.strokeColor = GameTheme.freezeBlue
            chronoFrame.glowWidth = 5
            startScanline(color: GameTheme.freezeBlue, duration: 1.7)
        case .slowMotion:
            freezeVeil.fillColor = GameTheme.jade
            freezeVeil.alpha = 0.022
            chronoFrame.strokeColor = GameTheme.jade.withAlphaComponent(0.72)
            chronoFrame.glowWidth = 2
            startScanline(color: GameTheme.jade, duration: 3.2)
        case .rewinding:
            freezeVeil.fillColor = GameTheme.vermilion
            freezeVeil.alpha = 0.032
            chronoFrame.strokeColor = GameTheme.vermilion
            chronoFrame.glowWidth = 4
            startScanline(color: GameTheme.vermilion, duration: 0.85)
        }
    }

    private func startScanline(color: UIColor, duration: TimeInterval) {
        scanline.fillColor = color
        scanline.alpha = 0.30
        scanline.position.y = size.height / 2 - 18
        guard !SaveStore.shared.settings.reduceMotion else { return }
        scanline.run(.repeatForever(.sequence([
            .moveTo(y: -size.height / 2 + 18, duration: duration),
            .moveTo(y: size.height / 2 - 18, duration: 0)
        ])))
    }

    private func configureTutorial() {
        guard let key = definition.rules.tutorialKey else { return }
        let manager = TutorialManager(key: key, steps: TutorialManager.steps(for: key))
        tutorialManager = manager
        manager.stepChanged = { [weak self] step in
            guard let self else { return }
            if let step { self.showTutorial(step) }
            else { self.tutorialBanner.hide() }
        }
        eventToken = world.eventBus.subscribe(owner: self) { [weak self] event in
            self?.tutorialManager?.consume(event)
            self?.recorder?.record(event: event, worldTime: self?.world.timeController.clock.worldTime ?? 0)
        }
    }

    private func configureReplay() {
        recorder = ReplayRecorder(levelID: definition.id, seed: definition.seed)
        guard (1...200).contains(definition.id),
              let replay = ReplayStore.shared.load(levelID: definition.id),
              replay.seed == definition.seed else { return }
        let ghost = GhostReplayNode(replay: replay, tileDefinitions: definition.tiles)
        world.worldContent.addChild(ghost)
        ghost.play()
        ghostReplay = ghost
    }

    private func showTutorial(_ step: TutorialStep) {
        let y = world.position.y + definition.boardSize.height * world.yScale / 2 - 44
        tutorialBanner.show(step.instruction, at: CGPoint(x: 0, y: y))
    }

    private func showPause() {
        guard pausePanel == nil, resultPanel == nil else { return }
        world.setPaused(true)
        let panel = PausePanel(sceneSize: size)
        panel.delegate = self
        addChild(panel)
        pausePanel = panel
    }
}
