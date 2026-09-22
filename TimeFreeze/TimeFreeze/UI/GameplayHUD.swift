import SpriteKit
import UIKit

protocol GameplayHUDDelegate: AnyObject {
    func gameplayHUDRequestedPause()
    func gameplayHUDRequestedRestart()
    func gameplayHUDRequestedFreeze(at point: CGPoint)
    func gameplayHUDRequestedRewind(began: Bool)
}

final class GameplayHUD: SKNode, PressableNodeDelegate {
    weak var delegate: GameplayHUDDelegate?
    private let levelLabel = SKLabelNode()
    private let modeLabel = SKLabelNode()
    private let objectiveLabel = SKLabelNode()
    private let freezeCountLabel = SKLabelNode()
    private let worldTimeLabel = SKLabelNode()
    private let stateLabel = SKLabelNode()
    private let stateDetailLabel = SKLabelNode()
    private let objectiveProgress = ProgressBarNode(width: 150, height: 5)
    private let energyProgress = ProgressBarNode(width: 110, height: 6)
    private let topBand = SKShapeNode()
    private let bottomBand = SKShapeNode()
    private let topSignal = SKShapeNode(rectOf: CGSize(width: 68, height: 2))
    private let bottomSignal = SKShapeNode(rectOf: CGSize(width: 44, height: 2))
    private let freezeHalo = SKShapeNode(circleOfRadius: 39)
    private let freezeCore = SKShapeNode(circleOfRadius: 31)
    private var freezeButton: PressableNode!
    private var rewindButton: PressableNode?
    private var currentSize = CGSize.zero
    private let definition: LevelDefinition

    init(definition: LevelDefinition) {
        self.definition = definition
        super.init()
        zPosition = 500
        buildNodes()
    }

    required init?(coder aDecoder: NSCoder) { nil }

    func layout(in scene: SKScene) {
        currentSize = scene.size
        let safeTop = scene.size.height / 2 - max(scene.view?.safeAreaInsets.top ?? 0, 16)
        let safeBottom = -scene.size.height / 2 + max(scene.view?.safeAreaInsets.bottom ?? 0, 10)
        levelLabel.position = CGPoint(x: -scene.size.width / 2 + 20, y: safeTop - 21)
        modeLabel.position = CGPoint(x: -scene.size.width / 2 + 20, y: safeTop - 44)
        childNode(withName: "restartButton")?.position = CGPoint(x: scene.size.width / 2 - 82, y: safeTop - 27)
        childNode(withName: "pauseButton")?.position = CGPoint(x: scene.size.width / 2 - 29, y: safeTop - 27)
        objectiveLabel.position = CGPoint(x: 0, y: safeTop - 76)
        objectiveProgress.position = CGPoint(x: 0, y: safeTop - 91)
        let bottomY = safeBottom + 54
        freezeButton.position = CGPoint(x: 0, y: bottomY)
        stateLabel.position = CGPoint(x: 0, y: bottomY + 41)
        stateDetailLabel.position = CGPoint(x: 0, y: bottomY - 42)
        freezeCountLabel.position = CGPoint(x: -scene.size.width / 2 + 22, y: safeBottom + 30)
        worldTimeLabel.position = CGPoint(x: scene.size.width / 2 - 22, y: safeBottom + 30)
        energyProgress.position = CGPoint(x: 0, y: bottomY - 57)
        rewindButton?.position = CGPoint(x: SaveStore.shared.settings.leftHandedControls ? scene.size.width / 2 - 34 : -scene.size.width / 2 + 34, y: bottomY)
        let topWidth = max(1, scene.size.width - 22)
        topBand.path = GameTheme.chamferedPath(size: CGSize(width: topWidth, height: 64), cut: 9)
        topBand.position = CGPoint(x: 0, y: safeTop - 32)
        let bottomWidth = max(1, scene.size.width - 22)
        bottomBand.path = GameTheme.chamferedPath(size: CGSize(width: bottomWidth, height: 118), cut: 11)
        bottomBand.position = CGPoint(x: 0, y: safeBottom + 48)
        topSignal.position = CGPoint(x: -topWidth / 2 + 48, y: safeTop - 1)
        bottomSignal.position = CGPoint(x: bottomWidth / 2 - 37, y: safeBottom + 106)
        freezeHalo.position = CGPoint(x: 0, y: bottomY)
        freezeCore.position = freezeHalo.position
    }

    func update(state: TimeState) {
        switch state {
        case .running:
            stateLabel.text = GameText.running
            stateLabel.fontColor = GameTheme.brassLight
            freezeButton.setTitle("FREEZE")
            stateDetailLabel.text = "TAP TO STOP WORLD TIME"
            applyTimeSignal(color: GameTheme.brassLight, glow: 1, pulsing: false)
        case .frozen:
            stateLabel.text = GameText.frozen
            stateLabel.fontColor = GameTheme.freezeBlue
            freezeButton.setTitle("RESUME")
            stateDetailLabel.text = "WORLD STILL  /  CONTROLS ACTIVE"
            applyTimeSignal(color: GameTheme.freezeBlue, glow: 6, pulsing: true)
        case .slowMotion:
            stateLabel.text = GameText.slowMotion
            stateLabel.fontColor = GameTheme.jade
            freezeButton.setTitle("FREEZE")
            stateDetailLabel.text = "WORLD SPEED 25%"
            applyTimeSignal(color: GameTheme.jade, glow: 3, pulsing: true)
        case .rewinding:
            stateLabel.text = "REWINDING"
            stateLabel.fontColor = GameTheme.vermilion
            stateDetailLabel.text = "RESTORING THE PREVIOUS BOARD STATE"
            applyTimeSignal(color: GameTheme.vermilion, glow: 5, pulsing: true)
        }
    }

    func updateMetrics(freezes: Int, worldTime: TimeInterval) {
        let limit = definition.rules.maximumFreezes > 0 ? "/\(definition.rules.maximumFreezes)" : ""
        freezeCountLabel.text = "FREEZES  \(freezes)\(limit)"
        worldTimeLabel.text = String(format: "WORLD  %.1fs", worldTime)
    }

    func updateObjective(progress: CGFloat) { objectiveProgress.setProgress(progress) }

    func updateEnergy(_ energy: CGFloat) {
        let maximum = max(1, definition.rules.freezeEnergy)
        let fraction = energy / maximum
        energyProgress.setProgress(fraction)
        energyProgress.setTint(fraction < 0.2 ? GameTheme.vermilion : GameTheme.freezeBlue)
    }

    func pressableNodeDidActivate(_ node: PressableNode) {
        switch node.identifier {
        case "pause": delegate?.gameplayHUDRequestedPause()
        case "restart": delegate?.gameplayHUDRequestedRestart()
        case "freeze": delegate?.gameplayHUDRequestedFreeze(at: .zero)
        case "rewind": delegate?.gameplayHUDRequestedRewind(began: true)
        default: break
        }
    }

    private func buildNodes() {
        topBand.fillColor = GameTheme.panel.withAlphaComponent(0.94)
        topBand.strokeColor = GameTheme.freezeBlue.withAlphaComponent(0.36)
        topBand.lineWidth = 1.2
        topBand.zPosition = -2
        bottomBand.fillColor = GameTheme.panel.withAlphaComponent(0.96)
        bottomBand.strokeColor = GameTheme.freezeBlue.withAlphaComponent(0.36)
        bottomBand.lineWidth = 1.2
        bottomBand.zPosition = -2
        addChild(topBand)
        addChild(bottomBand)
        topSignal.fillColor = GameTheme.freezeBlue
        topSignal.strokeColor = .clear
        topSignal.zPosition = -1
        bottomSignal.fillColor = GameTheme.vermilion
        bottomSignal.strokeColor = .clear
        bottomSignal.zPosition = -1
        addChild(topSignal)
        addChild(bottomSignal)
        freezeHalo.fillColor = .clear
        freezeHalo.strokeColor = GameTheme.brassLight
        freezeHalo.lineWidth = 1.4
        freezeHalo.zPosition = -1
        freezeCore.fillColor = GameTheme.background.withAlphaComponent(0.32)
        freezeCore.strokeColor = GameTheme.divider
        freezeCore.lineWidth = 0.7
        freezeCore.zPosition = -1
        addChild(freezeHalo)
        addChild(freezeCore)
        configureLabel(levelLabel, text: definition.mode == .daily ? "DAILY PUZZLE" : "LEVEL \(definition.displayNumber)", size: 13, color: GameTheme.textPrimary, alignment: .left, weight: .bold)
        configureLabel(modeLabel, text: definition.mode.displayName, size: 9, color: GameTheme.textSecondary, alignment: .left, weight: .medium)
        configureLabel(objectiveLabel, text: definition.objectives.first?.title.uppercased() ?? "REACH THE TARGET", size: 10, color: GameTheme.textSecondary, alignment: .center, weight: .bold)
        let freezeLimit = definition.rules.maximumFreezes > 0 ? "/\(definition.rules.maximumFreezes)" : ""
        configureLabel(freezeCountLabel, text: "FREEZES  0\(freezeLimit)", size: 10, color: GameTheme.textSecondary, alignment: .left, weight: .bold)
        configureLabel(worldTimeLabel, text: "WORLD  0.0s", size: 10, color: GameTheme.textSecondary, alignment: .right, weight: .bold)
        configureLabel(stateLabel, text: GameText.running, size: 11, color: GameTheme.brassLight, alignment: .center, weight: .bold)
        configureLabel(stateDetailLabel, text: "TAP TO STOP WORLD TIME", size: 8, color: GameTheme.textSecondary, alignment: .center, weight: .medium)
        [levelLabel, modeLabel, objectiveLabel, freezeCountLabel, worldTimeLabel, stateLabel, stateDetailLabel].forEach(addChild)
        addChild(objectiveProgress)
        let restart = PressableNode(identifier: "restart", title: "", icon: "\u{21BB}", size: CGSize(width: 46, height: 46), style: .quiet)
        restart.name = "restartButton"
        restart.delegate = self
        addChild(restart)
        let pause = PressableNode(identifier: "pause", title: "", icon: "\u{2016}", size: CGSize(width: 46, height: 46), style: .quiet)
        pause.name = "pauseButton"
        pause.delegate = self
        addChild(pause)
        freezeButton = PressableNode(identifier: "freeze", title: "FREEZE", size: CGSize(width: 148, height: 54), style: .freeze)
        freezeButton.delegate = self
        addChild(freezeButton)
        if !definition.rules.unlimitedFreeze {
            addChild(energyProgress)
            energyProgress.setProgress(1, animated: false)
        }
        if definition.rules.rewindEnabled {
            let rewind = PressableNode(identifier: "rewind", title: "", icon: "\u{00AB}", size: CGSize(width: 52, height: 52), style: .secondary)
            rewind.delegate = self
            addChild(rewind)
            rewindButton = rewind
        }
    }

    private func configureLabel(
        _ label: SKLabelNode,
        text: String,
        size: CGFloat,
        color: UIColor,
        alignment: SKLabelHorizontalAlignmentMode,
        weight: UIFont.Weight
    ) {
        label.text = text
        label.fontName = GameTheme.displayFont(size: size, weight: weight).fontName
        label.fontSize = size
        label.fontColor = color
        label.horizontalAlignmentMode = alignment
        label.verticalAlignmentMode = .center
    }

    private func applyTimeSignal(color: UIColor, glow: CGFloat, pulsing: Bool) {
        freezeHalo.removeAllActions()
        freezeHalo.setScale(1)
        freezeHalo.strokeColor = color
        freezeHalo.glowWidth = glow
        bottomBand.strokeColor = color.withAlphaComponent(0.52)
        stateLabel.removeAllActions()
        guard pulsing, !SaveStore.shared.settings.reduceMotion else { return }
        freezeHalo.run(.repeatForever(.sequence([
            .scale(to: 1.08, duration: 0.58),
            .scale(to: 1, duration: 0.58)
        ])))
    }
}
