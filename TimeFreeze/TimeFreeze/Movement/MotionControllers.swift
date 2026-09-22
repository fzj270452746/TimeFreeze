import CoreGraphics
import Foundation
import SpriteKit

protocol MotionController: AnyObject {
    var velocity: CGPoint { get }
    var elapsed: CGFloat { get }
    func update(tile: MahjongTileNode, deltaTime: CGFloat, world: GameWorld)
    func reset(tile: MahjongTileNode)
    func setElapsed(_ value: CGFloat)
}

enum MotionControllerFactory {
    static func make(definition: MotionDefinition, start: CGPoint) -> MotionController {
        switch definition.type {
        case .stationary:
            return StationaryMotion()
        case .linear:
            return LinearMotion(definition: definition, start: start)
        case .pingPong:
            return PingPongMotion(definition: definition, start: start)
        case .orbit:
            return OrbitMotion(definition: definition, start: start)
        case .rail:
            return RailMotion(definition: definition, start: start)
        case .gravity:
            return GravityMotion(definition: definition, start: start)
        case .conveyor:
            return ConveyorMotion(definition: definition, start: start)
        case .magnetic:
            return MagneticMotion(definition: definition, start: start)
        case .pendulum:
            return PendulumMotion(definition: definition, start: start)
        case .projectile:
            return ProjectileMotion(definition: definition, start: start)
        }
    }
}

final class StationaryMotion: MotionController {
    var velocity: CGPoint = .zero
    var elapsed: CGFloat = 0
    func update(tile: MahjongTileNode, deltaTime: CGFloat, world: GameWorld) { elapsed += deltaTime }
    func reset(tile: MahjongTileNode) { velocity = .zero; elapsed = 0 }
    func setElapsed(_ value: CGFloat) { elapsed = value }
}

final class LinearMotion: MotionController {
    private let definition: MotionDefinition
    private let start: CGPoint
    private let end: CGPoint
    var velocity: CGPoint = .zero
    var elapsed: CGFloat = 0

    init(definition: MotionDefinition, start: CGPoint) {
        self.definition = definition
        self.start = start
        end = definition.points.last?.cgPoint ?? CGPoint(x: start.x + 180, y: start.y)
    }

    func update(tile: MahjongTileNode, deltaTime: CGFloat, world: GameWorld) {
        guard deltaTime > 0 else { return }
        let old = tile.position
        elapsed += deltaTime
        let distance = start.distance(to: end)
        let duration = definition.duration > 0 ? definition.duration : distance / max(1, definition.speed)
        var progress = elapsed / max(0.01, duration)
        if definition.repeats {
            progress.formTruncatingRemainder(dividingBy: 1)
        } else {
            progress = min(1, progress)
        }
        tile.position = start.lerped(to: end, t: ScalarMath.ease(definition.curve, progress))
        velocity = (tile.position - old) / deltaTime
        if !definition.repeats && progress >= 1 { tile.motionDidFinish() }
    }

    func reset(tile: MahjongTileNode) {
        elapsed = 0
        velocity = .zero
        tile.position = start
    }

    func setElapsed(_ value: CGFloat) { elapsed = value }
}

final class PingPongMotion: MotionController {
    private let definition: MotionDefinition
    private let start: CGPoint
    private let end: CGPoint
    var velocity: CGPoint = .zero
    var elapsed: CGFloat = 0

    init(definition: MotionDefinition, start: CGPoint) {
        self.definition = definition
        self.start = start
        end = definition.points.last?.cgPoint ?? CGPoint(x: start.x + 160, y: start.y)
    }

    func update(tile: MahjongTileNode, deltaTime: CGFloat, world: GameWorld) {
        guard deltaTime > 0 else { return }
        let old = tile.position
        elapsed += deltaTime
        let distance = start.distance(to: end)
        let duration = definition.duration > 0 ? definition.duration : distance / max(1, definition.speed)
        let phase = ScalarMath.pingPong(elapsed / max(duration, 0.01), length: 1)
        tile.position = start.lerped(to: end, t: ScalarMath.ease(definition.curve, phase))
        velocity = (tile.position - old) / deltaTime
    }

    func reset(tile: MahjongTileNode) {
        elapsed = 0
        velocity = .zero
        tile.position = start
    }

    func setElapsed(_ value: CGFloat) { elapsed = value }
}

final class OrbitMotion: MotionController {
    private let definition: MotionDefinition
    private let center: CGPoint
    private let start: CGPoint
    private let angularSpeed: CGFloat
    var velocity: CGPoint = .zero
    var elapsed: CGFloat = 0

    init(definition: MotionDefinition, start: CGPoint) {
        self.definition = definition
        self.start = start
        center = definition.points.first?.cgPoint ?? CGPoint(x: start.x - definition.radius, y: start.y)
        angularSpeed = (definition.clockwise ? -1 : 1) * 2 * .pi / max(0.5, definition.duration)
    }

    func update(tile: MahjongTileNode, deltaTime: CGFloat, world: GameWorld) {
        guard deltaTime > 0 else { return }
        let old = tile.position
        elapsed += deltaTime
        let initialAngle = (start - center).angle + definition.phase
        let angle = initialAngle + angularSpeed * elapsed
        let radius = definition.radius > 0 ? definition.radius : start.distance(to: center)
        tile.position = center + CGPoint(x: cos(angle), y: sin(angle)) * radius
        tile.zRotation = angle + (definition.clockwise ? -.pi / 2 : .pi / 2)
        velocity = (tile.position - old) / deltaTime
    }

    func reset(tile: MahjongTileNode) {
        elapsed = 0
        velocity = .zero
        tile.position = start
    }

    func setElapsed(_ value: CGFloat) { elapsed = value }
}

final class RailMotion: MotionController {
    private let definition: MotionDefinition
    private let points: [CGPoint]
    private let segmentLengths: [CGFloat]
    private let totalLength: CGFloat
    private let start: CGPoint
    var velocity: CGPoint = .zero
    var elapsed: CGFloat = 0

    init(definition: MotionDefinition, start: CGPoint) {
        self.definition = definition
        self.start = start
        let configured = definition.points.map(\.cgPoint)
        points = configured.count >= 2 ? configured : [start, CGPoint(x: start.x + 100, y: start.y), CGPoint(x: start.x + 100, y: start.y + 100)]
        var lengths: [CGFloat] = []
        for index in 1..<points.count { lengths.append(points[index - 1].distance(to: points[index])) }
        segmentLengths = lengths
        totalLength = max(1, lengths.reduce(0, +))
    }

    func update(tile: MahjongTileNode, deltaTime: CGFloat, world: GameWorld) {
        guard deltaTime > 0 else { return }
        let old = tile.position
        elapsed += deltaTime
        var travel = elapsed * definition.speed
        if definition.repeats { travel.formTruncatingRemainder(dividingBy: totalLength) }
        else { travel = min(totalLength, travel) }
        var remaining = travel
        for index in segmentLengths.indices {
            if remaining <= segmentLengths[index] || index == segmentLengths.count - 1 {
                let t = ScalarMath.clamp(remaining / max(0.01, segmentLengths[index]), 0, 1)
                tile.position = points[index].lerped(to: points[index + 1], t: ScalarMath.ease(definition.curve, t))
                tile.zRotation = (points[index + 1] - points[index]).angle
                break
            }
            remaining -= segmentLengths[index]
        }
        velocity = (tile.position - old) / deltaTime
        if !definition.repeats && travel >= totalLength { tile.motionDidFinish() }
    }

    func reset(tile: MahjongTileNode) {
        elapsed = 0
        velocity = .zero
        tile.position = points.first ?? start
    }

    func setElapsed(_ value: CGFloat) { elapsed = value }
}

final class GravityMotion: MotionController {
    private let definition: MotionDefinition
    private let start: CGPoint
    private var accumulatedVelocity: CGPoint
    var velocity: CGPoint { accumulatedVelocity }
    var elapsed: CGFloat = 0

    init(definition: MotionDefinition, start: CGPoint) {
        self.definition = definition
        self.start = start
        accumulatedVelocity = definition.points.first?.cgPoint ?? .zero
    }

    func update(tile: MahjongTileNode, deltaTime: CGFloat, world: GameWorld) {
        guard deltaTime > 0 else { return }
        elapsed += deltaTime
        accumulatedVelocity = accumulatedVelocity + definition.acceleration.cgPoint * deltaTime
        accumulatedVelocity = accumulatedVelocity + world.environmentForce(on: tile) * deltaTime
        let proposed = tile.position + accumulatedVelocity * deltaTime
        let boardBottom = world.boardRect.minY + tile.collisionRadius
        if proposed.y < boardBottom {
            tile.position.y = boardBottom
            if definition.curve == .bounce {
                accumulatedVelocity.y = abs(accumulatedVelocity.y) * 0.68
                accumulatedVelocity.x *= 0.92
            } else {
                accumulatedVelocity.y = 0
                accumulatedVelocity.x *= 0.86
            }
        } else {
            tile.position = proposed
        }
        tile.zRotation += accumulatedVelocity.x * deltaTime * 0.002
    }

    func applyImpulse(_ impulse: CGPoint) { accumulatedVelocity = accumulatedVelocity + impulse }

    func reset(tile: MahjongTileNode) {
        elapsed = 0
        accumulatedVelocity = definition.points.first?.cgPoint ?? .zero
        tile.position = start
    }

    func setElapsed(_ value: CGFloat) { elapsed = value }
}

final class ConveyorMotion: MotionController {
    private let definition: MotionDefinition
    private let start: CGPoint
    var velocity: CGPoint = .zero
    var elapsed: CGFloat = 0

    init(definition: MotionDefinition, start: CGPoint) {
        self.definition = definition
        self.start = start
    }

    func update(tile: MahjongTileNode, deltaTime: CGFloat, world: GameWorld) {
        guard deltaTime > 0 else { return }
        elapsed += deltaTime
        let baseDirection = definition.points.first?.cgPoint.normalized ?? CGPoint(x: 1, y: 0)
        let conveyor = world.conveyorVelocity(at: tile.position)
        velocity = conveyor.lengthSquared > 0 ? conveyor : baseDirection * definition.speed
        tile.position = tile.position + velocity * deltaTime
        if velocity.length > 1 { tile.zRotation = velocity.angle }
    }

    func reset(tile: MahjongTileNode) {
        elapsed = 0
        velocity = .zero
        tile.position = start
    }

    func setElapsed(_ value: CGFloat) { elapsed = value }
}

final class MagneticMotion: MotionController {
    private let definition: MotionDefinition
    private let start: CGPoint
    private var currentVelocity = CGPoint.zero
    var velocity: CGPoint { currentVelocity }
    var elapsed: CGFloat = 0

    init(definition: MotionDefinition, start: CGPoint) {
        self.definition = definition
        self.start = start
    }

    func update(tile: MahjongTileNode, deltaTime: CGFloat, world: GameWorld) {
        guard deltaTime > 0 else { return }
        elapsed += deltaTime
        let attraction = world.magneticForce(on: tile)
        currentVelocity = currentVelocity + attraction * deltaTime
        currentVelocity = currentVelocity * pow(0.965, deltaTime * 60)
        if currentVelocity.length > definition.speed {
            currentVelocity = currentVelocity.normalized * definition.speed
        }
        tile.position = tile.position + currentVelocity * deltaTime
        if currentVelocity.length > 2 { tile.zRotation = currentVelocity.angle }
    }

    func reset(tile: MahjongTileNode) {
        elapsed = 0
        currentVelocity = .zero
        tile.position = start
    }

    func setElapsed(_ value: CGFloat) { elapsed = value }
}

final class PendulumMotion: MotionController {
    private let definition: MotionDefinition
    private let pivot: CGPoint
    private let start: CGPoint
    var velocity: CGPoint = .zero
    var elapsed: CGFloat = 0

    init(definition: MotionDefinition, start: CGPoint) {
        self.definition = definition
        self.start = start
        pivot = definition.points.first?.cgPoint ?? CGPoint(x: start.x, y: start.y + definition.radius)
    }

    func update(tile: MahjongTileNode, deltaTime: CGFloat, world: GameWorld) {
        guard deltaTime > 0 else { return }
        let old = tile.position
        elapsed += deltaTime
        let period = max(0.6, definition.duration)
        let amplitude = min(.pi * 0.46, max(.pi * 0.08, definition.phase == 0 ? .pi * 0.32 : definition.phase))
        let angle = sin(elapsed / period * .pi * 2) * amplitude - .pi / 2
        let length = max(24, definition.radius)
        tile.position = pivot + CGPoint(x: cos(angle), y: sin(angle)) * length
        tile.zRotation = angle + .pi / 2
        velocity = (tile.position - old) / deltaTime
    }

    func reset(tile: MahjongTileNode) {
        elapsed = 0
        velocity = .zero
        tile.position = start
    }

    func setElapsed(_ value: CGFloat) { elapsed = value }
}

final class ProjectileMotion: MotionController {
    private let definition: MotionDefinition
    private let start: CGPoint
    private var currentVelocity: CGPoint
    var velocity: CGPoint { currentVelocity }
    var elapsed: CGFloat = 0

    init(definition: MotionDefinition, start: CGPoint) {
        self.definition = definition
        self.start = start
        currentVelocity = (definition.points.first?.cgPoint ?? CGPoint(x: 1, y: 0)).normalized * definition.speed
    }

    func update(tile: MahjongTileNode, deltaTime: CGFloat, world: GameWorld) {
        guard deltaTime > 0 else { return }
        elapsed += deltaTime
        currentVelocity = currentVelocity + definition.acceleration.cgPoint * deltaTime
        let force = world.environmentForce(on: tile)
        currentVelocity = currentVelocity + force * deltaTime
        tile.position = tile.position + currentVelocity * deltaTime
        tile.zRotation = currentVelocity.angle
    }

    func reflect(normal: CGPoint) {
        currentVelocity = currentVelocity - normal * (2 * currentVelocity.dot(normal))
    }

    func reset(tile: MahjongTileNode) {
        elapsed = 0
        currentVelocity = (definition.points.first?.cgPoint ?? CGPoint(x: 1, y: 0)).normalized * definition.speed
        tile.position = start
    }

    func setElapsed(_ value: CGFloat) { elapsed = value }
}
