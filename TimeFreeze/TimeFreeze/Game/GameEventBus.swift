import CoreGraphics
import Foundation

enum GameEvent {
    case tileMoved(id: String, position: CGPoint)
    case tileEnteredTarget(tileID: String, targetID: String)
    case tileExitedTarget(tileID: String, targetID: String)
    case tileCollided(firstID: String, secondID: String, impulse: CGFloat)
    case tileLeftBoard(tileID: String)
    case tileDestroyed(tileID: String, reason: FailureKind)
    case switchActivated(id: String, channel: String)
    case switchDeactivated(id: String, channel: String)
    case pressureChanged(id: String, weight: Int, active: Bool)
    case gateChanged(id: String, open: Bool)
    case portalEntered(tileID: String, portalID: String)
    case portalExited(tileID: String, portalID: String)
    case mechanismActivated(id: String, kind: MechanismKind)
    case mechanismDeactivated(id: String, kind: MechanismKind)
    case sequenceAdvanced(id: String, step: Int)
    case sequenceReset(id: String)
    case objectiveProgress(id: String, progress: CGFloat)
    case objectiveCompleted(id: String)
    case timeFrozen(position: CGPoint)
    case timeResumed
    case timeRewound(seconds: CGFloat)
    case levelCompleted
    case levelFailed(FailureKind)
}

final class GameEventBus {
    typealias Token = UUID
    typealias Handler = (GameEvent) -> Void

    private struct Subscription {
        let token: Token
        weak var owner: AnyObject?
        let handler: Handler
    }

    private var subscriptions: [Subscription] = []
    private var queuedEvents: [GameEvent] = []
    private var isDispatching = false

    @discardableResult
    func subscribe(owner: AnyObject, handler: @escaping Handler) -> Token {
        let token = UUID()
        subscriptions.append(Subscription(token: token, owner: owner, handler: handler))
        return token
    }

    func unsubscribe(_ token: Token) {
        subscriptions.removeAll { $0.token == token }
    }

    func unsubscribe(owner: AnyObject) {
        subscriptions.removeAll { $0.owner === owner || $0.owner == nil }
    }

    func publish(_ event: GameEvent) {
        queuedEvents.append(event)
        guard !isDispatching else { return }
        isDispatching = true
        while !queuedEvents.isEmpty {
            let next = queuedEvents.removeFirst()
            subscriptions.removeAll { $0.owner == nil }
            let active = subscriptions
            for subscription in active where subscription.owner != nil {
                subscription.handler(next)
            }
        }
        isDispatching = false
    }

    func reset() {
        subscriptions.removeAll()
        queuedEvents.removeAll()
        isDispatching = false
    }
}

enum GameObjectState: String, Codable {
    case idle
    case moving
    case frozen
    case interacting
    case activated
    case disabled
    case destroyed
    case completed
}

protocol WorldObject: AnyObject {
    var objectID: String { get }
    var position: CGPoint { get set }
    var zRotation: CGFloat { get set }
    var objectState: GameObjectState { get }
    func update(deltaTime: TimeInterval, world: GameWorld)
    func resetRuntime()
    func captureSnapshot() -> ObjectSnapshot
    func restoreSnapshot(_ snapshot: ObjectSnapshot)
}

protocol FrozenInteractable: AnyObject {
    var objectID: String { get }
    var canInteractWhenFrozen: Bool { get }
    func containsWorldPoint(_ point: CGPoint) -> Bool
    func beginFrozenInteraction(at point: CGPoint, world: GameWorld)
    func continueFrozenInteraction(to point: CGPoint, world: GameWorld)
    func endFrozenInteraction(at point: CGPoint, world: GameWorld)
}

protocol MechanismRuntime: AnyObject {
    var mechanismID: String { get }
    var mechanismKind: MechanismKind { get }
    var isActive: Bool { get }
    func update(deltaTime: TimeInterval, world: GameWorld)
    func receive(event: GameEvent, world: GameWorld)
    func captureMechanismSnapshot() -> MechanismSnapshot
    func restoreMechanismSnapshot(_ snapshot: MechanismSnapshot)
}
