import SpriteKit
import UIKit

final class TargetNode: SKNode {
    let definition: TargetDefinition
    let targetID: String
    private let outer: SKShapeNode
    private let inner: SKShapeNode
    private let label: SKLabelNode
    private(set) var occupantIDs: Set<String> = []
    private var holdTimes: [String: CGFloat] = [:]
    private(set) var isSatisfied = false

    init(definition: TargetDefinition) {
        self.definition = definition
        targetID = definition.id
        outer = SKShapeNode(circleOfRadius: definition.radius)
        inner = SKShapeNode(circleOfRadius: definition.radius - 6)
        label = GameTheme.label("TARGET", size: 7, color: GameTheme.brassLight, weight: .bold)
        super.init()
        name = "target:\(definition.id)"
        position = definition.position.cgPoint
        zPosition = 4
        outer.fillColor = GameTheme.brass.withAlphaComponent(0.06)
        outer.strokeColor = GameTheme.brass
        outer.lineWidth = 2
        outer.glowWidth = 2
        addChild(outer)
        inner.fillColor = GameTheme.boardDark.withAlphaComponent(0.6)
        inner.strokeColor = GameTheme.brass.withAlphaComponent(0.38)
        inner.lineWidth = 1
        addChild(inner)
        label.position.y = -definition.radius - 10
        addChild(label)
        let crossHorizontal = SKShapeNode(rectOf: CGSize(width: definition.radius * 0.8, height: 1))
        crossHorizontal.fillColor = GameTheme.brass.withAlphaComponent(0.35)
        crossHorizontal.strokeColor = .clear
        inner.addChild(crossHorizontal)
        let crossVertical = SKShapeNode(rectOf: CGSize(width: 1, height: definition.radius * 0.8))
        crossVertical.fillColor = GameTheme.brass.withAlphaComponent(0.35)
        crossVertical.strokeColor = .clear
        inner.addChild(crossVertical)
        accessibilityLabel = "Target"
    }

    required init?(coder aDecoder: NSCoder) { nil }

    func update(tiles: [MahjongTileNode], deltaTime: CGFloat, eventBus: GameEventBus) {
        var current: Set<String> = []
        var combinedWeight = 0
        for tile in tiles where !tile.isDestroyed {
            guard contains(tile) else { continue }
            if accepts(tile) {
                current.insert(tile.objectID)
                combinedWeight += tile.weight
                holdTimes[tile.objectID, default: 0] += deltaTime
                if !occupantIDs.contains(tile.objectID) {
                    eventBus.publish(.tileEnteredTarget(tileID: tile.objectID, targetID: targetID))
                }
            } else if !occupantIDs.contains(tile.objectID) {
                eventBus.publish(.levelFailed(.wrongTarget))
            }
        }
        for departed in occupantIDs.subtracting(current) {
            holdTimes[departed] = nil
            eventBus.publish(.tileExitedTarget(tileID: departed, targetID: targetID))
        }
        occupantIDs = current
        let durationMet = current.contains { holdTimes[$0, default: 0] >= definition.holdDuration }
        let weightMet = combinedWeight >= definition.requiredWeight
        let newSatisfied = durationMet && weightMet
        if newSatisfied != isSatisfied {
            isSatisfied = newSatisfied
            refreshAppearance()
        }
    }

    func accepts(_ tile: MahjongTileNode) -> Bool {
        if let suit = definition.acceptsSuit, tile.suit != suit { return false }
        if let face = definition.acceptsFace, tile.face != face { return false }
        if let team = definition.acceptsTeam, tile.team != team { return false }
        return tile.definition.targetIDs.isEmpty || tile.definition.targetIDs.contains(targetID)
    }

    func contains(_ tile: MahjongTileNode) -> Bool {
        tile.position.distance(to: position) <= definition.radius - tile.collisionRadius * 0.25
    }

    func containsAccepted(_ tile: MahjongTileNode) -> Bool {
        !tile.isDestroyed && contains(tile) && accepts(tile)
    }

    func resetRuntime() {
        occupantIDs.removeAll()
        holdTimes.removeAll()
        isSatisfied = false
        removeAllActions()
        refreshAppearance()
    }

    private func refreshAppearance() {
        outer.strokeColor = isSatisfied ? GameTheme.jade : GameTheme.brass
        inner.fillColor = isSatisfied ? GameTheme.jade.withAlphaComponent(0.19) : GameTheme.boardDark.withAlphaComponent(0.6)
        label.text = isSatisfied ? "LOCKED" : "TARGET"
        label.fontColor = isSatisfied ? GameTheme.jade : GameTheme.brassLight
        if isSatisfied && !SaveStore.shared.settings.reduceMotion {
            outer.run(.sequence([.scale(to: 1.12, duration: 0.12), .scale(to: 1, duration: 0.18)]))
        }
    }
}

final class ObjectiveRuntime {
    let definition: ObjectiveDefinition
    private(set) var progress: CGFloat = 0
    private(set) var isComplete = false
    private(set) var values: [String] = []

    init(definition: ObjectiveDefinition) {
        self.definition = definition
    }

    func consume(event: GameEvent, world: GameWorld) {
        guard !isComplete else { return }
        switch definition.kind {
        case .reachTarget:
            if case let .tileEnteredTarget(tileID, targetID) = event,
               matchesRequired(tileID) || matchesRequired(targetID) {
                appendUnique(tileID)
            }
            updateCountProgress()
        case .freezeInZone:
            if case .timeFrozen = event {
                let zones = world.mechanisms.compactMap { $0 as? TimeZoneNode }.filter { $0.definition.kind == .freezeZone }
                let correctlyStoppedTile = world.targets.contains { target in
                    world.tiles.contains { tile in
                        target.containsAccepted(tile) && zones.contains { $0.containsRegion(tile.position) }
                    }
                }
                if correctlyStoppedTile { appendUnique("freeze") }
            }
            updateCountProgress()
        case .activateAll:
            if case let .mechanismActivated(id, _) = event, matchesRequired(id) { appendUnique(id) }
            updateCountProgress()
        case .orderedSwitches:
            if case let .switchActivated(id, _) = event {
                let expectedIndex = values.count
                if expectedIndex < definition.requiredIDs.count && definition.requiredIDs[expectedIndex] == id {
                    values.append(id)
                } else {
                    values.removeAll()
                    world.eventBus.publish(.sequenceReset(id: definition.id))
                }
            }
            updateCountProgress()
        case .matchingTiles:
            if case let .tileEnteredTarget(tileID, _) = event,
               let tile = world.tile(id: tileID) {
                let sameFace = world.tiles.filter { $0.face == tile.face && $0.isInsideTarget }
                values = sameFace.map(\.objectID)
            }
            updateCountProgress()
        case .sameSuit:
            if case .tileEnteredTarget = event {
                let groups = Dictionary(grouping: world.tiles.filter(\.isInsideTarget), by: \.suit)
                values = groups.values.max(by: { $0.count < $1.count })?.map(\.objectID) ?? []
            }
            updateCountProgress()
        case .totalWeight:
            if case .pressureChanged = event {
                let total = world.mechanisms.compactMap { $0 as? PressurePlateNode }.reduce(0) { $0 + $1.currentWeight }
                progress = min(1, CGFloat(total) / max(1, definition.requiredValue))
                isComplete = progress >= 1
            }
        case .protectTile:
            if case let .tileDestroyed(id, _) = event, matchesRequired(id) {
                progress = 0
                isComplete = false
            } else if world.timeController.clock.worldTime >= TimeInterval(definition.requiredValue) {
                progress = 1
                isComplete = true
            } else {
                progress = CGFloat(world.timeController.clock.worldTime) / max(0.1, definition.requiredValue)
            }
        case .simultaneousTargets:
            let satisfied = world.targets.filter(\.isSatisfied).count
            progress = min(1, CGFloat(satisfied) / CGFloat(max(1, definition.requiredCount)))
            isComplete = progress >= 1
        case .survive:
            progress = min(1, CGFloat(world.timeController.clock.worldTime) / max(0.1, definition.requiredValue))
            isComplete = progress >= 1
        }
    }

    func tick(world: GameWorld) {
        switch definition.kind {
        case .protectTile, .survive, .simultaneousTargets:
            consume(event: .tileMoved(id: "tick", position: .zero), world: world)
        default: break
        }
    }

    func captureSnapshot() -> ObjectiveSnapshot {
        ObjectiveSnapshot(id: definition.id, progress: progress, isComplete: isComplete, values: values)
    }

    func restore(_ snapshot: ObjectiveSnapshot) {
        guard snapshot.id == definition.id else { return }
        progress = snapshot.progress
        isComplete = snapshot.isComplete
        values = snapshot.values
    }

    func resetRuntime() {
        progress = 0
        isComplete = false
        values.removeAll()
    }

    private func matchesRequired(_ id: String) -> Bool {
        definition.requiredIDs.isEmpty || definition.requiredIDs.contains(id)
    }

    private func appendUnique(_ value: String) {
        if !values.contains(value) { values.append(value) }
    }

    private func updateCountProgress() {
        let required = max(1, definition.requiredCount)
        progress = min(1, CGFloat(values.count) / CGFloat(required))
        isComplete = values.count >= required
    }
}

final class ObjectiveEvaluator {
    private(set) var objectives: [ObjectiveRuntime]
    private let eventBus: GameEventBus
    private var token: GameEventBus.Token?
    private weak var world: GameWorld?
    private var completionDispatched = false

    init(definitions: [ObjectiveDefinition], eventBus: GameEventBus) {
        objectives = definitions.map { ObjectiveRuntime(definition: $0) }
        self.eventBus = eventBus
    }

    func attach(to world: GameWorld) {
        self.world = world
        token = eventBus.subscribe(owner: self) { [weak self] event in
            self?.consume(event)
        }
    }

    func update() {
        guard let world else { return }
        for objective in objectives { objective.tick(world: world) }
        evaluateCompletion()
    }

    func resetRuntime() {
        completionDispatched = false
        objectives.forEach { $0.resetRuntime() }
    }

    func snapshots() -> [ObjectiveSnapshot] { objectives.map { $0.captureSnapshot() } }

    func restore(_ snapshots: [ObjectiveSnapshot]) {
        for snapshot in snapshots {
            objectives.first { $0.definition.id == snapshot.id }?.restore(snapshot)
        }
        completionDispatched = false
    }

    var requiredProgress: CGFloat {
        let required = objectives.filter { !$0.definition.optional }
        guard !required.isEmpty else { return 1 }
        return required.reduce(0) { $0 + $1.progress } / CGFloat(required.count)
    }

    var allRequiredComplete: Bool {
        objectives.filter { !$0.definition.optional }.allSatisfy(\.isComplete)
    }

    private func consume(_ event: GameEvent) {
        guard let world else { return }
        for objective in objectives {
            let previousProgress = objective.progress
            let wasComplete = objective.isComplete
            objective.consume(event: event, world: world)
            if objective.isComplete && !wasComplete {
                eventBus.publish(.objectiveCompleted(id: objective.definition.id))
            } else if abs(objective.progress - previousProgress) > 0.0001 {
                eventBus.publish(.objectiveProgress(id: objective.definition.id, progress: objective.progress))
            }
        }
        evaluateCompletion()
    }

    private func evaluateCompletion() {
        guard allRequiredComplete, !completionDispatched else { return }
        completionDispatched = true
        eventBus.publish(.levelCompleted)
    }
}
