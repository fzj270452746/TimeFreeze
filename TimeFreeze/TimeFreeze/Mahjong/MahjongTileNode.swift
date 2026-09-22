import SpriteKit
import UIKit

final class MahjongTileNode: SKNode, WorldObject, FrozenInteractable {
    let definition: TileDefinition
    let objectID: String
    let collisionRadius: CGFloat
    let initialPosition: CGPoint
    let initialRotation: CGFloat
    private(set) var objectState: GameObjectState = .idle
    private(set) var motionController: MotionController
    private(set) var isInsideTarget = false
    private(set) var isDestroyed = false
    private(set) var isSelected = false
    private var dragOffset = CGPoint.zero
    private var lastValidPosition: CGPoint
    private var faceNode: SKNode

    var velocity: CGPoint { motionController.velocity }
    var weight: Int { definition.weight }
    var team: TileTeam { definition.team }
    var suit: MahjongSuit { definition.suit }
    var face: MahjongFace { definition.face }
    var canInteractWhenFrozen: Bool { definition.canDragWhenFrozen || definition.canRotateWhenFrozen }

    init(definition: TileDefinition) {
        self.definition = definition
        objectID = definition.id
        collisionRadius = definition.collisionRadius
        initialPosition = definition.position.cgPoint
        initialRotation = definition.rotation
        lastValidPosition = definition.position.cgPoint
        motionController = MotionControllerFactory.make(definition: definition.motion, start: definition.position.cgPoint)
        faceNode = MahjongTileRenderer.makeFaceNode(suit: definition.suit, face: definition.face, team: definition.team)
        super.init()
        name = "tile:\(definition.id)"
        position = initialPosition
        zRotation = initialRotation
        zPosition = 30
        addChild(faceNode)
        objectState = definition.motion.type == .stationary ? .idle : .moving
        accessibilityLabel = "\(definition.face.glyph) \(definition.suit.shortName) tile"
    }

    required init?(coder aDecoder: NSCoder) { nil }

    func update(deltaTime: TimeInterval, world: GameWorld) {
        guard !isDestroyed else { return }
        let delta = CGFloat(deltaTime)
        lastValidPosition = position
        if definition.behavior == .directional, definition.motion.type == .linear {
            let direction = CGPoint(x: cos(zRotation), y: sin(zRotation))
            position = position + direction * definition.motion.speed * delta
        } else {
            motionController.update(tile: self, deltaTime: delta, world: world)
        }
        applyMechanismInfluences(deltaTime: delta, world: world)
        updateShadow(for: velocity)
        world.eventBus.publish(.tileMoved(id: objectID, position: position))
    }

    func applyImpulse(_ impulse: CGPoint) {
        if let gravity = motionController as? GravityMotion {
            gravity.applyImpulse(impulse)
        } else {
            position = position + impulse * 0.016
        }
    }

    func reflect(normal: CGPoint) {
        if let projectile = motionController as? ProjectileMotion {
            projectile.reflect(normal: normal)
        } else {
            zRotation = atan2(normal.y, normal.x)
        }
    }

    func rotateQuarterTurn() {
        zRotation = ScalarMath.wrapAngle(zRotation + .pi / 2)
        if !SaveStore.shared.settings.reduceMotion {
            faceNode.run(.sequence([.scale(to: 1.08, duration: 0.08), .scale(to: 1, duration: 0.12)]))
        }
    }

    func setSelected(_ selected: Bool, frozen: Bool) {
        isSelected = selected
        MahjongTileRenderer.updateSelection(self, selected: selected, frozen: frozen)
    }

    func markInsideTarget(_ inside: Bool) {
        isInsideTarget = inside
        if inside {
            objectState = .completed
            faceNode.run(.colorize(with: GameTheme.brassLight, colorBlendFactor: 0.24, duration: 0.18))
        } else if objectState == .completed {
            objectState = .moving
            faceNode.run(.colorize(withColorBlendFactor: 0, duration: 0.12))
        }
    }

    func destroy(reason: FailureKind, world: GameWorld) {
        guard !isDestroyed else { return }
        isDestroyed = true
        objectState = .destroyed
        world.eventBus.publish(.tileDestroyed(tileID: objectID, reason: reason))
        if SaveStore.shared.settings.reduceMotion {
            alpha = 0
        } else {
            run(.group([.fadeOut(withDuration: 0.22), .scale(to: 0.3, duration: 0.22), .rotate(byAngle: .pi / 3, duration: 0.22)]))
        }
    }

    func motionDidFinish() {
        if objectState == .moving { objectState = .idle }
    }

    func resetRuntime() {
        removeAllActions()
        position = initialPosition
        zRotation = initialRotation
        alpha = 1
        setScale(1)
        isInsideTarget = false
        isDestroyed = false
        isSelected = false
        lastValidPosition = initialPosition
        motionController.reset(tile: self)
        objectState = definition.motion.type == .stationary ? .idle : .moving
        MahjongTileRenderer.updateSelection(self, selected: false, frozen: false)
    }

    func captureSnapshot() -> ObjectSnapshot {
        ObjectSnapshot(
            id: objectID,
            position: WorldPoint(position),
            velocity: WorldPoint(velocity),
            rotation: zRotation,
            motionTime: motionController.elapsed,
            state: objectState.rawValue,
            isRemoved: isDestroyed
        )
    }

    func restoreSnapshot(_ snapshot: ObjectSnapshot) {
        guard snapshot.id == objectID else { return }
        removeAllActions()
        position = snapshot.position.cgPoint
        zRotation = snapshot.rotation
        motionController.setElapsed(snapshot.motionTime)
        objectState = GameObjectState(rawValue: snapshot.state) ?? .moving
        isDestroyed = snapshot.isRemoved
        alpha = snapshot.isRemoved ? 0 : 1
        setScale(snapshot.isRemoved ? 0.3 : 1)
    }

    func containsWorldPoint(_ point: CGPoint) -> Bool {
        calculateAccumulatedFrame().insetBy(dx: -6, dy: -6).contains(point)
    }

    func beginFrozenInteraction(at point: CGPoint, world: GameWorld) {
        guard canInteractWhenFrozen else { return }
        objectState = .interacting
        setSelected(true, frozen: true)
        dragOffset = position - point
        HapticService.shared.play(.tap)
    }

    func continueFrozenInteraction(to point: CGPoint, world: GameWorld) {
        guard definition.canDragWhenFrozen else { return }
        let proposed = point + dragOffset
        let inset = world.boardRect.insetBy(dx: collisionRadius, dy: collisionRadius)
        position = CGPoint(
            x: ScalarMath.clamp(proposed.x, inset.minX, inset.maxX),
            y: ScalarMath.clamp(proposed.y, inset.minY, inset.maxY)
        )
    }

    func endFrozenInteraction(at point: CGPoint, world: GameWorld) {
        if definition.canRotateWhenFrozen && position.distance(to: lastValidPosition) < 8 {
            rotateQuarterTurn()
            world.interactionCount += 1
        } else if definition.canDragWhenFrozen {
            world.interactionCount += 1
        }
        objectState = definition.motion.type == .stationary ? .idle : .moving
        setSelected(false, frozen: true)
    }

    private func applyMechanismInfluences(deltaTime: CGFloat, world: GameWorld) {
        let conveyor = world.conveyorVelocity(at: position)
        if conveyor.lengthSquared > 0, definition.motion.type != .conveyor {
            position = position + conveyor * deltaTime
        }
        let magnet = world.magneticForce(on: self)
        if magnet.lengthSquared > 0, definition.motion.type != .magnetic {
            position = position + magnet * deltaTime * deltaTime * 0.5
        }
    }

    private func updateShadow(for velocity: CGPoint) {
        guard let shadow = faceNode.children.first else { return }
        let speed = min(1, velocity.length / 180)
        shadow.position = CGPoint(x: 2.8 + velocity.x * 0.005, y: -4 - speed * 2)
        shadow.alpha = 0.8 - speed * 0.2
    }

}
