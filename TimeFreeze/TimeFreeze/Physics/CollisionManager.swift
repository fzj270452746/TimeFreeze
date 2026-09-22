import CoreGraphics
import Foundation
import SpriteKit

final class CollisionManager {
    private var previousPairs: Set<CollisionPair> = []

    func update(world: GameWorld) {
        guard world.definition.rules.collisionEnabled else { return }
        let activeTiles = world.tiles.filter { !$0.isDestroyed }
        var currentPairs: Set<CollisionPair> = []
        if activeTiles.count > 1 {
            for firstIndex in 0..<(activeTiles.count - 1) {
                for secondIndex in (firstIndex + 1)..<activeTiles.count {
                    let first = activeTiles[firstIndex]
                    let second = activeTiles[secondIndex]
                    if resolveTileCollision(first, second, world: world) {
                        currentPairs.insert(CollisionPair(first.objectID, second.objectID))
                    }
                }
            }
        }
        for tile in activeTiles {
            resolveBoardBounds(tile, world: world)
            resolveMechanisms(tile, world: world)
        }
        previousPairs = currentPairs
    }

    func reset() { previousPairs.removeAll() }

    private func resolveTileCollision(_ first: MahjongTileNode, _ second: MahjongTileNode, world: GameWorld) -> Bool {
        let delta = second.position - first.position
        let minimumDistance = first.collisionRadius + second.collisionRadius
        let distanceSquared = delta.lengthSquared
        guard distanceSquared > 0.0001, distanceSquared < minimumDistance * minimumDistance else { return false }
        let distance = sqrt(distanceSquared)
        let normal = delta / distance
        let penetration = minimumDistance - distance
        let totalWeight = CGFloat(max(1, first.weight + second.weight))
        first.position = first.position - normal * penetration * CGFloat(second.weight) / totalWeight
        second.position = second.position + normal * penetration * CGFloat(first.weight) / totalWeight
        let relativeVelocity = second.velocity - first.velocity
        let closingSpeed = -relativeVelocity.dot(normal)
        if closingSpeed > 0 {
            let restitution: CGFloat = first.definition.behavior == .fragile || second.definition.behavior == .fragile ? 0.2 : 0.62
            let impulseMagnitude = closingSpeed * (1 + restitution) / (1 / CGFloat(first.weight) + 1 / CGFloat(second.weight))
            first.applyImpulse(-normal * impulseMagnitude / CGFloat(first.weight))
            second.applyImpulse(normal * impulseMagnitude / CGFloat(second.weight))
            let pair = CollisionPair(first.objectID, second.objectID)
            if !previousPairs.contains(pair) {
                world.eventBus.publish(.tileCollided(firstID: first.objectID, secondID: second.objectID, impulse: impulseMagnitude))
                AudioService.shared.play(.tileCollision)
                if impulseMagnitude > 145 {
                    if first.definition.behavior == .fragile { first.destroy(reason: .fragileDestroyed, world: world) }
                    if second.definition.behavior == .fragile { second.destroy(reason: .fragileDestroyed, world: world) }
                }
            }
        }
        return true
    }

    private func resolveBoardBounds(_ tile: MahjongTileNode, world: GameWorld) {
        let bounds = world.boardRect
        let margin = tile.collisionRadius
        if bounds.insetBy(dx: -margin * 2, dy: -margin * 2).contains(tile.position) { return }
        if world.definition.rules.failWhenTileLeavesBoard {
            world.eventBus.publish(.tileLeftBoard(tileID: tile.objectID))
            world.eventBus.publish(.levelFailed(.outOfBounds))
        } else {
            tile.position = CGPoint(
                x: ScalarMath.clamp(tile.position.x, bounds.minX + margin, bounds.maxX - margin),
                y: ScalarMath.clamp(tile.position.y, bounds.minY + margin, bounds.maxY - margin)
            )
        }
    }

    private func resolveMechanisms(_ tile: MahjongTileNode, world: GameWorld) {
        for mechanism in world.mechanisms {
            if let gate = mechanism as? TimeGateNode, gate.blocks(tile: tile) {
                let localDelta = tile.position - gate.position
                let normal = abs(localDelta.x) > abs(localDelta.y)
                    ? CGPoint(x: localDelta.x >= 0 ? 1 : -1, y: 0)
                    : CGPoint(x: 0, y: localDelta.y >= 0 ? 1 : -1)
                tile.position = tile.position + normal * 3
                tile.reflect(normal: normal)
            } else if let mirror = mechanism as? MirrorNode, let normal = mirror.collisionNormal(for: tile) {
                tile.reflect(normal: normal)
                tile.position = tile.position + normal * 4
            } else if let hazard = mechanism as? HazardNode, hazard.collides(with: tile) {
                tile.destroy(reason: .hazardCollision, world: world)
                world.eventBus.publish(.levelFailed(.hazardCollision))
            } else if let pendulum = mechanism as? PendulumHazardNode, pendulum.collides(with: tile) {
                let normal = (tile.position - pendulum.weightWorldPosition).normalized
                tile.applyImpulse(normal * 180)
                if tile.definition.behavior == .fragile {
                    tile.destroy(reason: .fragileDestroyed, world: world)
                    world.eventBus.publish(.levelFailed(.fragileDestroyed))
                }
            }
        }
    }
}

private struct CollisionPair: Hashable {
    let first: String
    let second: String

    init(_ a: String, _ b: String) {
        if a < b { first = a; second = b }
        else { first = b; second = a }
    }
}

prefix func - (point: CGPoint) -> CGPoint { CGPoint(x: -point.x, y: -point.y) }
