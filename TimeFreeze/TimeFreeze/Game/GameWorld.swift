import SpriteKit
import UIKit

protocol GameWorldDelegate: AnyObject {
    func gameWorld(_ world: GameWorld, timeStateChanged state: TimeState)
    func gameWorld(_ world: GameWorld, energyChanged energy: CGFloat)
    func gameWorld(_ world: GameWorld, objectiveProgressChanged progress: CGFloat)
    func gameWorld(_ world: GameWorld, didFail reason: FailureKind)
    func gameWorldDidComplete(_ world: GameWorld)
}

final class GameWorld: SKNode, TimeControllerDelegate {
    let definition: LevelDefinition
    let eventBus = GameEventBus()
    let timeController = TimeController()
    let collisionManager = CollisionManager()
    let timeline = SnapshotTimeline(interval: 0.1, maximumDuration: 9)
    let worldContent = SKNode()
    let effectLayer = SKNode()
    let effects: GameEffects
    let boardRect: CGRect
    private(set) var tiles: [MahjongTileNode] = []
    private(set) var mechanisms: [BaseMechanismNode] = []
    private(set) var targets: [TargetNode] = []
    private(set) var objectiveEvaluator: ObjectiveEvaluator
    private var eventToken: GameEventBus.Token?
    private var isComplete = false
    private var isFailed = false
    private var rewindAccumulator: TimeInterval = 0
    private var priorObjectiveProgress: CGFloat = -1
    private var simulationPaused = false
    var interactionCount = 0
    weak var delegate: GameWorldDelegate?

    init(definition: LevelDefinition) {
        self.definition = definition
        boardRect = CGRect(
            x: -definition.boardSize.width / 2,
            y: -definition.boardSize.height / 2,
            width: definition.boardSize.width,
            height: definition.boardSize.height
        )
        effects = GameEffects(container: effectLayer)
        objectiveEvaluator = ObjectiveEvaluator(definitions: definition.objectives, eventBus: eventBus)
        super.init()
        name = "gameWorld"
        addChild(worldContent)
        addChild(effectLayer)
        buildBoard()
        buildObjects()
        attachEventRouting()
        timeController.delegate = self
        timeController.configure(rules: definition.rules)
        objectiveEvaluator.attach(to: self)
    }

    required init?(coder aDecoder: NSCoder) { nil }

    func update(timestamp: TimeInterval) {
        guard !simulationPaused, !isComplete, !isFailed else { return }
        timeController.update(timestamp: timestamp)
        if timeController.state == .rewinding {
            updateRewind(deltaTime: timeController.clock.realDelta)
            return
        }
        updateTimeZones()
        let mechanismDelta = timeController.clock.simulationDelta
        for mechanism in mechanisms {
            mechanism.update(deltaTime: mechanismDelta, world: self)
        }
        for tile in tiles {
            let delta = timeController.simulationDelta(for: tile.team, affectedByFreeze: tile.definition.affectedByFreeze)
            tile.update(deltaTime: delta, world: self)
        }
        if mechanismDelta > 0 { collisionManager.update(world: self) }
        for target in targets {
            target.update(tiles: tiles, deltaTime: CGFloat(max(mechanismDelta, timeController.clock.realDelta * 0.1)), eventBus: eventBus)
        }
        for tile in tiles {
            tile.markInsideTarget(targets.contains { $0.occupantIDs.contains(tile.objectID) })
        }
        objectiveEvaluator.update()
        updateFailureRules()
        captureSnapshotIfNeeded()
        reportObjectiveProgress()
    }

    @discardableResult
    func toggleFreeze(at point: CGPoint) -> Bool {
        guard !simulationPaused, !isComplete, !isFailed else { return false }
        let enteringFreeze = timeController.state != .frozen
        if enteringFreeze && definition.rules.maximumFreezes > 0 &&
            timeController.freezeCount >= definition.rules.maximumFreezes {
            failLevel(.freezeLimitReached)
            return false
        }
        if enteringFreeze && missedFreezeWindowIsFatal && !isValidFreezeWindowAttempt {
            failLevel(.freezeMissed)
            return false
        }
        if timeController.state != .frozen && isPointBlockedFromFreezing(point) {
            HapticService.shared.play(.warning)
            return false
        }
        guard timeController.toggleFreeze() else {
            HapticService.shared.play(.warning)
            return false
        }
        if enteringFreeze {
            effects.emitFreezeBurst(at: point, maximumRadius: max(definition.boardSize.width, definition.boardSize.height) * 0.75)
            eventBus.publish(.timeFrozen(position: point))
            AudioService.shared.play(.freeze)
            AudioService.shared.setFreezeLayer(true)
            HapticService.shared.play(.freeze)
        } else {
            eventBus.publish(.timeResumed)
            AudioService.shared.play(.resume)
            AudioService.shared.setFreezeLayer(false)
            HapticService.shared.play(.resume)
        }
        return true
    }

    /// Whether stopping the clock away from the mark should end the run.
    ///
    /// Freezing is only ever fatal when it spends the level's last one. A level
    /// that hands out a fixed budget is built around a single decisive freeze —
    /// the opening levels give exactly one, and "MISSED FREEZE WINDOW" is
    /// literal there. Where freezes are unlimited the same tap is a working
    /// tool: the wind-tile levels need one freeze to turn the tile and a second
    /// to stop it on the mark, so a freeze that lands off the mark is a
    /// rehearsal the player resumes out of rather than a loss.
    ///
    /// Judging every freeze by the win condition alone made those levels
    /// impossible to finish — the opening tap of their own tutorial, the tap
    /// that stops the world so the tile can be turned, ended the run on the
    /// spot, and leaving the tile alone flew it off the board instead.
    private var missedFreezeWindowIsFatal: Bool {
        let limit = definition.rules.maximumFreezes
        guard limit > 0, timeController.freezeCount + 1 >= limit else { return false }
        return definition.objectives.contains { !$0.optional && $0.kind == .freezeInZone }
    }

    private var isValidFreezeWindowAttempt: Bool {
        let zones = mechanisms.compactMap { $0 as? TimeZoneNode }
            .filter { $0.definition.kind == .freezeZone }
        guard !zones.isEmpty else { return false }
        return targets.contains { target in
            tiles.contains { tile in
                target.containsAccepted(tile) && zones.contains { $0.containsRegion(tile.position) }
            }
        }
    }

    func beginRewind() -> Bool {
        guard !simulationPaused, timeController.beginRewind() else { return false }
        rewindAccumulator = 0
        AudioService.shared.play(.rewind)
        return true
    }

    func endRewind() {
        timeController.endRewind()
    }

    func setPaused(_ paused: Bool) {
        simulationPaused = paused
        if paused { timeController.clock.suspend() }
    }

    func resetRuntime() {
        isComplete = false
        isFailed = false
        interactionCount = 0
        priorObjectiveProgress = -1
        collisionManager.reset()
        timeline.reset()
        effects.clear()
        // A reset can land mid-freeze, which would otherwise strand the drone.
        AudioService.shared.setFreezeLayer(false, fade: 0.2)
        tiles.forEach { $0.resetRuntime() }
        mechanisms.forEach { $0.resetRuntime() }
        targets.forEach { $0.resetRuntime() }
        objectiveEvaluator.resetRuntime()
        timeController.reset()
    }

    func tearDown() {
        setPaused(true)
        eventBus.reset()
        effects.clear()
        AudioService.shared.setFreezeLayer(false, fade: 0.2)
        tiles.forEach { $0.removeAllActions(); $0.removeFromParent() }
        mechanisms.forEach { $0.removeAllActions(); $0.removeFromParent() }
        targets.forEach { $0.removeAllActions(); $0.removeFromParent() }
        tiles.removeAll()
        mechanisms.removeAll()
        targets.removeAll()
        removeAllActions()
        removeAllChildren()
    }

    func tile(id: String) -> MahjongTileNode? { tiles.first { $0.objectID == id } }
    func mechanism(id: String) -> BaseMechanismNode? { mechanisms.first { $0.mechanismID == id } }
    func target(id: String) -> TargetNode? { targets.first { $0.targetID == id } }

    func frozenInteractable(at point: CGPoint) -> FrozenInteractable? {
        guard timeController.state == .frozen else { return nil }
        let tileCandidates = tiles.filter { $0.canInteractWhenFrozen && $0.containsWorldPoint(point) }
        if let closest = tileCandidates.min(by: { $0.position.distance(to: point) < $1.position.distance(to: point) }) { return closest }
        return mechanisms
            .filter { $0.canInteractWhenFrozen && $0.containsWorldPoint(point) }
            .min(by: { $0.position.distance(to: point) < $1.position.distance(to: point) })
    }

    func conveyorVelocity(at point: CGPoint) -> CGPoint {
        mechanisms.compactMap { $0 as? ConveyorNode }.first { $0.containsRegion(point) }?.velocity ?? .zero
    }

    func magneticForce(on tile: MahjongTileNode) -> CGPoint {
        mechanisms.compactMap { $0 as? MagnetNode }.reduce(.zero) { $0 + $1.force(on: tile) }
    }

    func environmentForce(on tile: MahjongTileNode) -> CGPoint {
        magneticForce(on: tile)
    }

    func captureSnapshot() -> TimeSnapshot {
        TimeSnapshot(
            simulationTime: timeController.clock.simulationTime,
            worldTime: timeController.clock.worldTime,
            timeState: timeController.state,
            freezeEnergy: timeController.energy,
            freezeCount: timeController.freezeCount,
            objectStates: tiles.map { $0.captureSnapshot() },
            mechanismStates: mechanisms.map { $0.captureMechanismSnapshot() },
            objectiveStates: objectiveEvaluator.snapshots()
        )
    }

    func restoreSnapshot(_ snapshot: TimeSnapshot) {
        for state in snapshot.objectStates { tile(id: state.id)?.restoreSnapshot(state) }
        for state in snapshot.mechanismStates { mechanism(id: state.id)?.restoreMechanismSnapshot(state) }
        objectiveEvaluator.restore(snapshot.objectiveStates)
        timeController.restore(from: snapshot)
        isComplete = false
        isFailed = false
    }

    func timeController(_ controller: TimeController, didChange state: TimeState) {
        for tile in tiles {
            if state == .frozen { tile.setSelected(false, frozen: true) }
        }
        delegate?.gameWorld(self, timeStateChanged: state)
    }

    func timeController(_ controller: TimeController, energyChanged energy: CGFloat) {
        delegate?.gameWorld(self, energyChanged: energy)
    }

    func timeControllerDidExhaustEnergy(_ controller: TimeController) {
        HapticService.shared.play(.warning)
    }

    private func buildBoard() {
        let boardPath = GameTheme.chamferedPath(size: boardRect.size, cut: 13)
        let shadow = SKShapeNode(path: boardPath)
        shadow.fillColor = UIColor.black.withAlphaComponent(0.45)
        shadow.strokeColor = .clear
        shadow.position.y = -7
        shadow.zPosition = -12
        worldContent.addChild(shadow)
        let board = SKShapeNode(path: boardPath)
        board.name = "boardSurface"
        board.fillColor = GameTheme.board
        board.strokeColor = GameTheme.freezeBlue.withAlphaComponent(0.66)
        board.lineWidth = 2
        board.glowWidth = 1
        board.zPosition = -10
        worldContent.addChild(board)
        let innerSize = CGSize(width: boardRect.width - 14, height: boardRect.height - 14)
        let inner = SKShapeNode(path: GameTheme.chamferedPath(size: innerSize, cut: 9))
        inner.fillColor = .clear
        inner.strokeColor = GameTheme.freezeWhite.withAlphaComponent(0.08)
        inner.lineWidth = 1
        inner.zPosition = -9
        worldContent.addChild(inner)
        for corner in [CGPoint(x: -1, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1)] {
            let marker = SKShapeNode(rectOf: CGSize(width: 18, height: 3))
            marker.fillColor = corner.x == corner.y ? GameTheme.vermilion : GameTheme.brassLight
            marker.strokeColor = .clear
            marker.position = CGPoint(
                x: corner.x * (boardRect.width / 2 - 24),
                y: corner.y * (boardRect.height / 2 - 6)
            )
            marker.zPosition = -8
            worldContent.addChild(marker)
        }
        buildBoardTexture()
    }

    private func buildBoardTexture() {
        let gridSpacing: CGFloat = 34
        var x = boardRect.minX + gridSpacing
        while x < boardRect.maxX {
            let line = SKShapeNode(rectOf: CGSize(width: 0.7, height: boardRect.height - 14))
            line.fillColor = GameTheme.freezeBlue.withAlphaComponent(0.035)
            line.strokeColor = .clear
            line.position.x = x
            line.zPosition = -8
            worldContent.addChild(line)
            x += gridSpacing
        }
        var y = boardRect.minY + gridSpacing
        while y < boardRect.maxY {
            let line = SKShapeNode(rectOf: CGSize(width: boardRect.width - 14, height: 0.7))
            line.fillColor = GameTheme.freezeBlue.withAlphaComponent(0.035)
            line.strokeColor = .clear
            line.position.y = y
            line.zPosition = -8
            worldContent.addChild(line)
            y += gridSpacing
        }
        for index in 0..<20 {
            let fleck = SKShapeNode(circleOfRadius: CGFloat(index % 2 + 1) * 0.45)
            fleck.fillColor = index % 3 == 0 ? GameTheme.vermilion.withAlphaComponent(0.16) : GameTheme.freezeBlue.withAlphaComponent(0.08)
            fleck.strokeColor = .clear
            fleck.position = CGPoint(
                x: boardRect.minX + CGFloat((index * 61) % Int(boardRect.width)),
                y: boardRect.minY + CGFloat((index * 97) % Int(boardRect.height))
            )
            fleck.zPosition = -7
            worldContent.addChild(fleck)
        }
    }

    private func buildObjects() {
        targets = definition.targets.map { TargetNode(definition: $0) }
        targets.forEach(worldContent.addChild)
        mechanisms = definition.mechanisms.map { MechanismNodeFactory.make($0) }
        mechanisms.forEach(worldContent.addChild)
        tiles = definition.tiles.map { MahjongTileNode(definition: $0) }
        tiles.forEach(worldContent.addChild)
    }

    private func attachEventRouting() {
        eventToken = eventBus.subscribe(owner: self) { [weak self] event in
            guard let self else { return }
            for mechanism in mechanisms { mechanism.receive(event: event, world: self) }
            switch event {
            case .levelCompleted:
                completeLevel()
            case let .levelFailed(reason):
                failLevel(reason)
            case let .tileDestroyed(_, reason):
                if definition.rules.failWhenTileLeavesBoard { failLevel(reason) }
            default: break
            }
        }
    }

    private func completeLevel() {
        guard !isComplete, !isFailed else { return }
        isComplete = true
        timeController.clock.setState(.frozen)
        HapticService.shared.play(.success)
        AudioService.shared.finishLevel(success: true)
        delegate?.gameWorldDidComplete(self)
    }

    private func failLevel(_ reason: FailureKind) {
        guard !isComplete, !isFailed else { return }
        isFailed = true
        timeController.clock.setState(.frozen)
        HapticService.shared.play(.failure)
        AudioService.shared.finishLevel(success: false)
        delegate?.gameWorld(self, didFail: reason)
    }

    private func updateFailureRules() {
        let maxTime = definition.rules.maxWorldTime
        if maxTime > 0, timeController.clock.worldTime > TimeInterval(maxTime) {
            eventBus.publish(.levelFailed(.worldTimeExpired))
        }
    }

    private func captureSnapshotIfNeeded() {
        let delta = timeController.clock.simulationDelta
        guard delta > 0, timeline.shouldCapture(delta: delta) else { return }
        timeline.append(captureSnapshot())
    }

    private func updateRewind(deltaTime: TimeInterval) {
        rewindAccumulator += deltaTime
        guard rewindAccumulator >= 0.06 else { return }
        rewindAccumulator = 0
        guard let snapshot = timeline.popPrevious(before: timeController.clock.simulationTime, step: 0.14) else {
            timeController.endRewind()
            return
        }
        restoreSnapshot(snapshot)
        timeController.clock.setState(.rewinding)
    }

    private func reportObjectiveProgress() {
        let progress = objectiveEvaluator.requiredProgress
        if abs(progress - priorObjectiveProgress) > 0.005 {
            priorObjectiveProgress = progress
            delegate?.gameWorld(self, objectiveProgressChanged: progress)
        }
    }

    private func updateTimeZones() {
        let selective = mechanisms.compactMap { $0 as? TimeZoneNode }.filter { $0.definition.kind == .partialFreezeZone }
        var teams: Set<TileTeam> = []
            for zone in selective where tiles.contains(where: { zone.containsRegion($0.position) }) {
            teams.formUnion(zone.definition.selectiveTeams)
        }
        timeController.setSelectiveTeams(teams)
        let reverseZones = mechanisms.compactMap { $0 as? TimeZoneNode }.filter { $0.definition.kind == .reverseZone }
        if timeController.state == .frozen {
            for zone in reverseZones {
                for tile in tiles where zone.containsRegion(tile.position) {
                    if let snapshot = timeline.popPrevious(before: timeController.clock.simulationTime, step: 0.04),
                       let state = snapshot.objectStates.first(where: { $0.id == tile.objectID }) {
                        tile.restoreSnapshot(state)
                    }
                }
            }
        }
    }

    private func isPointBlockedFromFreezing(_ point: CGPoint) -> Bool {
        mechanisms.compactMap { $0 as? TimeZoneNode }.contains {
            $0.definition.kind == .noFreezeZone && $0.containsRegion(point)
        }
    }
}
