import CoreGraphics
import Foundation

enum LevelValidationIssue: Hashable, CustomStringConvertible {
    case invalidID(Int)
    case invalidChapter(Int)
    case emptyTiles
    case emptyTargets
    case emptyObjectives
    case duplicateObjectID(String)
    case outOfBounds(id: String)
    case missingReference(owner: String, target: String)
    case invalidPortalLink(String)
    case invalidMotion(String)
    case invalidRule(String)
    case unreachableTarget(String)

    var description: String {
        switch self {
        case let .invalidID(id): return "Invalid level id \(id)"
        case let .invalidChapter(chapter): return "Invalid chapter \(chapter)"
        case .emptyTiles: return "Level has no Mahjong tiles"
        case .emptyTargets: return "Level has no targets"
        case .emptyObjectives: return "Level has no objectives"
        case let .duplicateObjectID(id): return "Duplicate object id \(id)"
        case let .outOfBounds(id): return "Object \(id) starts outside board"
        case let .missingReference(owner, target): return "\(owner) references missing \(target)"
        case let .invalidPortalLink(id): return "Portal \(id) has no valid exit"
        case let .invalidMotion(id): return "Tile \(id) has invalid motion"
        case let .invalidRule(rule): return "Invalid level rule: \(rule)"
        case let .unreachableTarget(id): return "Target \(id) has no eligible tile"
        }
    }
}

struct LevelValidationReport {
    var issues: [LevelValidationIssue]
    var warnings: [String]
    var complexityScore: Int
    var estimatedSeconds: ClosedRange<Int>

    var isValid: Bool { issues.isEmpty }
}

final class LevelValidator {
    static let shared = LevelValidator()
    private init() {}

    func validate(_ level: LevelDefinition) -> LevelValidationReport {
        var issues: [LevelValidationIssue] = []
        var warnings: [String] = []
        if level.id <= 0 { issues.append(.invalidID(level.id)) }
        if !(1...10).contains(level.chapter) && ![.daily, .endless].contains(level.mode) {
            issues.append(.invalidChapter(level.chapter))
        }
        if level.tiles.isEmpty { issues.append(.emptyTiles) }
        if level.targets.isEmpty { issues.append(.emptyTargets) }
        if level.objectives.isEmpty { issues.append(.emptyObjectives) }
        let allIDs = level.tiles.map(\.id) + level.mechanisms.map(\.id) + level.targets.map(\.id) + level.objectives.map(\.id)
        let grouped = Dictionary(grouping: allIDs, by: { $0 })
        issues.append(contentsOf: grouped.filter { $0.value.count > 1 }.map { .duplicateObjectID($0.key) })
        let bounds = CGRect(x: -level.boardSize.width / 2, y: -level.boardSize.height / 2, width: level.boardSize.width, height: level.boardSize.height)
        for tile in level.tiles where !bounds.insetBy(dx: -40, dy: -40).contains(tile.position.cgPoint) {
            issues.append(.outOfBounds(id: tile.id))
        }
        for mechanism in level.mechanisms where !bounds.insetBy(dx: -60, dy: -60).contains(mechanism.position.cgPoint) {
            issues.append(.outOfBounds(id: mechanism.id))
        }
        for target in level.targets where !bounds.contains(target.position.cgPoint) {
            issues.append(.outOfBounds(id: target.id))
        }
        let mechanismIDs = Set(level.mechanisms.map(\.id))
        let targetIDs = Set(level.targets.map(\.id))
        for mechanism in level.mechanisms {
            if mechanism.kind == .portal {
                guard let link = mechanism.linkedIDs.first, mechanismIDs.contains(link) else {
                    issues.append(.invalidPortalLink(mechanism.id))
                    continue
                }
            } else if mechanism.kind != .elevator {
                for link in mechanism.linkedIDs where !mechanismIDs.contains(link) {
                    issues.append(.missingReference(owner: mechanism.id, target: link))
                }
            }
        }
        for tile in level.tiles {
            for targetID in tile.targetIDs where !targetIDs.contains(targetID) {
                issues.append(.missingReference(owner: tile.id, target: targetID))
            }
            if tile.motion.speed < 0 || tile.motion.duration < 0 || tile.motion.radius < 0 {
                issues.append(.invalidMotion(tile.id))
            }
            if tile.motion.type == .rail && tile.motion.points.count < 2 {
                warnings.append("Rail tile \(tile.id) uses a fallback path")
            }
        }
        for target in level.targets where !level.tiles.contains(where: { accepts(target: target, tile: $0) }) {
            issues.append(.unreachableTarget(target.id))
        }
        if !level.rules.unlimitedFreeze && level.rules.freezeEnergy <= 0 {
            issues.append(.invalidRule("freeze energy must be positive"))
        }
        if level.rules.rewindEnabled && level.rules.rewindSeconds <= 0 {
            issues.append(.invalidRule("rewind duration must be positive"))
        }
        if level.rules.maxWorldTime > 0 && level.rules.maxWorldTime < 2 {
            warnings.append("World time is unusually short")
        }
        if level.objectives.contains(where: { !$0.optional && $0.kind == .freezeInZone }) &&
            !level.mechanisms.contains(where: { $0.kind == .freezeZone }) {
            issues.append(.invalidRule("freeze-window objective requires a freeze zone"))
        }
        if level.objectives.contains(where: { !$0.optional && $0.kind == .freezeInZone }) &&
            !level.tiles.contains(where: { tile in
                level.targets.contains(where: { target in
                    accepts(target: target, tile: tile) &&
                    level.mechanisms.contains(where: { mechanism in
                        guard mechanism.kind == .freezeZone else { return false }
                        return abs(target.position.x - mechanism.position.x) <= mechanism.size.width / 2 &&
                            abs(target.position.y - mechanism.position.y) <= mechanism.size.height / 2
                    })
                })
            }) {
            issues.append(.invalidRule("freeze zone does not overlap an eligible target"))
        }
        let complexity = complexityScore(for: level)
        let lower = max(5, 4 + complexity * 2)
        let upper = max(lower + 5, 12 + complexity * 5)
        return LevelValidationReport(issues: issues, warnings: warnings, complexityScore: complexity, estimatedSeconds: lower...upper)
    }

    func repaired(_ level: LevelDefinition) -> LevelDefinition {
        var copy = level
        copy.boardSize.width = max(280, copy.boardSize.width)
        copy.boardSize.height = max(400, copy.boardSize.height)
        let bounds = CGRect(x: -copy.boardSize.width / 2, y: -copy.boardSize.height / 2, width: copy.boardSize.width, height: copy.boardSize.height)
        let tileBounds = bounds.insetBy(dx: 24, dy: 31)
        for index in copy.tiles.indices {
            copy.tiles[index].position = WorldPoint(clamped(copy.tiles[index].position.cgPoint, to: tileBounds))
            copy.tiles[index].collisionRadius = ScalarMath.clamp(copy.tiles[index].collisionRadius, 10, 28)
            copy.tiles[index].weight = max(1, copy.tiles[index].weight)
            copy.tiles[index].motion.speed = max(0, copy.tiles[index].motion.speed)
            copy.tiles[index].motion.duration = max(0.1, copy.tiles[index].motion.duration)
            copy.tiles[index].motion.radius = max(0, copy.tiles[index].motion.radius)
        }
        let mechanismBounds = bounds.insetBy(dx: 12, dy: 12)
        for index in copy.mechanisms.indices {
            copy.mechanisms[index].position = WorldPoint(clamped(copy.mechanisms[index].position.cgPoint, to: mechanismBounds))
            copy.mechanisms[index].size.width = max(12, copy.mechanisms[index].size.width)
            copy.mechanisms[index].size.height = max(12, copy.mechanisms[index].size.height)
            copy.mechanisms[index].threshold = max(1, copy.mechanisms[index].threshold)
        }
        let targetBounds = bounds.insetBy(dx: 28, dy: 28)
        for index in copy.targets.indices {
            copy.targets[index].position = WorldPoint(clamped(copy.targets[index].position.cgPoint, to: targetBounds))
            copy.targets[index].radius = ScalarMath.clamp(copy.targets[index].radius, 22, 52)
            copy.targets[index].holdDuration = max(0.05, copy.targets[index].holdDuration)
        }
        let mechanismIDs = Set(copy.mechanisms.map(\.id))
        for index in copy.mechanisms.indices where copy.mechanisms[index].kind == .portal {
            let validLinks = copy.mechanisms[index].linkedIDs.filter(mechanismIDs.contains)
            if validLinks.isEmpty,
               let alternate = copy.mechanisms.first(where: { $0.kind == .portal && $0.id != copy.mechanisms[index].id }) {
                copy.mechanisms[index].linkedIDs = [alternate.id]
            } else {
                copy.mechanisms[index].linkedIDs = validLinks
            }
        }
        copy.rules.freezeEnergy = max(1, copy.rules.freezeEnergy)
        copy.rules.freezeDrainPerSecond = max(0.1, copy.rules.freezeDrainPerSecond)
        copy.rules.freezeRecoveryPerSecond = max(0, copy.rules.freezeRecoveryPerSecond)
        copy.rules.rewindSeconds = max(0.5, copy.rules.rewindSeconds)
        return copy
    }

    func complexityScore(for level: LevelDefinition) -> Int {
        let movingTiles = level.tiles.filter { $0.motion.type != .stationary }.count
        let movementKinds = Set(level.tiles.map(\.motion.type)).count
        let mechanismKinds = Set(level.mechanisms.map(\.kind)).count
        let interactive = level.tiles.filter { $0.canDragWhenFrozen || $0.canRotateWhenFrozen }.count + level.mechanisms.filter(\.canInteractWhenFrozen).count
        let timingPressure = level.rules.maxWorldTime > 0 || !level.rules.unlimitedFreeze ? 2 : 0
        let advancedTime = (level.rules.rewindEnabled ? 2 : 0) + (level.rules.slowMotionEnabled ? 1 : 0)
        let objectiveDepth = max(0, level.objectives.count - 1) + level.objectives.filter { $0.kind == .simultaneousTargets || $0.kind == .orderedSwitches }.count * 2
        return movingTiles + movementKinds + mechanismKinds + interactive + timingPressure + advancedTime + objectiveDepth
    }

    private func accepts(target: TargetDefinition, tile: TileDefinition) -> Bool {
        if let suit = target.acceptsSuit, suit != tile.suit { return false }
        if let face = target.acceptsFace, face != tile.face { return false }
        if let team = target.acceptsTeam, team != tile.team { return false }
        return tile.targetIDs.isEmpty || tile.targetIDs.contains(target.id)
    }

    private func clamped(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(x: ScalarMath.clamp(point.x, rect.minX, rect.maxX), y: ScalarMath.clamp(point.y, rect.minY, rect.maxY))
    }
}
