import SpriteKit
import UIKit

enum TutorialTrigger: String, Codable {
    case onStart
    case timeFrozen
    case timeResumed
    case switchActivated
    case tileDragged
    case tileInteracted
    case objectiveProgress
}

struct TutorialStep: Codable, Hashable {
    var id: String
    var instruction: String
    var trigger: TutorialTrigger
    var highlightID: String?
    var requiredState: TimeState?
    var dismissAfterAction: Bool
}

final class TutorialManager {
    private let key: String
    private let steps: [TutorialStep]
    private(set) var index = 0
    private(set) var isComplete = false
    var currentStep: TutorialStep? { index < steps.count ? steps[index] : nil }
    var stepChanged: ((TutorialStep?) -> Void)?

    init(key: String, steps: [TutorialStep]) {
        self.key = key
        self.steps = steps
        if SaveStore.shared.progress.tutorialKeysSeen.contains(key) || !SaveStore.shared.settings.tutorialHints {
            index = steps.count
            isComplete = true
        }
    }

    func start() { stepChanged?(currentStep) }

    func consume(_ event: GameEvent) {
        guard let step = currentStep else { return }
        let matched: Bool
        switch (step.trigger, event) {
        case (.timeFrozen, .timeFrozen): matched = true
        case (.timeResumed, .timeResumed): matched = true
        case (.switchActivated, .switchActivated): matched = true
        case (.objectiveProgress, .objectiveProgress): matched = true
        default: matched = false
        }
        if matched { advance() }
    }

    func recordDrag() {
        if currentStep?.trigger == .tileDragged { advance() }
    }

    func recordTileInteraction() {
        if currentStep?.trigger == .tileInteracted { advance() }
    }

    func dismiss() { complete() }

    private func advance() {
        index += 1
        if index >= steps.count { complete() }
        else { stepChanged?(steps[index]) }
    }

    private func complete() {
        guard !isComplete else { return }
        isComplete = true
        SaveStore.shared.markTutorialSeen(key)
        stepChanged?(nil)
    }

    static func steps(for key: String) -> [TutorialStep] {
        switch key {
        case "first-freeze":
            return [
                TutorialStep(id: "freeze", instruction: GameText.freezeOnTarget, trigger: .timeFrozen, highlightID: "freeze", requiredState: .running, dismissAfterAction: true),
                TutorialStep(id: "resume", instruction: GameText.tapToResume, trigger: .timeResumed, highlightID: "freeze", requiredState: .frozen, dismissAfterAction: true)
            ]
        case "switch":
            return [
                TutorialStep(id: "freeze", instruction: GameText.tapToFreeze, trigger: .timeFrozen, highlightID: "freeze", requiredState: .running, dismissAfterAction: true),
                TutorialStep(id: "switch", instruction: GameText.activateSwitch, trigger: .switchActivated, highlightID: "switch-a", requiredState: .frozen, dismissAfterAction: true),
                TutorialStep(id: "resume", instruction: GameText.tapToResume, trigger: .timeResumed, highlightID: "freeze", requiredState: .frozen, dismissAfterAction: true)
            ]
        case "drag", "foundation-drag":
            return [
                TutorialStep(id: "freeze", instruction: GameText.tapToFreeze, trigger: .timeFrozen, highlightID: "freeze", requiredState: .running, dismissAfterAction: true),
                TutorialStep(id: "drag", instruction: GameText.dragWhileFrozen, trigger: .tileDragged, highlightID: "tile-a", requiredState: .frozen, dismissAfterAction: true)
            ]
        case "foundation-direction":
            return [
                TutorialStep(id: "freeze", instruction: GameText.tapToFreeze, trigger: .timeFrozen, highlightID: "freeze", requiredState: .running, dismissAfterAction: true),
                TutorialStep(id: "turn", instruction: GameText.turnWindTile, trigger: .tileInteracted, highlightID: "tile-a", requiredState: .frozen, dismissAfterAction: true),
                TutorialStep(id: "resume", instruction: GameText.tapToResume, trigger: .timeResumed, highlightID: "freeze", requiredState: .frozen, dismissAfterAction: true),
                TutorialStep(id: "arrival", instruction: GameText.freezeOnTarget, trigger: .timeFrozen, highlightID: "target-a", requiredState: .running, dismissAfterAction: true)
            ]
        case "rewind":
            return [TutorialStep(id: "rewind", instruction: GameText.swipeToRewind, trigger: .onStart, highlightID: "rewind", requiredState: nil, dismissAfterAction: false)]
        default:
            return []
        }
    }
}

final class TutorialBannerNode: SKNode {
    private let panel = SKShapeNode(rectOf: CGSize(width: 286, height: 48), cornerRadius: 7)
    private let label = SKLabelNode()
    private let pointer = SKShapeNode()

    override init() {
        super.init()
        zPosition = 900
        panel.fillColor = GameTheme.freezeWhite.withAlphaComponent(0.96)
        panel.strokeColor = GameTheme.freezeBlue
        panel.lineWidth = 2
        panel.glowWidth = 2
        addChild(panel)
        label.fontName = GameTheme.displayFont(size: 11, weight: .bold).fontName
        label.fontSize = 11
        label.fontColor = GameTheme.ink
        label.verticalAlignmentMode = .center
        panel.addChild(label)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -8, y: -23))
        path.addLine(to: CGPoint(x: 0, y: -33))
        path.addLine(to: CGPoint(x: 8, y: -23))
        path.closeSubpath()
        pointer.path = path
        pointer.fillColor = GameTheme.freezeWhite
        pointer.strokeColor = GameTheme.freezeBlue
        pointer.lineWidth = 1
        panel.addChild(pointer)
        isHidden = true
    }

    required init?(coder aDecoder: NSCoder) { nil }

    func show(_ instruction: String, at position: CGPoint) {
        label.text = instruction
        self.position = position
        isHidden = false
        removeAllActions()
        if !SaveStore.shared.settings.reduceMotion {
            alpha = 0
            run(.fadeIn(withDuration: 0.16))
            panel.run(.repeatForever(.sequence([.moveBy(x: 0, y: 2, duration: 0.5), .moveBy(x: 0, y: -2, duration: 0.5)])), withKey: "float")
        }
    }

    func hide() {
        panel.removeAction(forKey: "float")
        if SaveStore.shared.settings.reduceMotion { isHidden = true }
        else {
            run(.sequence([.fadeOut(withDuration: 0.14), .run { [weak self] in self?.isHidden = true }]))
        }
    }
}
