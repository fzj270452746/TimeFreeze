import CoreGraphics
import Foundation

enum GameGestureState {
    case idle
    case pendingFreeze(start: CGPoint, timestamp: TimeInterval)
    case interacting(FrozenInteractable)
    case rewinding
}

protocol GameInputControllerDelegate: AnyObject {
    func inputControllerRequestedFreeze(at point: CGPoint)
    func inputControllerBeganRewind()
    func inputControllerEndedRewind()
}

final class GameInputController {
    private weak var world: GameWorld?
    weak var delegate: GameInputControllerDelegate?
    private(set) var state: GameGestureState = .idle
    private let dragThreshold: CGFloat = 7
    private var initialPoint = CGPoint.zero

    init(world: GameWorld) {
        self.world = world
    }

    func touchesBegan(at point: CGPoint, timestamp: TimeInterval) {
        guard let world else { return }
        initialPoint = point
        if world.timeController.state == .frozen, let interactable = world.frozenInteractable(at: point) {
            state = .interacting(interactable)
            interactable.beginFrozenInteraction(at: point, world: world)
        } else {
            state = .pendingFreeze(start: point, timestamp: timestamp)
        }
    }

    func touchesMoved(to point: CGPoint) {
        guard let world else { return }
        switch state {
        case let .interacting(interactable):
            interactable.continueFrozenInteraction(to: point, world: world)
        case let .pendingFreeze(start, timestamp):
            if point.distance(to: start) > dragThreshold, world.timeController.canRewind,
               point.x < start.x - 28 {
                state = .rewinding
                delegate?.inputControllerBeganRewind()
            } else {
                state = .pendingFreeze(start: start, timestamp: timestamp)
            }
        default: break
        }
    }

    @discardableResult
    func touchesEnded(at point: CGPoint) -> Bool {
        guard let world else { return false }
        var interactedWithFrozenObject = false
        switch state {
        case let .interacting(interactable):
            interactable.endFrozenInteraction(at: point, world: world)
            interactedWithFrozenObject = true
        case let .pendingFreeze(start, _):
            if point.distance(to: start) <= dragThreshold {
                delegate?.inputControllerRequestedFreeze(at: point)
            }
        case .rewinding:
            delegate?.inputControllerEndedRewind()
        case .idle: break
        }
        state = .idle
        return interactedWithFrozenObject
    }

    func cancel() {
        if case .rewinding = state { delegate?.inputControllerEndedRewind() }
        state = .idle
    }
}
