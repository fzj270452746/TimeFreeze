import CoreGraphics
import Foundation

struct TimeSnapshot: Codable {
    var simulationTime: TimeInterval
    var worldTime: TimeInterval
    var timeState: TimeState
    var freezeEnergy: CGFloat
    var freezeCount: Int
    var objectStates: [ObjectSnapshot]
    var mechanismStates: [MechanismSnapshot]
    var objectiveStates: [ObjectiveSnapshot]
}

struct ObjectSnapshot: Codable, Hashable {
    var id: String
    var position: WorldPoint
    var velocity: WorldPoint
    var rotation: CGFloat
    var motionTime: CGFloat
    var state: String
    var isRemoved: Bool
}

struct MechanismSnapshot: Codable, Hashable {
    var id: String
    var isActive: Bool
    var isLocked: Bool
    var phase: CGFloat
    var activationCount: Int
    var occupants: [String]
}

struct ObjectiveSnapshot: Codable, Hashable {
    var id: String
    var progress: CGFloat
    var isComplete: Bool
    var values: [String]
}

final class GameClock {
    private(set) var realTime: TimeInterval = 0
    private(set) var simulationTime: TimeInterval = 0
    private(set) var worldTime: TimeInterval = 0
    private(set) var realDelta: TimeInterval = 0
    private(set) var simulationDelta: TimeInterval = 0
    private(set) var state: TimeState = .running
    private(set) var timeScale: CGFloat = 1
    private var previousTimestamp: TimeInterval?
    private let maximumDelta: TimeInterval = 1.0 / 15.0

    func beginFrame(timestamp: TimeInterval) {
        guard let previousTimestamp else {
            self.previousTimestamp = timestamp
            realDelta = 0
            simulationDelta = 0
            return
        }
        let rawDelta = max(0, timestamp - previousTimestamp)
        self.previousTimestamp = timestamp
        realDelta = min(rawDelta, maximumDelta)
        simulationDelta = realDelta * TimeInterval(timeScale)
        realTime += realDelta
        simulationTime += simulationDelta
        if state != .frozen && state != .rewinding { worldTime += simulationDelta }
    }

    func setState(_ newState: TimeState) {
        state = newState
        timeScale = newState.scale
    }

    func setCustomScale(_ scale: CGFloat) {
        timeScale = ScalarMath.clamp(scale, 0, 2)
        if scale == 0 { state = .frozen }
        else if scale < 1 { state = .slowMotion }
        else { state = .running }
    }

    func reset() {
        realTime = 0
        simulationTime = 0
        worldTime = 0
        realDelta = 0
        simulationDelta = 0
        state = .running
        timeScale = 1
        previousTimestamp = nil
    }

    func restore(simulationTime: TimeInterval, worldTime: TimeInterval, state: TimeState) {
        self.simulationTime = simulationTime
        self.worldTime = worldTime
        setState(state)
    }

    func suspend() {
        previousTimestamp = nil
    }
}

protocol TimeControllerDelegate: AnyObject {
    func timeController(_ controller: TimeController, didChange state: TimeState)
    func timeController(_ controller: TimeController, energyChanged energy: CGFloat)
    func timeControllerDidExhaustEnergy(_ controller: TimeController)
}

final class TimeController {
    let clock = GameClock()
    weak var delegate: TimeControllerDelegate?
    private(set) var freezeCount = 0
    private(set) var rewindCount = 0
    private(set) var energy: CGFloat = 100
    private(set) var rules = LevelRules()
    private(set) var selectiveTeams: Set<TileTeam> = []
    private var lastReportedEnergy: Int = 100

    var state: TimeState { clock.state }
    var canFreeze: Bool {
        rules.freezeEnabled && energy > 0.01 &&
        (rules.maximumFreezes <= 0 || freezeCount < rules.maximumFreezes)
    }
    var canRewind: Bool { rules.rewindEnabled }

    func configure(rules: LevelRules) {
        self.rules = rules
        energy = rules.freezeEnergy
        freezeCount = 0
        rewindCount = 0
        selectiveTeams.removeAll()
        clock.reset()
    }

    @discardableResult
    func toggleFreeze() -> Bool {
        switch state {
        case .running, .slowMotion:
            guard canFreeze else { return false }
            freezeCount += 1
            setState(.frozen)
        case .frozen:
            setState(.running)
        case .rewinding:
            return false
        }
        return true
    }

    @discardableResult
    func enterSlowMotion() -> Bool {
        guard rules.slowMotionEnabled, state == .running, energy > 0 else { return false }
        setState(.slowMotion)
        return true
    }

    func beginRewind() -> Bool {
        guard rules.rewindEnabled, state != .rewinding else { return false }
        rewindCount += 1
        setState(.rewinding)
        return true
    }

    func endRewind() {
        guard state == .rewinding else { return }
        setState(.frozen)
    }

    func update(timestamp: TimeInterval) {
        clock.beginFrame(timestamp: timestamp)
        guard !rules.unlimitedFreeze else { return }
        let oldEnergy = energy
        if state == .frozen || state == .slowMotion {
            let multiplier: CGFloat = state == .slowMotion ? 0.45 : 1
            energy -= CGFloat(clock.realDelta) * rules.freezeDrainPerSecond * multiplier
            energy = max(0, energy)
            if energy == 0 {
                setState(.running)
                delegate?.timeControllerDidExhaustEnergy(self)
            }
        } else if state == .running {
            energy += CGFloat(clock.realDelta) * rules.freezeRecoveryPerSecond
            energy = min(rules.freezeEnergy, energy)
        }
        let reported = Int(energy.rounded())
        if reported != lastReportedEnergy || abs(oldEnergy - energy) > 2 {
            lastReportedEnergy = reported
            delegate?.timeController(self, energyChanged: energy)
        }
    }

    func setSelectiveTeams(_ teams: Set<TileTeam>) {
        selectiveTeams = teams
    }

    func simulationDelta(for team: TileTeam, affectedByFreeze: Bool) -> TimeInterval {
        guard affectedByFreeze else { return clock.realDelta }
        guard state == .frozen else { return clock.simulationDelta }
        if !selectiveTeams.isEmpty && !selectiveTeams.contains(team) { return clock.realDelta }
        return 0
    }

    func restore(from snapshot: TimeSnapshot) {
        energy = snapshot.freezeEnergy
        freezeCount = snapshot.freezeCount
        clock.restore(
            simulationTime: snapshot.simulationTime,
            worldTime: snapshot.worldTime,
            state: snapshot.timeState
        )
        delegate?.timeController(self, energyChanged: energy)
        delegate?.timeController(self, didChange: state)
    }

    func reset() {
        configure(rules: rules)
        delegate?.timeController(self, energyChanged: energy)
        delegate?.timeController(self, didChange: .running)
    }

    private func setState(_ state: TimeState) {
        clock.setState(state)
        delegate?.timeController(self, didChange: state)
    }
}

final class SnapshotTimeline {
    private var snapshots: [TimeSnapshot] = []
    private let interval: TimeInterval
    private let maximumDuration: TimeInterval
    private var accumulator: TimeInterval = 0

    init(interval: TimeInterval = 0.1, maximumDuration: TimeInterval = 8) {
        self.interval = interval
        self.maximumDuration = maximumDuration
    }

    func shouldCapture(delta: TimeInterval) -> Bool {
        accumulator += delta
        guard accumulator >= interval else { return false }
        accumulator.formTruncatingRemainder(dividingBy: interval)
        return true
    }

    func append(_ snapshot: TimeSnapshot) {
        snapshots.append(snapshot)
        let cutoff = snapshot.simulationTime - maximumDuration
        if let firstValid = snapshots.firstIndex(where: { $0.simulationTime >= cutoff }), firstValid > 0 {
            snapshots.removeFirst(firstValid)
        }
    }

    func popPrevious(before time: TimeInterval, step: TimeInterval = 0.12) -> TimeSnapshot? {
        let target = time - step
        guard let index = snapshots.lastIndex(where: { $0.simulationTime <= target }) else {
            return snapshots.first
        }
        let snapshot = snapshots[index]
        if index < snapshots.count - 1 { snapshots.removeSubrange((index + 1)..<snapshots.count) }
        return snapshot
    }

    func snapshot(secondsBefore seconds: TimeInterval, currentTime: TimeInterval) -> TimeSnapshot? {
        let target = currentTime - seconds
        return snapshots.min { abs($0.simulationTime - target) < abs($1.simulationTime - target) }
    }

    func reset() {
        snapshots.removeAll(keepingCapacity: true)
        accumulator = 0
    }
}
