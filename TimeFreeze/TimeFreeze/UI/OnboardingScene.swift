import SpriteKit
import UIKit

/// First-run onboarding. Shows the one idea the game is built on — world time
/// stops, but the player's hands do not — before the player ever reaches the
/// menu. Three screens, one core concept each, so a reviewer who opens the app
/// cold understands the hook instead of reading it as a plain timing game.
final class OnboardingScene: BaseScene {

    private struct Page {
        let eyebrow: String
        let title: String
        let body: String
    }

    private static let pages: [Page] = [
        Page(
            eyebrow: "SYSTEM 01",
            title: "STOP WORLD TIME",
            body: "Tap to freeze the table. Every tile, gate and conveyor halts at the exact moment you choose."
        ),
        Page(
            eyebrow: "WHILE FROZEN",
            title: "YOUR HANDS MOVE",
            body: "Time stands still — you don't. Drag tiles, flip switches and turn gates while the world is held."
        ),
        Page(
            eyebrow: "TEN LESSONS",
            title: "200 LEVELS. ONE CLOCK.",
            body: "Master twenty time mechanisms across ten chapters, plus a daily puzzle and an endless table."
        )
    ]

    private var pageIndex = 0
    private let dots = SKNode()
    private let content = SKNode()
    private var nextButton: PressableNode!
    private var skipButton: PressableNode!
    private var isBuilt = false

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        buildChrome()
        buildPage()
        isBuilt = true
        transitionIn()
    }

    override func layoutDidChange() {
        guard isBuilt else { return }
        removeSceneContent()
        buildChrome()
        buildPage()
    }

    // MARK: - Chrome

    private func buildChrome() {
        addChild(dots)
        layoutDots()
        addChild(content)

        skipButton = PressableNode(
            identifier: "skip",
            title: "SKIP",
            size: CGSize(width: 96, height: 46),
            style: .quiet
        )
        skipButton.position = CGPoint(x: -size.width / 2 + 64, y: safeBottom + 34)
        skipButton.delegate = self
        addChild(skipButton)

        nextButton = PressableNode(
            identifier: "next",
            title: pageIndex == Self.pages.count - 1 ? "START" : "NEXT",
            icon: "\u{203A}",
            size: CGSize(width: 148, height: 50),
            style: .primary
        )
        nextButton.position = CGPoint(x: size.width / 2 - 88, y: safeBottom + 34)
        nextButton.delegate = self
        addChild(nextButton)
    }

    private func layoutDots() {
        dots.removeAllChildren()
        let spacing: CGFloat = 18
        let totalWidth = CGFloat(Self.pages.count - 1) * spacing
        for index in 0..<Self.pages.count {
            let dot = SKShapeNode(circleOfRadius: index == pageIndex ? 5 : 3.5)
            dot.fillColor = index == pageIndex ? GameTheme.freezeBlue : GameTheme.divider
            dot.strokeColor = .clear
            dot.position = CGPoint(x: -totalWidth / 2 + CGFloat(index) * spacing, y: safeBottom + 78)
            if index == pageIndex {
                dot.glowWidth = 2
            }
            dots.addChild(dot)
        }
    }

    // MARK: - Page

    private func buildPage() {
        content.removeAllChildren()
        let page = Self.pages[pageIndex]

        let eyebrow = GameTheme.label(page.eyebrow, size: 10, color: GameTheme.freezeBlue, weight: .bold)
        eyebrow.position = CGPoint(x: 0, y: safeTop - 88)
        content.addChild(eyebrow)

        let title = GameTheme.label(page.title, size: 30, color: GameTheme.textPrimary, weight: .black)
        title.fontName = GameTheme.titleFont(size: 30).fontName
        title.position = CGPoint(x: 0, y: safeTop - 130)
        content.addChild(title)

        let body = GameTheme.label(page.body, size: 13, color: GameTheme.textSecondary, weight: .regular)
        body.numberOfLines = 0
        body.preferredMaxLayoutWidth = min(330, size.width - 56)
        body.verticalAlignmentMode = .top
        body.position = CGPoint(x: 0, y: safeTop - 190)
        content.addChild(body)

        let demo = demoNode(for: pageIndex)
        demo.position = CGPoint(x: 0, y: safeTop - 300)
        content.addChild(demo)
    }

    /// The visual anchor for each page, built from the same art the game uses so
    /// the onboarding reads as a preview of play rather than a marketing slide.
    private func demoNode(for page: Int) -> SKNode {
        let node = SKNode()
        switch page {
        case 0:
            node.addChild(ClockEmblemNode(radius: 66))
        case 1:
            let tile = MahjongTileRenderer.makeFaceNode(
                suit: .dots,
                face: .five,
                team: .ivory,
                size: CGSize(width: 48, height: 62),
                compact: true,
                skin: SaveStore.shared.settings.tileSkin
            )
            tile.position = CGPoint(x: -88, y: 0)
            node.addChild(tile)
            let arrow = SKShapeNode(rectOf: CGSize(width: 96, height: 3))
            arrow.fillColor = GameTheme.freezeBlue
            arrow.strokeColor = .clear
            arrow.position = CGPoint(x: -10, y: 0)
            node.addChild(arrow)
            let head = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 46, y: 8))
            path.addLine(to: CGPoint(x: 46, y: -8))
            path.addLine(to: CGPoint(x: 62, y: 0))
            path.closeSubpath()
            head.path = path
            head.fillColor = GameTheme.freezeBlue
            head.strokeColor = .clear
            node.addChild(head)
            let target = SKShapeNode(circleOfRadius: 40)
            target.fillColor = GameTheme.freezeBlue.withAlphaComponent(0.08)
            target.strokeColor = GameTheme.freezeBlue
            target.lineWidth = 2
            target.glowWidth = 2
            target.position = CGPoint(x: 86, y: 0)
            node.addChild(target)
        default:
            let glyphs: [(String, CGPoint)] = [
                (GameAssets.Mechanic.gate, CGPoint(x: -90, y: 0)),
                (GameAssets.Mechanic.portalOut, CGPoint(x: 0, y: 6)),
                (GameAssets.Mechanic.magnet, CGPoint(x: 90, y: 0))
            ]
            for (asset, position) in glyphs {
                if let sprite = GameAssets.sprite(asset, fitting: CGSize(width: 58, height: 58)) {
                    sprite.position = position
                    node.addChild(sprite)
                } else {
                    let ring = SKShapeNode(circleOfRadius: 29)
                    ring.fillColor = GameTheme.board
                    ring.strokeColor = GameTheme.freezeBlue
                    ring.lineWidth = 1.4
                    ring.position = position
                    node.addChild(ring)
                }
            }
        }
        return node
    }

    // MARK: - Actions

    private func advance() {
        if pageIndex < Self.pages.count - 1 {
            pageIndex += 1
            layoutDots()
            nextButton.setTitle(pageIndex == Self.pages.count - 1 ? "START" : "NEXT")
            buildPage()
        } else {
            finish()
        }
    }

    private func finish() {
        SaveStore.shared.markOnboardingSeen()
        GameCoordinator.shared.showMenu()
    }

    override func pressableNodeDidActivate(_ node: PressableNode) {
        switch node.identifier {
        case "skip": finish()
        case "next": advance()
        default: break
        }
    }
}
