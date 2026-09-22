import SpriteKit
import UIKit

final class GameCoordinator {
    static let shared = GameCoordinator()

    private weak var skView: SKView?
    private(set) var flowState: AppFlowState = .boot
    private var navigationStack: [AppFlowState] = []
    private var selectedChapter = 1
    /// Which board the leaderboard screen is showing, so backing out of it
    /// returns to the same one rather than to the campaign default.
    private var currentLeaderboardBoard: LeaderboardBoard = .campaign
    private var currentLevel: LevelDefinition?
    private var activeGameScene: GameScene?
    private var endlessRun: EndlessRun?

    private init() {}

    func attach(to view: SKView) {
        skView = view
        AudioService.shared.start()
        SyncEngine.shared.start()
    }

    func resizeScene(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        skView?.scene?.size = size
    }

    /// Re-lays out the presented scene after the view's safe area changes.
    ///
    /// The insets are not known while the first scene is being built and only
    /// become real once the view has been laid out. The view's bounds do not
    /// change at that moment, so the scene is never resized and would otherwise
    /// keep every position it derived from an inset of zero — the header too
    /// high, the scroll bands too tall, the board off-centre.
    func sceneSafeAreaDidChange() {
        if let base = skView?.scene as? BaseScene {
            base.refreshLayout()
        } else if let game = skView?.scene as? GameScene {
            game.relayoutForSafeArea()
        }
    }

    func showLaunch() {
        guard let view = skView else { return }
        flowState = .boot
        let scene = LaunchScene(size: view.bounds.size)
        present(scene, transition: .crossFade(withDuration: 0.15))
    }

    func showMenu(push: Bool = false) {
        if push { navigationStack.append(flowState) }
        flowState = .menu
        activeGameScene = nil
        present(MainMenuScene(size: sceneSize), transition: menuTransition())
    }

    func showChapters() {
        navigationStack.append(flowState)
        flowState = .chapterSelect
        present(ChapterSelectScene(size: sceneSize), transition: forwardTransition())
    }

    func showLevels(chapter: Int) {
        selectedChapter = ScalarMath.clamp(chapter, 1, 10)
        navigationStack.append(flowState)
        flowState = .levelSelect
        let scene = LevelSelectScene(size: sceneSize, chapter: selectedChapter)
        present(scene, transition: forwardTransition())
    }

    func showSettings() {
        navigationStack.append(flowState)
        flowState = .settings
        present(SettingsScene(size: sceneSize), transition: forwardTransition())
    }

    func showMastery() {
        navigationStack.append(flowState)
        flowState = .mastery
        present(MasteryScene(size: sceneSize), transition: forwardTransition())
    }

    func showLeaderboard(board: LeaderboardBoard = .campaign, push: Bool = true) {
        if push { navigationStack.append(flowState) }
        flowState = .leaderboard
        currentLeaderboardBoard = board
        present(LeaderboardScene(size: sceneSize, board: board), transition: forwardTransition())
    }

    /// Switches the board shown by the leaderboard screen.
    ///
    /// Deliberately not a push: tabs are peers, so walking four tabs and then
    /// pressing back should return to wherever the player came from rather than
    /// unwinding the tabs one at a time.
    func switchLeaderboardBoard(to board: LeaderboardBoard) {
        flowState = .leaderboard
        currentLeaderboardBoard = board
        present(
            LeaderboardScene(size: sceneSize, board: board),
            transition: SaveStore.shared.settings.reduceMotion
                ? .crossFade(withDuration: 0)
                : .crossFade(withDuration: 0.18)
        )
    }

    func continueCampaign() {
        let id = max(1, min(200, SaveStore.shared.progress.lastLevelID))
        startCampaignLevel(id: id)
    }

    func startCampaignLevel(id: Int) {
        guard SaveStore.shared.progress.isLevelUnlocked(id) else {
            HapticService.shared.play(.warning)
            return
        }
        SaveStore.shared.markLevelStarted(id)
        let definition = CampaignLevelBuilder.shared.level(id: id)
        startLevel(definition)
    }

    func startDaily() {
        let definition = ProceduralLevelGenerator.shared.dailyLevel(for: Date())
        startLevel(definition)
    }

    func startEndless() {
        endlessRun = EndlessRun()
        guard let definition = endlessRun?.nextLevel() else { return }
        startLevel(definition)
    }

    func startLevel(_ definition: LevelDefinition) {
        navigationStack.removeAll()
        currentLevel = definition
        flowState = .levelLoading
        let loading = LevelLoadingScene(size: sceneSize, definition: definition) { [weak self] in
            self?.presentGame(definition)
        }
        present(loading, transition: .crossFade(withDuration: 0.18))
    }

    func restartLevel() {
        guard let currentLevel else { return }
        presentGame(currentLevel, restart: true)
    }

    func levelDidComplete(_ result: LevelResult) {
        guard let level = currentLevel else { return }
        let unlockedBefore = unlockedChapters()
        // A copy, not a reference: `PlayerProgress` is a struct, so this stays
        // put while the branches below write. The marks earned are the
        // difference between it and the progress that comes out the far side,
        // which is the only way to tell "unlocked by this run" from "already
        // held" without persisting a list of the latter.
        let progressBefore = SaveStore.shared.progress
        if (1...200).contains(level.id) { SaveStore.shared.record(result) }
        if level.mode == .daily {
            SaveStore.shared.recordDaily(key: ProceduralLevelGenerator.dayKey(for: Date()), result: result)
        }
        if level.mode == .endless {
            endlessRun?.record(score: result.score)
            SaveStore.shared.recordEndless(score: endlessRun?.score ?? 0, stage: endlessRun?.stage ?? 1)
        }
        let earned = AchievementEngine.shared.newlyUnlocked(
            before: progressBefore,
            after: SaveStore.shared.progress
        )
        // Clearing the opening level of a chapter opens the next one; that is the
        // only moment the unlock tag is worth playing. The banner plays the same
        // tag when a mark lands, and the two can fall on the same board — the
        // tag player only ever holds one stinger, so it restarts rather than
        // doubling up.
        if unlockedChapters().count > unlockedBefore.count {
            AudioService.shared.playTag(.chapterUnlock)
        }
        SyncEngine.shared.requestSync(reason: "levelComplete")
        flowState = .success
        activeGameScene?.showResult(result)
        activeGameScene?.showAchievements(earned)
    }

    private func unlockedChapters() -> Set<Int> {
        Set((1...10).filter { SaveStore.shared.progress.isChapterUnlocked($0) })
    }

    func levelDidFail(_ reason: FailureKind) {
        flowState = .failure
        activeGameScene?.showFailure(reason)
    }

    func advanceAfterResult() {
        guard let level = currentLevel else { return }
        if level.mode == .endless, let next = endlessRun?.nextLevel() {
            startLevel(next)
        } else if level.mode == .daily {
            showMenu()
        } else if level.id < 200 {
            startCampaignLevel(id: level.id + 1)
        } else {
            showMastery()
        }
    }

    func exitLevel() {
        activeGameScene?.tearDown()
        activeGameScene = nil
        currentLevel = nil
        navigationStack.removeAll()
        showMenu()
    }

    func goBack() {
        let previous = navigationStack.popLast() ?? .menu
        switch previous {
        case .menu, .boot: showMenu()
        case .chapterSelect: showChaptersWithoutPush()
        case .levelSelect: showLevelsWithoutPush(chapter: selectedChapter)
        case .settings: showSettingsWithoutPush()
        case .mastery: showMasteryWithoutPush()
        // Restores whichever board was on screen. Passing no board used to fall
        // back to the `.campaign` default, so backing out of any other tab
        // landed the player on the campaign board.
        case .leaderboard: showLeaderboard(board: currentLeaderboardBoard, push: false)
        default: showMenu()
        }
    }

    func applicationResignedActive() {
        activeGameScene?.pauseForInterruption()
        SaveStore.shared.flush()
        SyncEngine.shared.flush()
    }

    func applicationBecameActive() {
        activeGameScene?.resumeFromInterruption()
        HapticService.shared.prepare()
    }

    private var sceneSize: CGSize {
        let size = skView?.bounds.size ?? LayoutMetrics.referenceSize
        return size.width > 0 && size.height > 0 ? size : LayoutMetrics.referenceSize
    }

    private func presentGame(_ definition: LevelDefinition, restart: Bool = false) {
        flowState = .playing
        let scene = GameScene(size: sceneSize, definition: definition)
        activeGameScene = scene
        let transition = restart
            ? SKTransition.crossFade(withDuration: SaveStore.shared.settings.reduceMotion ? 0 : 0.16)
            : SKTransition.fade(with: GameTheme.background, duration: SaveStore.shared.settings.reduceMotion ? 0 : 0.28)
        present(scene, transition: transition)
    }

    private func present(_ scene: SKScene, transition: SKTransition) {
        scene.scaleMode = .resizeFill
        applyAudio(for: scene)
        skView?.presentScene(scene, transition: transition)
    }

    /// Music and room tone follow the scene, so every navigation path lands on the
    /// right bed without each caller having to remember to change it. The loading
    /// scene deliberately keeps whatever is already playing, so the menu bed rides
    /// into the level instead of gapping.
    private func applyAudio(for scene: SKScene) {
        switch scene {
        case is GameScene:
            guard let currentLevel else { return }
            AudioService.shared.playMusic(.gameplay(forChapter: currentLevel.chapter))
            AudioService.shared.playAmbient(.forChapter(currentLevel.chapter))
        case is LevelLoadingScene:
            break
        default:
            AudioService.shared.playMusic(.menu)
            AudioService.shared.playAmbient(.tableRoom)
        }
    }

    private func showChaptersWithoutPush() {
        flowState = .chapterSelect
        present(ChapterSelectScene(size: sceneSize), transition: backTransition())
    }

    private func showLevelsWithoutPush(chapter: Int) {
        flowState = .levelSelect
        present(LevelSelectScene(size: sceneSize, chapter: chapter), transition: backTransition())
    }

    private func showSettingsWithoutPush() {
        flowState = .settings
        present(SettingsScene(size: sceneSize), transition: backTransition())
    }

    private func showMasteryWithoutPush() {
        flowState = .mastery
        present(MasteryScene(size: sceneSize), transition: backTransition())
    }

    private func menuTransition() -> SKTransition {
        SaveStore.shared.settings.reduceMotion ? .crossFade(withDuration: 0) : .fade(withDuration: 0.24)
    }

    private func forwardTransition() -> SKTransition {
        SaveStore.shared.settings.reduceMotion ? .crossFade(withDuration: 0) : .push(with: .left, duration: 0.28)
    }

    private func backTransition() -> SKTransition {
        SaveStore.shared.settings.reduceMotion ? .crossFade(withDuration: 0) : .push(with: .right, duration: 0.24)
    }
}

struct EndlessRun {
    private(set) var stage = 0
    private(set) var score = 0
    private let seed: UInt64

    init() {
        seed = UInt64(Date().timeIntervalSince1970 * 1000)
    }

    mutating func nextLevel() -> LevelDefinition {
        stage += 1
        return ProceduralLevelGenerator.shared.endlessLevel(stage: stage, seed: seed &+ UInt64(stage * 7919))
    }

    mutating func record(score resultScore: Int) {
        score += resultScore + stage * 500
    }
}
