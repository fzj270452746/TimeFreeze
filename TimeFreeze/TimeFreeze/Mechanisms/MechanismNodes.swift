import SpriteKit
import UIKit

class BaseMechanismNode: SKNode, MechanismRuntime, FrozenInteractable {
    let definition: MechanismDefinition
    let mechanismID: String
    let mechanismKind: MechanismKind
    var objectID: String { mechanismID }
    var isActive: Bool
    var isLocked = false
    var phase: CGFloat
    var activationCount = 0
    var occupantIDs: Set<String> = []
    var canInteractWhenFrozen: Bool { definition.canInteractWhenFrozen }

    init(definition: MechanismDefinition) {
        self.definition = definition
        mechanismID = definition.id
        mechanismKind = definition.kind
        isActive = definition.startsActive
        phase = definition.phase
        super.init()
        name = "mechanism:\(definition.id)"
        position = definition.position.cgPoint
        zRotation = definition.rotation
        zPosition = 15
        accessibilityLabel = definition.kind.rawValue
    }

    required init?(coder aDecoder: NSCoder) { nil }

    func update(deltaTime: TimeInterval, world: GameWorld) {}
    func receive(event: GameEvent, world: GameWorld) {}

    func activate(world: GameWorld) {
        guard !isLocked, !isActive else { return }
        isActive = true
        activationCount += 1
        world.eventBus.publish(.mechanismActivated(id: mechanismID, kind: mechanismKind))
        AudioService.shared.play(.switchOn)
        HapticService.shared.play(.mechanism)
    }

    func deactivate(world: GameWorld) {
        guard isActive else { return }
        isActive = false
        world.eventBus.publish(.mechanismDeactivated(id: mechanismID, kind: mechanismKind))
    }

    func containsWorldPoint(_ point: CGPoint) -> Bool {
        calculateAccumulatedFrame().insetBy(dx: -8, dy: -8).contains(point)
    }

    func beginFrozenInteraction(at point: CGPoint, world: GameWorld) {}
    func continueFrozenInteraction(to point: CGPoint, world: GameWorld) {}
    func endFrozenInteraction(at point: CGPoint, world: GameWorld) {}

    func captureMechanismSnapshot() -> MechanismSnapshot {
        MechanismSnapshot(
            id: mechanismID,
            isActive: isActive,
            isLocked: isLocked,
            phase: phase,
            activationCount: activationCount,
            occupants: Array(occupantIDs)
        )
    }

    func restoreMechanismSnapshot(_ snapshot: MechanismSnapshot) {
        guard snapshot.id == mechanismID else { return }
        isActive = snapshot.isActive
        isLocked = snapshot.isLocked
        phase = snapshot.phase
        activationCount = snapshot.activationCount
        occupantIDs = Set(snapshot.occupants)
        refreshAppearance()
    }

    func resetRuntime() {
        isActive = definition.startsActive
        isLocked = false
        phase = definition.phase
        activationCount = 0
        occupantIDs.removeAll()
        removeAllActions()
        refreshAppearance()
    }

    func refreshAppearance() {}

    /// The delivered art now standing in for this mechanism's drawn body, when
    /// the asset is present in the bundle.
    private(set) var bodyArt: SKSpriteNode?

    /// Installs delivered art as this mechanism's body and hides the drawn
    /// shapes it replaces, returning nil when the asset is missing so the
    /// subclass keeps a complete drawn fallback.
    ///
    /// The art goes to `zPosition` -1: behind anything the subclass animates to
    /// report state — a gate bar, a switch lever, a portal chevron — so those
    /// keep working on top of the new body rather than being covered by it.
    @discardableResult
    func installBodyArt(_ name: String, fitting box: CGSize, stretched: Bool = false, hiding drawn: [SKNode] = []) -> SKSpriteNode? {
        let sprite = stretched
            ? GameAssets.stretchedSprite(name, size: box)
            : GameAssets.sprite(name, fitting: box)
        guard let sprite else { return nil }
        sprite.zPosition = -1
        addChild(sprite)
        drawn.forEach { $0.isHidden = true }
        bodyArt = sprite
        return sprite
    }
}

enum MechanismNodeFactory {
    static func make(_ definition: MechanismDefinition) -> BaseMechanismNode {
        switch definition.kind {
        case .gate: return TimeGateNode(definition: definition, rotating: false)
        case .rotatingGate: return TimeGateNode(definition: definition, rotating: true)
        case .switchControl: return SwitchNode(definition: definition)
        case .pressurePlate: return PressurePlateNode(definition: definition)
        case .conveyor: return ConveyorNode(definition: definition)
        case .portal: return PortalNode(definition: definition)
        case .elevator: return ElevatorNode(definition: definition)
        case .magnet: return MagnetNode(definition: definition)
        case .mirror: return MirrorNode(definition: definition)
        case .rotatingPlatform: return RotatingPlatformNode(definition: definition)
        case .pendulum: return PendulumHazardNode(definition: definition)
        case .freezeZone, .noFreezeZone, .reverseZone, .partialFreezeZone:
            return TimeZoneNode(definition: definition)
        case .hazard: return HazardNode(definition: definition)
        case .bridge: return BridgeNode(definition: definition)
        }
    }
}

final class TimeGateNode: BaseMechanismNode {
    private let rotating: Bool
    private let leftPost = SKShapeNode()
    private let rightPost = SKShapeNode()
    private let bar = SKShapeNode()
    private(set) var openness: CGFloat = 0
    private var requestedOpen: Bool?

    init(definition: MechanismDefinition, rotating: Bool) {
        self.rotating = rotating
        super.init(definition: definition)
        buildAppearance()
        refreshAppearance()
    }

    required init?(coder aDecoder: NSCoder) { nil }

    override func update(deltaTime: TimeInterval, world: GameWorld) {
        let delta = CGFloat(deltaTime)
        if definition.period > 0, requestedOpen == nil {
            phase += delta
            let cycle = sin((phase / definition.period) * .pi * 2)
            openness = ScalarMath.smoothStep((cycle + 1) / 2)
            setActiveSilently(openness > 0.58)
        } else {
            let target: CGFloat = (requestedOpen ?? isActive) ? 1 : 0
            openness += (target - openness) * min(1, delta * 6)
        }
        if rotating {
            bar.zRotation = definition.rotation + openness * .pi / 2
        } else {
            bar.yScale = max(0.05, 1 - openness)
            bar.alpha = max(0.14, 1 - openness * 0.86)
        }
        leftPost.fillColor = isActive ? GameTheme.jade : GameTheme.brass
        rightPost.fillColor = leftPost.fillColor
    }

    override func receive(event: GameEvent, world: GameWorld) {
        switch event {
        case let .switchActivated(_, channel):
            guard channel == definition.channel else { return }
            requestedOpen = true
            activate(world: world)
            world.eventBus.publish(.gateChanged(id: mechanismID, open: true))
        case let .switchDeactivated(_, channel):
            guard channel == definition.channel else { return }
            requestedOpen = false
            deactivate(world: world)
            world.eventBus.publish(.gateChanged(id: mechanismID, open: false))
        default: break
        }
    }

    override func endFrozenInteraction(at point: CGPoint, world: GameWorld) {
        guard rotating, canInteractWhenFrozen else { return }
        requestedOpen = true
        activate(world: world)
        zRotation += .pi / 2
        world.interactionCount += 1
        refreshAppearance()
    }

    func blocks(tile: MahjongTileNode) -> Bool {
        guard openness < 0.72 else { return false }
        let local = convert(tile.position, from: tile.parent ?? self)
        let half = definition.size.cgSize
        return abs(local.x) < half.width / 2 + tile.collisionRadius && abs(local.y) < half.height / 2 + tile.collisionRadius
    }

    override func refreshAppearance() {
        openness = isActive ? 1 : 0
        bar.alpha = isActive ? 0.18 : 1
    }

    private func buildAppearance() {
        let size = definition.size.cgSize
        let postSize = CGSize(width: 9, height: max(34, size.height))
        leftPost.path = CGPath(roundedRect: CGRect(x: -postSize.width / 2, y: -postSize.height / 2, width: postSize.width, height: postSize.height), cornerWidth: 3, cornerHeight: 3, transform: nil)
        rightPost.path = leftPost.path
        leftPost.strokeColor = GameTheme.brassLight
        rightPost.strokeColor = GameTheme.brassLight
        leftPost.position.x = -size.width / 2
        rightPost.position.x = size.width / 2
        addChild(leftPost)
        addChild(rightPost)
        bar.path = CGPath(roundedRect: CGRect(x: -size.width / 2, y: -4, width: size.width, height: 8), cornerWidth: 3, cornerHeight: 3, transform: nil)
        bar.fillColor = GameTheme.vermilion.blended(with: GameTheme.brass, amount: 0.55)
        bar.strokeColor = GameTheme.brassLight
        bar.lineWidth = 1
        addChild(bar)
        for x in stride(from: -size.width / 2 + 8, through: size.width / 2 - 8, by: 12) {
            let bolt = SKShapeNode(circleOfRadius: 1.4)
            bolt.fillColor = GameTheme.ink
            bolt.strokeColor = .clear
            bolt.position.x = x
            bar.addChild(bolt)
        }
        // The posts are the gate's frame and the bar is its state, so only the
        // posts give way to the art; the bar keeps swinging over it.
        installBodyArt(
            rotating ? GameAssets.Mechanic.rotatingGate : GameAssets.Mechanic.gate,
            fitting: CGSize(width: size.width + 26, height: max(40, size.height + 16)),
            hiding: [leftPost, rightPost]
        )
    }

    private func setActiveSilently(_ active: Bool) { isActive = active }
}

final class SwitchNode: BaseMechanismNode {
    private let base = SKShapeNode(circleOfRadius: 20)
    private let lever = SKShapeNode(rectOf: CGSize(width: 7, height: 27), cornerRadius: 3.5)
    private let status = SKShapeNode(circleOfRadius: 4)

    override init(definition: MechanismDefinition) {
        super.init(definition: definition)
        base.fillColor = GameTheme.boardDark
        base.strokeColor = GameTheme.brass
        base.lineWidth = 2
        addChild(base)
        lever.fillColor = GameTheme.ivoryShadow
        lever.strokeColor = GameTheme.ink
        lever.lineWidth = 1
        lever.position.y = 6
        base.addChild(lever)
        status.position = CGPoint(x: 11, y: -10)
        base.addChild(status)
        // The socket hosts the lever and the status dot, so it stays drawn as a
        // rim and only its fill drops away to let the delivered housing show.
        if installBodyArt(GameAssets.Mechanic.switchControl, fitting: CGSize(width: 50, height: 50)) != nil {
            base.fillColor = GameTheme.boardDark.withAlphaComponent(0.22)
        }
        refreshAppearance()
    }

    required init?(coder aDecoder: NSCoder) { nil }

    override func endFrozenInteraction(at point: CGPoint, world: GameWorld) {
        guard canInteractWhenFrozen, !isLocked else { return }
        if isActive {
            deactivate(world: world)
            world.eventBus.publish(.switchDeactivated(id: mechanismID, channel: definition.channel))
        } else {
            activate(world: world)
            world.eventBus.publish(.switchActivated(id: mechanismID, channel: definition.channel))
        }
        world.interactionCount += 1
        refreshAppearance()
    }

    override func refreshAppearance() {
        lever.zRotation = isActive ? -.pi / 5 : .pi / 5
        lever.fillColor = isActive ? GameTheme.brassLight : GameTheme.ivoryShadow
        status.fillColor = isActive ? GameTheme.jade : GameTheme.vermilion
        status.strokeColor = .clear
    }
}

final class PressurePlateNode: BaseMechanismNode {
    private let plate: SKShapeNode
    private let indicator = SKLabelNode()
    private(set) var currentWeight = 0

    override init(definition: MechanismDefinition) {
        plate = SKShapeNode(rectOf: definition.size.cgSize, cornerRadius: 6)
        super.init(definition: definition)
        plate.fillColor = GameTheme.boardLight
        plate.strokeColor = GameTheme.brass
        plate.lineWidth = 2
        plate.zPosition = -2
        addChild(plate)
        let inner = SKShapeNode(rectOf: CGSize(width: max(10, definition.size.width - 9), height: max(10, definition.size.height - 9)), cornerRadius: 4)
        inner.fillColor = UIColor.black.withAlphaComponent(0.14)
        inner.strokeColor = GameTheme.divider
        plate.addChild(inner)
        indicator.fontName = GameTheme.monoFont(size: 9, weight: .bold).fontName
        indicator.fontSize = 9
        indicator.verticalAlignmentMode = .center
        indicator.position.y = -definition.size.height / 2 - 10
        addChild(indicator)
        installBodyArt(GameAssets.Mechanic.pressurePlate, fitting: definition.size.cgSize, hiding: [inner])
        refreshAppearance()
    }

    required init?(coder aDecoder: NSCoder) { nil }

    override func update(deltaTime: TimeInterval, world: GameWorld) {
        let rect = CGRect(
            x: position.x - definition.size.width / 2,
            y: position.y - definition.size.height / 2,
            width: definition.size.width,
            height: definition.size.height
        )
        let occupants = world.tiles.filter { rect.insetBy(dx: -$0.collisionRadius / 2, dy: -$0.collisionRadius / 2).contains($0.position) }
        let newIDs = Set(occupants.map(\.objectID))
        let newWeight = occupants.reduce(0) { $0 + $1.weight }
        if newWeight != currentWeight || newIDs != occupantIDs {
            currentWeight = newWeight
            occupantIDs = newIDs
            let nowActive = currentWeight >= max(1, definition.threshold)
            if nowActive && !isActive {
                activate(world: world)
                world.eventBus.publish(.pressureChanged(id: mechanismID, weight: currentWeight, active: true))
                world.eventBus.publish(.switchActivated(id: mechanismID, channel: definition.channel))
            } else if !nowActive && isActive {
                deactivate(world: world)
                world.eventBus.publish(.pressureChanged(id: mechanismID, weight: currentWeight, active: false))
                world.eventBus.publish(.switchDeactivated(id: mechanismID, channel: definition.channel))
            }
            refreshAppearance()
        }
    }

    override func refreshAppearance() {
        let fill = isActive ? GameTheme.jade.blended(with: GameTheme.board, amount: 0.45) : GameTheme.boardLight
        // With art installed the drawn plate becomes a tint over the delivered
        // surface, so pressed and released still read as two different colours.
        plate.fillColor = bodyArt == nil ? fill : fill.withAlphaComponent(0.26)
        plate.yScale = isActive ? 0.92 : 1
        indicator.text = "\(currentWeight)/\(max(1, definition.threshold))"
        indicator.fontColor = isActive ? GameTheme.jade : GameTheme.textSecondary
    }
}

final class ConveyorNode: BaseMechanismNode {
    private let belt: SKShapeNode
    private var stripes: [SKShapeNode] = []
    var velocity: CGPoint {
        guard isActive else { return .zero }
        return definition.direction.cgPoint.normalized * definition.strength
    }

    override init(definition: MechanismDefinition) {
        belt = SKShapeNode(rectOf: definition.size.cgSize, cornerRadius: 5)
        super.init(definition: definition)
        belt.fillColor = GameTheme.ink
        belt.strokeColor = GameTheme.brass
        belt.lineWidth = 2
        addChild(belt)
        let count = max(2, Int(definition.size.width / 18))
        for index in 0..<count {
            let stripe = SKShapeNode(rectOf: CGSize(width: 4, height: definition.size.height - 8), cornerRadius: 2)
            stripe.fillColor = GameTheme.brass.withAlphaComponent(0.7)
            stripe.strokeColor = .clear
            stripe.position.x = -definition.size.width / 2 + 10 + CGFloat(index) * 18
            belt.addChild(stripe)
            stripes.append(stripe)
        }
        // The stripes are the moving part, so the belt stays as their container
        // and just loses its fill; dimming it still fades the stripes when off.
        // The art marks the belt's whole region, so it is stretched to it.
        if installBodyArt(GameAssets.Mechanic.conveyor, fitting: definition.size.cgSize, stretched: true) != nil {
            belt.fillColor = GameTheme.ink.withAlphaComponent(0.12)
        }
        if !definition.startsActive { setActiveForInitialization() }
        refreshAppearance()
    }

    required init?(coder aDecoder: NSCoder) { nil }

    override func update(deltaTime: TimeInterval, world: GameWorld) {
        guard isActive else { return }
        phase += CGFloat(deltaTime) * definition.strength
        let span = max(18, definition.size.width)
        for (index, stripe) in stripes.enumerated() {
            let base = -definition.size.width / 2 + 10 + CGFloat(index) * 18
            var x = base + phase.truncatingRemainder(dividingBy: 18)
            if x > definition.size.width / 2 - 4 { x -= span }
            stripe.position.x = x
        }
    }

    override func receive(event: GameEvent, world: GameWorld) {
        switch event {
        case let .switchActivated(_, channel) where channel == definition.channel:
            activate(world: world); refreshAppearance()
        case let .switchDeactivated(_, channel) where channel == definition.channel:
            deactivate(world: world); refreshAppearance()
        default: break
        }
    }

    func containsRegion(_ point: CGPoint) -> Bool {
        let local = convert(point, from: parent ?? self)
        return abs(local.x) <= definition.size.width / 2 && abs(local.y) <= definition.size.height / 2
    }

    override func refreshAppearance() {
        belt.alpha = isActive ? 1 : 0.45
        belt.strokeColor = isActive ? GameTheme.brassLight : GameTheme.textSecondary
    }

    private func setActiveForInitialization() {}
}

final class PortalNode: BaseMechanismNode {
    private let outer = SKShapeNode()
    private let inner = SKShapeNode()
    private let chevron = SKShapeNode()
    private var cooldowns: [String: CGFloat] = [:]
    var exitID: String? { definition.linkedIDs.first }

    override init(definition: MechanismDefinition) {
        super.init(definition: definition)
        let radius = min(definition.size.width, definition.size.height) / 2
        outer.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius * 0.55, width: radius * 2, height: radius * 1.1), transform: nil)
        outer.fillColor = GameTheme.freezeBlue.withAlphaComponent(0.08)
        outer.strokeColor = GameTheme.freezeBlue
        outer.lineWidth = 3
        outer.glowWidth = 4
        addChild(outer)
        inner.path = CGPath(ellipseIn: CGRect(x: -radius + 7, y: -radius * 0.38, width: (radius - 7) * 2, height: radius * 0.76), transform: nil)
        inner.fillColor = UIColor.black.withAlphaComponent(0.45)
        inner.strokeColor = GameTheme.brass.withAlphaComponent(0.65)
        inner.lineWidth = 1
        addChild(inner)
        let arrowPath = CGMutablePath()
        arrowPath.move(to: CGPoint(x: -6, y: -5))
        arrowPath.addLine(to: CGPoint(x: 6, y: 0))
        arrowPath.addLine(to: CGPoint(x: -6, y: 5))
        chevron.path = arrowPath
        chevron.strokeColor = GameTheme.freezeWhite
        chevron.lineWidth = 2
        chevron.lineCap = .round
        inner.addChild(chevron)
        // Both delivered portal plates are used, and both are parented to the
        // rings that already rotate so the portal keeps its spin: the outer
        // plate is the mouth a tile falls into, the inner one the mouth it
        // returns from. The drawn ellipses stay only as the fallback, so their
        // own paint is cleared rather than the shapes hidden, which would take
        // the art down with them.
        // Both plates are round, so their boxes are square: the drawn ellipses
        // were squashed, and fitting round art into that shape would cap it well
        // short of the portal it is standing in for.
        if let rim = GameAssets.sprite(GameAssets.Mechanic.portalIn, fitting: CGSize(width: radius * 2 + 8, height: radius * 2 + 8)) {
            rim.zPosition = -1
            outer.addChild(rim)
            outer.fillColor = .clear
            outer.strokeColor = .clear
            outer.lineWidth = 0
            outer.glowWidth = 0
        }
        if let mouth = GameAssets.sprite(GameAssets.Mechanic.portalOut, fitting: CGSize(width: (radius - 7) * 2, height: (radius - 7) * 2)) {
            mouth.zPosition = -1
            inner.addChild(mouth)
            inner.fillColor = .clear
            inner.strokeColor = .clear
            inner.lineWidth = 0
        }
        refreshAppearance()
    }

    required init?(coder aDecoder: NSCoder) { nil }

    override func update(deltaTime: TimeInterval, world: GameWorld) {
        phase += CGFloat(deltaTime)
        outer.zRotation = phase * 0.55
        inner.zRotation = -phase * 0.22
        cooldowns = cooldowns.compactMapValues { value in
            let next = value - CGFloat(deltaTime)
            return next > 0 ? next : nil
        }
        guard isActive, let exitID, let exit = world.mechanism(id: exitID) as? PortalNode else { return }
        for tile in world.tiles where cooldowns[tile.objectID] == nil && tile.position.distance(to: position) < definition.size.width * 0.36 {
            cooldowns[tile.objectID] = 0.7
            exit.cooldowns[tile.objectID] = 0.7
            world.eventBus.publish(.portalEntered(tileID: tile.objectID, portalID: mechanismID))
            let offset = exit.definition.direction.cgPoint.normalized * max(28, tile.collisionRadius * 1.8)
            tile.position = exit.position + offset
            tile.zRotation += exit.zRotation - zRotation
            world.eventBus.publish(.portalExited(tileID: tile.objectID, portalID: exit.mechanismID))
            AudioService.shared.play(.portal)
        }
    }

    override func receive(event: GameEvent, world: GameWorld) {
        switch event {
        case let .switchActivated(_, channel) where channel == definition.channel:
            activate(world: world); refreshAppearance()
        case let .switchDeactivated(_, channel) where channel == definition.channel:
            deactivate(world: world); refreshAppearance()
        default: break
        }
    }

    override func endFrozenInteraction(at point: CGPoint, world: GameWorld) {
        guard canInteractWhenFrozen else { return }
        zRotation += .pi / 2
        world.interactionCount += 1
        HapticService.shared.play(.mechanism)
    }

    override func refreshAppearance() {
        alpha = isActive ? 1 : 0.36
        chevron.alpha = isActive ? 1 : 0.2
    }
}

final class ElevatorNode: BaseMechanismNode {
    private let platform: SKShapeNode
    private let startPoint: CGPoint
    private let endPoint: CGPoint
    private var travel: CGFloat = 0

    override init(definition: MechanismDefinition) {
        startPoint = definition.position.cgPoint
        endPoint = definition.linkedIDs.first.flatMap { value -> CGPoint? in
            let parts = value.split(separator: ",").compactMap { Double($0) }
            return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
        } ?? CGPoint(x: startPoint.x, y: startPoint.y + 100)
        platform = SKShapeNode(rectOf: definition.size.cgSize, cornerRadius: 5)
        super.init(definition: definition)
        platform.fillColor = GameTheme.boardLight
        platform.strokeColor = GameTheme.brass
        platform.lineWidth = 2
        addChild(platform)
        for x in stride(from: -definition.size.width / 2 + 8, through: definition.size.width / 2 - 8, by: 12) {
            let groove = SKShapeNode(rectOf: CGSize(width: 2, height: definition.size.height - 8))
            groove.fillColor = UIColor.black.withAlphaComponent(0.2)
            groove.strokeColor = .clear
            groove.position.x = x
            platform.addChild(groove)
        }
    }

    required init?(coder aDecoder: NSCoder) { nil }

    override func update(deltaTime: TimeInterval, world: GameWorld) {
        let previous = position
        let direction: CGFloat = isActive ? 1 : -1
        travel = ScalarMath.clamp(travel + CGFloat(deltaTime) / max(0.4, definition.period) * direction, 0, 1)
        position = startPoint.lerped(to: endPoint, t: ScalarMath.smootherStep(travel))
        let displacement = position - previous
        guard displacement.lengthSquared > 0 else { return }
        let platformRect = CGRect(x: previous.x - definition.size.width / 2, y: previous.y - definition.size.height / 2 - 8, width: definition.size.width, height: definition.size.height + 16)
        for tile in world.tiles where platformRect.contains(tile.position) {
            tile.position = tile.position + displacement
        }
    }

    override func receive(event: GameEvent, world: GameWorld) {
        switch event {
        case let .switchActivated(_, channel) where channel == definition.channel: activate(world: world)
        case let .switchDeactivated(_, channel) where channel == definition.channel: deactivate(world: world)
        default: break
        }
    }
}

final class MagnetNode: BaseMechanismNode {
    private let core = SKShapeNode(circleOfRadius: 18)
    private var rings: [SKShapeNode] = []

    override init(definition: MechanismDefinition) {
        super.init(definition: definition)
        core.fillColor = GameTheme.vermilion.blended(with: GameTheme.ink, amount: 0.25)
        core.strokeColor = GameTheme.brassLight
        core.lineWidth = 2
        addChild(core)
        let north = GameTheme.label("N", size: 10, color: GameTheme.textPrimary, weight: .bold)
        north.position.x = -7
        core.addChild(north)
        let south = GameTheme.label("S", size: 10, color: GameTheme.freezeBlue, weight: .bold)
        south.position.x = 7
        core.addChild(south)
        for index in 0..<3 {
            let ring = SKShapeNode(circleOfRadius: CGFloat(27 + index * 11))
            ring.fillColor = .clear
            ring.strokeColor = GameTheme.freezeBlue.withAlphaComponent(0.24 - CGFloat(index) * 0.05)
            ring.lineWidth = 1
            addChild(ring)
            rings.append(ring)
        }
        // The core keeps its N/S letters, which carry the polarity the art
        // cannot, so only its fill drops away. The pulsing rings stay as the
        // field drawn over the delivered magnet.
        if installBodyArt(GameAssets.Mechanic.magnet, fitting: CGSize(width: 52, height: 52)) != nil {
            core.fillColor = core.fillColor.withAlphaComponent(0.2)
        }
        refreshAppearance()
    }

    required init?(coder aDecoder: NSCoder) { nil }

    override func update(deltaTime: TimeInterval, world: GameWorld) {
        phase += CGFloat(deltaTime)
        for (index, ring) in rings.enumerated() {
            ring.setScale(1 + sin(phase * 2 + CGFloat(index)) * 0.06)
        }
    }

    override func receive(event: GameEvent, world: GameWorld) {
        switch event {
        case let .switchActivated(_, channel) where channel == definition.channel: activate(world: world); refreshAppearance()
        case let .switchDeactivated(_, channel) where channel == definition.channel: deactivate(world: world); refreshAppearance()
        default: break
        }
    }

    func force(on tile: MahjongTileNode) -> CGPoint {
        guard isActive else { return .zero }
        let delta = position - tile.position
        let distance = max(18, delta.length)
        let falloff = min(1, definition.size.width * 2.6 / distance)
        let polarity: CGFloat = tile.definition.behavior == .key ? -1 : 1
        return delta.normalized * definition.strength * falloff * falloff * polarity
    }

    override func refreshAppearance() { alpha = isActive ? 1 : 0.36 }
}

final class MirrorNode: BaseMechanismNode {
    private let glass: SKShapeNode

    override init(definition: MechanismDefinition) {
        glass = SKShapeNode(rectOf: definition.size.cgSize, cornerRadius: 3)
        super.init(definition: definition)
        glass.fillColor = GameTheme.freezeBlue.withAlphaComponent(0.16)
        glass.strokeColor = GameTheme.freezeWhite
        glass.lineWidth = 2
        glass.glowWidth = 2
        addChild(glass)
        let shine = SKShapeNode(rectOf: CGSize(width: 2, height: max(8, definition.size.height - 10)))
        shine.fillColor = UIColor.white.withAlphaComponent(0.55)
        shine.strokeColor = .clear
        shine.zRotation = .pi / 10
        shine.position.x = -6
        glass.addChild(shine)
        // The whole pane is the body, highlight included, so the art replaces it
        // outright; its rotation still reads because the node itself turns.
        installBodyArt(GameAssets.Mechanic.mirror, fitting: definition.size.cgSize, hiding: [glass])
    }

    required init?(coder aDecoder: NSCoder) { nil }

    override func endFrozenInteraction(at point: CGPoint, world: GameWorld) {
        guard canInteractWhenFrozen else { return }
        zRotation += .pi / 4
        world.interactionCount += 1
        HapticService.shared.play(.mechanism)
    }

    func collisionNormal(for tile: MahjongTileNode) -> CGPoint? {
        let local = convert(tile.position, from: tile.parent ?? self)
        guard abs(local.x) < definition.size.width / 2 + tile.collisionRadius,
              abs(local.y) < definition.size.height / 2 + tile.collisionRadius else { return nil }
        return CGPoint(x: -sin(zRotation), y: cos(zRotation)).normalized
    }
}

final class RotatingPlatformNode: BaseMechanismNode {
    private let disc: SKShapeNode
    private var priorRotation: CGFloat = 0

    override init(definition: MechanismDefinition) {
        disc = SKShapeNode(circleOfRadius: min(definition.size.width, definition.size.height) / 2)
        super.init(definition: definition)
        disc.fillColor = GameTheme.boardLight
        disc.strokeColor = GameTheme.brass
        disc.lineWidth = 3
        addChild(disc)
        for index in 0..<8 {
            let spoke = SKShapeNode(rectOf: CGSize(width: definition.size.width * 0.38, height: 2), cornerRadius: 1)
            spoke.fillColor = GameTheme.brass.withAlphaComponent(0.6)
            spoke.strokeColor = .clear
            spoke.position = CGPoint(x: definition.size.width * 0.19, y: 0).rotated(by: CGFloat(index) * .pi / 4)
            spoke.zRotation = CGFloat(index) * .pi / 4
            disc.addChild(spoke)
        }
        // The spokes exist to make the spin visible, and the delivered disc
        // turns with the node itself, so they go with the disc they decorate.
        installBodyArt(GameAssets.Mechanic.rotatingPlatform, fitting: definition.size.cgSize, hiding: [disc])
    }

    required init?(coder aDecoder: NSCoder) { nil }

    override func update(deltaTime: TimeInterval, world: GameWorld) {
        guard isActive else { return }
        priorRotation = zRotation
        zRotation += CGFloat(deltaTime) * definition.strength * .pi / 180
        let rotationDelta = zRotation - priorRotation
        let radius = definition.size.width / 2
        for tile in world.tiles where tile.position.distance(to: position) < radius {
            let offset = tile.position - position
            tile.position = position + offset.rotated(by: rotationDelta)
            tile.zRotation += rotationDelta
        }
    }

    override func receive(event: GameEvent, world: GameWorld) {
        switch event {
        case let .switchActivated(_, channel) where channel == definition.channel: activate(world: world)
        case let .switchDeactivated(_, channel) where channel == definition.channel: deactivate(world: world)
        default: break
        }
    }

    override func endFrozenInteraction(at point: CGPoint, world: GameWorld) {
        guard canInteractWhenFrozen else { return }
        zRotation += .pi / 4
        world.interactionCount += 1
        HapticService.shared.play(.mechanism)
    }
}

final class PendulumHazardNode: BaseMechanismNode {
    private let pivot = SKShapeNode(circleOfRadius: 7)
    private let arm = SKShapeNode(rectOf: CGSize(width: 3, height: 86), cornerRadius: 1.5)
    private let weight = SKShapeNode(circleOfRadius: 17)
    private(set) var weightWorldPosition = CGPoint.zero

    override init(definition: MechanismDefinition) {
        super.init(definition: definition)
        pivot.fillColor = GameTheme.brass
        pivot.strokeColor = GameTheme.brassLight
        addChild(pivot)
        arm.fillColor = GameTheme.brass
        arm.strokeColor = .clear
        arm.position.y = -43
        pivot.addChild(arm)
        weight.fillColor = GameTheme.vermilion.blended(with: GameTheme.ink, amount: 0.35)
        weight.strokeColor = GameTheme.brassLight
        weight.lineWidth = 2
        weight.position.y = -43
        arm.addChild(weight)
        // The arm and weight are the hazard, so they are never replaced. The art
        // becomes the mount the pendulum hangs from, which sits behind the pivot
        // and therefore stays still while the arm swings.
        installBodyArt(GameAssets.Mechanic.pendulum, fitting: CGSize(width: 68, height: 68))
    }

    required init?(coder aDecoder: NSCoder) { nil }

    override func update(deltaTime: TimeInterval, world: GameWorld) {
        guard isActive else { return }
        phase += CGFloat(deltaTime)
        let amplitude = max(0.2, min(1.1, definition.strength / 100))
        pivot.zRotation = sin(phase * .pi * 2 / max(0.6, definition.period)) * amplitude
        weightWorldPosition = convert(weight.position, from: arm)
    }

    func collides(with tile: MahjongTileNode) -> Bool {
        tile.position.distance(to: weightWorldPosition) < tile.collisionRadius + 17
    }
}

final class TimeZoneNode: BaseMechanismNode {
    private let zone: SKShapeNode

    override init(definition: MechanismDefinition) {
        zone = SKShapeNode(rectOf: definition.size.cgSize, cornerRadius: 10)
        super.init(definition: definition)
        let color: UIColor
        switch definition.kind {
        case .freezeZone: color = GameTheme.freezeBlue
        case .noFreezeZone: color = GameTheme.vermilion
        case .reverseZone: color = GameTheme.brassLight
        case .partialFreezeZone: color = GameTheme.jade
        default: color = GameTheme.textSecondary
        }
        zone.fillColor = color.withAlphaComponent(0.07)
        zone.strokeColor = color.withAlphaComponent(0.7)
        zone.lineWidth = 1.5
        addChild(zone)
        let badge = GameTheme.label(zoneLabel, size: 8, color: color, weight: .bold)
        badge.position.y = definition.size.height / 2 - 10
        addChild(badge)
        let art: String
        switch definition.kind {
        case .noFreezeZone: art = GameAssets.Mechanic.noFreezeZone
        case .reverseZone: art = GameAssets.Mechanic.reverseZone
        case .partialFreezeZone: art = GameAssets.Mechanic.partialFreezeZone
        default: art = GameAssets.Mechanic.freezeZone
        }
        // Each zone kind has its own plate. The drawn tint and the badge both
        // stay, so the rule is stated twice and survives a faded backdrop.
        installBodyArt(art, fitting: definition.size.cgSize)
    }

    required init?(coder aDecoder: NSCoder) { nil }

    var zoneLabel: String {
        switch definition.kind {
        case .freezeZone: return "FREEZE"
        case .noFreezeZone: return "NO FREEZE"
        case .reverseZone: return "REVERSE"
        case .partialFreezeZone: return "SELECTIVE"
        default: return "ZONE"
        }
    }

    func containsRegion(_ point: CGPoint) -> Bool {
        abs(point.x - position.x) <= definition.size.width / 2 && abs(point.y - position.y) <= definition.size.height / 2
    }
}

final class HazardNode: BaseMechanismNode {
    private let hazard: SKShapeNode

    override init(definition: MechanismDefinition) {
        hazard = SKShapeNode(rectOf: definition.size.cgSize, cornerRadius: 4)
        super.init(definition: definition)
        hazard.fillColor = GameTheme.vermilion.withAlphaComponent(0.13)
        hazard.strokeColor = GameTheme.vermilion
        hazard.lineWidth = 1.5
        addChild(hazard)
        let count = max(1, Int(definition.size.width / 18))
        for index in 0..<count {
            let slash = SKShapeNode(rectOf: CGSize(width: 2, height: definition.size.height * 0.7))
            slash.fillColor = GameTheme.warning.withAlphaComponent(0.8)
            slash.strokeColor = .clear
            slash.zRotation = -.pi / 4
            slash.position.x = -definition.size.width / 2 + 9 + CGFloat(index) * 18
            hazard.addChild(slash)
        }
        // The plate and its stripes are one object, so the art replaces both and
        // takes over the warning pulse below.
        installBodyArt(GameAssets.Mechanic.hazard, fitting: definition.size.cgSize, hiding: [hazard])
    }

    required init?(coder aDecoder: NSCoder) { nil }

    override func update(deltaTime: TimeInterval, world: GameWorld) {
        phase += CGFloat(deltaTime)
        let pulse = 0.7 + sin(phase * 5) * 0.2
        if let bodyArt {
            bodyArt.alpha = pulse
        } else {
            hazard.alpha = pulse
        }
    }

    func collides(with tile: MahjongTileNode) -> Bool {
        abs(tile.position.x - position.x) < definition.size.width / 2 + tile.collisionRadius * 0.55 &&
        abs(tile.position.y - position.y) < definition.size.height / 2 + tile.collisionRadius * 0.55
    }
}

final class BridgeNode: BaseMechanismNode {
    private let deck: SKShapeNode

    override init(definition: MechanismDefinition) {
        deck = SKShapeNode(rectOf: definition.size.cgSize, cornerRadius: 3)
        super.init(definition: definition)
        deck.fillColor = GameTheme.brass.blended(with: GameTheme.board, amount: 0.42)
        deck.strokeColor = GameTheme.brassLight
        deck.lineWidth = 1.5
        addChild(deck)
        for x in stride(from: -definition.size.width / 2 + 5, through: definition.size.width / 2 - 5, by: 10) {
            let seam = SKShapeNode(rectOf: CGSize(width: 1, height: definition.size.height - 4))
            seam.fillColor = UIColor.black.withAlphaComponent(0.22)
            seam.strokeColor = .clear
            seam.position.x = x
            deck.addChild(seam)
        }
        // Retracting the bridge is a scale on the deck, so the art has to take
        // that over rather than sit behind a slab that shrinks away from it. It
        // marks the bridge's whole span, so it is stretched to that rect.
        installBodyArt(GameAssets.Mechanic.bridge, fitting: definition.size.cgSize, stretched: true, hiding: [deck])
        refreshAppearance()
    }

    required init?(coder aDecoder: NSCoder) { nil }

    override func receive(event: GameEvent, world: GameWorld) {
        switch event {
        case let .switchActivated(_, channel) where channel == definition.channel: activate(world: world); refreshAppearance()
        case let .switchDeactivated(_, channel) where channel == definition.channel: deactivate(world: world); refreshAppearance()
        default: break
        }
    }

    override func refreshAppearance() {
        let alpha: CGFloat = isActive ? 1 : 0.18
        let scale: CGFloat = isActive ? 1 : 0.18
        if let bodyArt {
            bodyArt.alpha = alpha
            bodyArt.yScale = scale
        } else {
            deck.alpha = alpha
            deck.yScale = scale
        }
    }
}
