import SpriteKit
import UIKit

protocol PausePanelDelegate: AnyObject {
    func pausePanelDidResume()
    func pausePanelDidRestart()
    func pausePanelDidQuit()
}

final class PausePanel: SKNode, PressableNodeDelegate {
    weak var delegate: PausePanelDelegate?

    init(sceneSize: CGSize) {
        super.init()
        zPosition = 1_000
        let dim = SKShapeNode(rectOf: CGSize(width: sceneSize.width * 1.2, height: sceneSize.height * 1.2))
        dim.fillColor = UIColor.black.withAlphaComponent(0.72)
        dim.strokeColor = .clear
        addChild(dim)
        let panel = GameTheme.roundedPanel(size: CGSize(width: min(320, sceneSize.width - 40), height: 308), fill: GameTheme.panel)
        addChild(panel)
        let title = GameTheme.label(GameText.pause, size: 23, weight: .bold)
        title.position.y = 110
        panel.addChild(title)
        let detail = GameTheme.label("WORLD TIME IS HELD", size: 10, color: GameTheme.freezeBlue, weight: .bold)
        detail.position.y = 79
        panel.addChild(detail)
        let actions = [
            ("resume", GameText.resume, "\u{25B6}", PressableNode.Style.primary),
            ("restart", GameText.restart, "\u{21BB}", PressableNode.Style.secondary),
            ("quit", GameText.quit, "\u{2039}", PressableNode.Style.danger)
        ]
        for (index, action) in actions.enumerated() {
            let button = PressableNode(identifier: action.0, title: action.1, icon: action.2, size: CGSize(width: 252, height: 50), style: action.3)
            button.position.y = 32 - CGFloat(index) * 62
            button.delegate = self
            panel.addChild(button)
        }
        if !SaveStore.shared.settings.reduceMotion {
            panel.setScale(0.92)
            panel.alpha = 0
            panel.run(.group([.scale(to: 1, duration: 0.2), .fadeIn(withDuration: 0.16)]))
        }
    }

    required init?(coder aDecoder: NSCoder) { nil }

    func pressableNodeDidActivate(_ node: PressableNode) {
        switch node.identifier {
        case "resume": delegate?.pausePanelDidResume()
        case "restart": delegate?.pausePanelDidRestart()
        case "quit": delegate?.pausePanelDidQuit()
        default: break
        }
    }
}

protocol ResultPanelDelegate: AnyObject {
    func resultPanelRequestedNext()
    func resultPanelRequestedRetry()
    func resultPanelRequestedMenu()
}

final class ResultPanel: SKNode, PressableNodeDelegate {
    /// The panel is centred, so half of these is the height of its top edge —
    /// which is what anything laid out above it has to clear. Named here rather
    /// than written twice: `AchievementBannerNode` keeps its card off this edge.
    static let successHeight: CGFloat = 390
    static let failureHeight: CGFloat = 280

    weak var delegate: ResultPanelDelegate?
    private let success: Bool

    init(sceneSize: CGSize, result: LevelResult?, failure: FailureKind?) {
        success = result != nil
        super.init()
        zPosition = 1_100
        let dim = SKShapeNode(rectOf: CGSize(width: sceneSize.width * 1.2, height: sceneSize.height * 1.2))
        dim.fillColor = UIColor.black.withAlphaComponent(0.76)
        dim.strokeColor = .clear
        addChild(dim)
        let height: CGFloat = result == nil ? Self.failureHeight : Self.successHeight
        let panel = GameTheme.roundedPanel(size: CGSize(width: min(334, sceneSize.width - 36), height: height), fill: GameTheme.panel)
        addChild(panel)
        if let result { buildSuccess(result, in: panel, width: panel.frame.width) }
        else { buildFailure(failure ?? .hazardCollision, in: panel, width: panel.frame.width) }
        if !SaveStore.shared.settings.reduceMotion {
            panel.position.y = -35
            panel.alpha = 0
            panel.run(.group([.moveTo(y: 0, duration: 0.28), .fadeIn(withDuration: 0.2)]))
        }
    }

    required init?(coder aDecoder: NSCoder) { nil }

    func pressableNodeDidActivate(_ node: PressableNode) {
        switch node.identifier {
        case "next": delegate?.resultPanelRequestedNext()
        case "retry": delegate?.resultPanelRequestedRetry()
        case "menu": delegate?.resultPanelRequestedMenu()
        default: break
        }
    }

    private func buildSuccess(_ result: LevelResult, in panel: SKShapeNode, width: CGFloat) {
        let eyebrow = GameTheme.label("TIME ALIGNED", size: 10, color: GameTheme.jade, weight: .bold)
        eyebrow.position.y = 160
        panel.addChild(eyebrow)
        let title = GameTheme.label(GameText.levelComplete, size: 22, weight: .bold)
        title.position.y = 128
        panel.addChild(title)
        let stars = StarRowNode(count: 0, size: 35, spacing: 47)
        stars.position.y = 80
        panel.addChild(stars)
        stars.setCount(result.stars, animated: true)
        let metrics = [
            (GameText.freezes, "\(result.freezeCount)"),
            (GameText.worldTime, String(format: "%.1fs", result.worldTime)),
            ("SCORE", "\(result.score)")
        ]
        for (index, metric) in metrics.enumerated() {
            let x = -width / 3 + width / 3 * CGFloat(index)
            let value = GameTheme.label(metric.1, size: 17, color: index == 2 ? GameTheme.brassLight : GameTheme.textPrimary, weight: .bold)
            value.position = CGPoint(x: x, y: 29)
            panel.addChild(value)
            let label = GameTheme.label(metric.0, size: 8, color: GameTheme.textSecondary, weight: .medium)
            label.position = CGPoint(x: x, y: 7)
            panel.addChild(label)
        }
        let divider = SKShapeNode(rectOf: CGSize(width: width - 40, height: 1))
        divider.fillColor = GameTheme.divider
        divider.strokeColor = .clear
        divider.position.y = -19
        panel.addChild(divider)
        let next = PressableNode(identifier: "next", title: GameText.next, icon: "\u{203A}", size: CGSize(width: width - 40, height: 52), style: .primary)
        next.position.y = -62
        next.delegate = self
        panel.addChild(next)
        let retry = PressableNode(identifier: "retry", title: GameText.retry, icon: "\u{21BB}", size: CGSize(width: (width - 50) / 2, height: 46), style: .secondary)
        retry.position = CGPoint(x: -(width - 40) / 4 - 3, y: -121)
        retry.delegate = self
        panel.addChild(retry)
        let menu = PressableNode(identifier: "menu", title: "MENU", icon: "\u{25A6}", size: CGSize(width: (width - 50) / 2, height: 46), style: .quiet)
        menu.position = CGPoint(x: (width - 40) / 4 + 3, y: -121)
        menu.delegate = self
        panel.addChild(menu)
    }

    private func buildFailure(_ reason: FailureKind, in panel: SKShapeNode, width: CGFloat) {
        // The ring carries the failure colour; the delivered glyph supplies the
        // mark itself, so the two-tone line art is left untinted.
        if let glyph = GameAssets.sprite(GameAssets.Icon.close, fitting: CGSize(width: 26, height: 26)) {
            glyph.position.y = 91
            panel.addChild(glyph)
        } else {
            let symbol = GameTheme.label("!", size: 28, color: GameTheme.vermilion, weight: .black)
            symbol.position.y = 91
            panel.addChild(symbol)
        }
        let ring = SKShapeNode(circleOfRadius: 25)
        ring.strokeColor = GameTheme.vermilion
        ring.fillColor = GameTheme.vermilion.withAlphaComponent(0.08)
        ring.lineWidth = 2
        ring.position.y = 91
        panel.addChild(ring)
        let title = GameTheme.label(reason.message, size: 18, weight: .bold)
        title.position.y = 43
        panel.addChild(title)
        let detail = GameTheme.label("The board resets instantly. Read the rhythm and try again.", size: 9, color: GameTheme.textSecondary, weight: .regular)
        detail.position.y = 15
        panel.addChild(detail)
        let retry = PressableNode(identifier: "retry", title: GameText.retry, icon: "\u{21BB}", size: CGSize(width: width - 40, height: 52), style: .primary)
        retry.position.y = -37
        retry.delegate = self
        panel.addChild(retry)
        let menu = PressableNode(identifier: "menu", title: "RETURN TO MENU", icon: "\u{2039}", size: CGSize(width: width - 40, height: 46), style: .quiet)
        menu.position.y = -96
        menu.delegate = self
        panel.addChild(menu)
    }
}
