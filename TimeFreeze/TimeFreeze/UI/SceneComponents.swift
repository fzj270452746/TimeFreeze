import SpriteKit
import UIKit

protocol PressableNodeDelegate: AnyObject {
    func pressableNodeDidActivate(_ node: PressableNode)
}

class PressableNode: SKNode {
    let identifier: String
    weak var delegate: PressableNodeDelegate?
    private let background: SKShapeNode
    private let titleLabel: SKLabelNode
    private let iconNode: SKSpriteNode?
    private let fixedSize: CGSize
    private var normalColor: UIColor
    private var pressedColor: UIColor
    private(set) var style: Style
    private(set) var isEnabled = true
    private(set) var isPressed = false

    init(
        identifier: String,
        title: String,
        icon: String? = nil,
        size: CGSize,
        style: Style = .primary,
        showsRail: Bool = true
    ) {
        self.identifier = identifier
        self.style = style
        fixedSize = CGSize(
            width: max(LayoutMetrics.minimumTouch, size.width),
            height: max(LayoutMetrics.minimumTouch, size.height)
        )
        (normalColor, pressedColor) = Self.colors(for: style)
        background = SKShapeNode(path: GameTheme.chamferedPath(size: fixedSize, cut: style == .quiet ? 5 : 8))
        background.fillColor = normalColor
        switch style {
        case .primary, .freeze: background.strokeColor = GameTheme.freezeWhite.withAlphaComponent(0.88)
        case .danger: background.strokeColor = GameTheme.vermilion
        case .secondary, .quiet: background.strokeColor = GameTheme.divider
        }
        background.lineWidth = style == .quiet ? 0.8 : 1.2
        background.glowWidth = style == .primary ? 1.5 : 0
        let foregroundColor = style == .primary ? GameTheme.ink : (style == .freeze ? GameTheme.freezeWhite : GameTheme.textPrimary)
        titleLabel = GameTheme.label(
            title,
            size: style == .primary ? 14 : 12,
            color: foregroundColor,
            weight: .bold
        )
        if let icon, let delivered = Self.deliveredIcon(for: icon) {
            // Delivered line art carries its own brass-and-teal palette, so it is
            // only pulled part of the way toward the button foreground. Left
            // untinted it reads as a dimmer, differently-coloured sibling of the
            // symbols beside it, and blended all the way it collapses into a flat
            // silhouette; a partial blend keeps the drawing and matches the row.
            delivered.color = foregroundColor
            delivered.colorBlendFactor = 0.4
            iconNode = delivered
        } else if let icon, let systemName = Self.systemSymbolName(for: icon) {
            let color = foregroundColor
            let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            let image = Self.rasterizedSymbol(
                named: systemName,
                configuration: configuration,
                color: color
            )
            if let image {
                let sprite = SKSpriteNode(texture: SKTexture(image: image))
                let ratio = image.size.width / max(1, image.size.height)
                sprite.size = CGSize(width: min(23, 19 * ratio), height: min(23, 19 / max(0.5, ratio)))
                iconNode = sprite
            } else {
                iconNode = nil
            }
        } else {
            iconNode = nil
        }
        super.init()
        isUserInteractionEnabled = true
        if style != .quiet {
            let lip = SKShapeNode(path: GameTheme.chamferedPath(size: fixedSize, cut: 8))
            switch style {
            case .primary: lip.fillColor = GameTheme.freezeBlue.blended(with: GameTheme.background, amount: 0.58)
            case .secondary: lip.fillColor = GameTheme.background
            case .freeze: lip.fillColor = GameTheme.boardDark
            case .danger: lip.fillColor = GameTheme.background
            case .quiet: lip.fillColor = .clear
            }
            lip.strokeColor = .clear
            lip.position.y = -4
            lip.zPosition = -1
            addChild(lip)

            if showsRail {
                let rail = SKShapeNode(rectOf: CGSize(width: 3, height: max(14, fixedSize.height - 20)))
                rail.fillColor = style == .danger ? GameTheme.vermilion : (style == .secondary ? GameTheme.brassLight : GameTheme.freezeWhite)
                rail.strokeColor = .clear
                rail.position.x = -fixedSize.width / 2 + 6
                rail.zPosition = 2
                addChild(rail)
            }
        }
        addChild(background)
        if let iconNode {
            iconNode.position = CGPoint(x: title.isEmpty ? 0 : -fixedSize.width / 2 + 25, y: 0)
            addChild(iconNode)
            titleLabel.position.x = title.isEmpty ? 0 : 10
        }
        titleLabel.position.y = -1
        addChild(titleLabel)
        accessibilityLabel = title
        accessibilityTraits = .button
    }

    required init?(coder aDecoder: NSCoder) { nil }

    enum Style {
        case primary
        case secondary
        case freeze
        case danger
        case quiet
    }

    private static func colors(for style: Style) -> (normal: UIColor, pressed: UIColor) {
        switch style {
        case .primary:
            return (GameTheme.freezeBlue, GameTheme.freezeWhite)
        case .secondary:
            return (GameTheme.panel, GameTheme.boardLight)
        case .freeze:
            return (GameTheme.freezeBlue.blended(with: GameTheme.background, amount: 0.72), GameTheme.boardLight)
        case .danger:
            return (
                GameTheme.vermilion.blended(with: GameTheme.background, amount: 0.72),
                GameTheme.vermilion.blended(with: GameTheme.background, amount: 0.45)
            )
        case .quiet:
            return (.clear, UIColor.white.withAlphaComponent(0.12))
        }
    }

    func setTitle(_ title: String) {
        titleLabel.text = title
        accessibilityLabel = title
    }

    /// Restyles in place, so a control that doubles as a selector can show its
    /// new state without its scene being torn down and rebuilt around it.
    func setStyle(_ newStyle: Style) {
        style = newStyle
        (normalColor, pressedColor) = Self.colors(for: newStyle)
        background.fillColor = isPressed ? pressedColor : normalColor
        switch newStyle {
        case .primary, .freeze: background.strokeColor = GameTheme.freezeWhite.withAlphaComponent(0.88)
        case .danger: background.strokeColor = GameTheme.vermilion
        case .secondary, .quiet: background.strokeColor = GameTheme.divider
        }
        background.lineWidth = newStyle == .quiet ? 0.8 : 1.2
        background.glowWidth = newStyle == .primary ? 1.5 : 0
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        alpha = enabled ? 1 : 0.42
        accessibilityTraits = enabled ? .button : [.button, .notEnabled]
    }

    func containsScenePoint(_ point: CGPoint) -> Bool {
        calculateAccumulatedFrame().insetBy(dx: -3, dy: -3).contains(point)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isEnabled else { return }
        isPressed = true
        background.fillColor = pressedColor
        if !SaveStore.shared.settings.reduceMotion {
            run(.scale(to: 0.97, duration: 0.08))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let inside = background.contains(touch.location(in: self))
        background.fillColor = inside ? pressedColor : normalColor
        isPressed = inside
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { restoreAppearance() }
        guard isEnabled, isPressed, let touch = touches.first,
              background.contains(touch.location(in: self)) else { return }
        HapticService.shared.play(.tap)
        AudioService.shared.play(.tap)
        delegate?.pressableNodeDidActivate(self)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        restoreAppearance()
    }

    /// Drops an in-flight press without activating.
    ///
    /// A scrolling container needs this: once the scene decides a drag is a
    /// scroll rather than a tap, the button under the finger has to stop looking
    /// pressed, and the touch it is already tracking must not fire on release.
    func cancelPress() {
        guard isPressed else { return }
        restoreAppearance()
    }

    /// Shows the pressed look without a touch of its own, for containers that own
    /// the gesture. Paired with `cancelPress()` or `activateFromContainer()`.
    func beginPressFromContainer() {
        guard isEnabled, !isPressed else { return }
        isPressed = true
        background.fillColor = pressedColor
        if !SaveStore.shared.settings.reduceMotion {
            run(.scale(to: 0.97, duration: 0.08))
        }
    }

    /// Activates without a touch of its own, for containers that own the gesture.
    ///
    /// A node inside a scrolling list cannot track touches itself: the scene has
    /// to decide whether a drag is a scroll or a tap, and a node that swallows
    /// the touch never gives it that chance. Such nodes are built with
    /// `isUserInteractionEnabled = false` and the container drives them through
    /// `beginPressFromContainer()` and this.
    func activateFromContainer() {
        guard isEnabled else { return }
        restoreAppearance()
        HapticService.shared.play(.tap)
        AudioService.shared.play(.tap)
        delegate?.pressableNodeDidActivate(self)
    }

    private func restoreAppearance() {
        isPressed = false
        background.fillColor = normalColor
        run(.scale(to: 1, duration: 0.08))
    }

    /// Maps the glyph tokens callers already pass to the delivered icon set.
    /// Tokens with no delivered counterpart keep falling through to SF Symbols.
    private static func deliveredIcon(for token: String) -> SKSpriteNode? {
        let name: String
        switch token {
        case "\u{21BB}": name = GameAssets.Icon.restart
        case "\u{2016}": name = GameAssets.Icon.pause
        case "\u{00AB}": name = GameAssets.Icon.rewind
        case "\u{2039}": name = GameAssets.Icon.back
        case "\u{2699}": name = GameAssets.Icon.settings
        default: return nil
        }
        guard let sprite = GameAssets.sprite(name, fitting: CGSize(width: 25, height: 25)) else { return nil }
        return sprite
    }

    private static func systemSymbolName(for token: String) -> String? {
        switch token {
        case "\u{25B6}": return "play.fill"
        case "\u{25A6}": return "square.grid.3x3.fill"
        case "\u{25C9}": return "calendar.circle.fill"
        case "\u{221E}": return "infinity"
        case "\u{2605}": return "star.fill"
        case "\u{2699}": return "gearshape.fill"
        case "\u{2039}": return "chevron.left"
        case "\u{203A}": return "chevron.right"
        case "\u{21BB}": return "arrow.clockwise"
        case "\u{2016}": return "pause.fill"
        case "\u{00AB}": return "backward.end.fill"
        default: return token.isEmpty ? nil : token
        }
    }

    private static func rasterizedSymbol(
        named systemName: String,
        configuration: UIImage.SymbolConfiguration,
        color: UIColor
    ) -> UIImage? {
        guard let symbol = UIImage(systemName: systemName, withConfiguration: configuration)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return nil }
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        return UIGraphicsImageRenderer(size: symbol.size, format: format).image { _ in
            symbol.draw(in: CGRect(origin: .zero, size: symbol.size))
        }
    }
}

final class ToggleNode: SKNode {
    let identifier: String
    var valueChanged: ((Bool) -> Void)?
    private let titleLabel: SKLabelNode
    private let track: SKShapeNode
    private let knob: SKShapeNode
    private(set) var isOn: Bool
    private var isPressed = false

    init(identifier: String, title: String, isOn: Bool, width: CGFloat = 340) {
        self.identifier = identifier
        self.isOn = isOn
        titleLabel = GameTheme.label(title, size: 14, weight: .medium, alignment: .left)
        track = SKShapeNode(rectOf: CGSize(width: 51, height: 31), cornerRadius: 15.5)
        knob = SKShapeNode(circleOfRadius: 12.5)
        super.init()
        isUserInteractionEnabled = true
        titleLabel.position = CGPoint(x: -width / 2, y: 0)
        track.position = CGPoint(x: width / 2 - 26, y: 0)
        track.lineWidth = 1
        knob.strokeColor = UIColor.black.withAlphaComponent(0.15)
        knob.lineWidth = 0.5
        addChild(titleLabel)
        addChild(track)
        track.addChild(knob)
        updateAppearance(animated: false)
        accessibilityLabel = title
        accessibilityTraits = [.button]
        accessibilityValue = isOn ? "On" : "Off"
    }

    required init?(coder aDecoder: NSCoder) { nil }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        flip()
    }

    func setOn(_ on: Bool, animated: Bool) {
        isOn = on
        updateAppearance(animated: animated)
    }

    func containsScenePoint(_ point: CGPoint) -> Bool {
        calculateAccumulatedFrame().insetBy(dx: -3, dy: -3).contains(point)
    }

    /// Container-gesture support, mirroring `PressableNode`. A toggle inside a
    /// scrolling list cannot track touches itself: the scene has to decide
    /// whether a drag is a scroll or a tap, and a node that swallowed the touch
    /// would never give it that chance.
    func beginPressFromContainer() {
        guard !isPressed else { return }
        isPressed = true
        alpha = 0.72
    }

    func cancelPress() {
        guard isPressed else { return }
        isPressed = false
        alpha = 1
    }

    func activateFromContainer() {
        cancelPress()
        flip()
    }

    private func flip() {
        isOn.toggle()
        updateAppearance(animated: true)
        HapticService.shared.play(.tap)
        valueChanged?(isOn)
    }

    private func updateAppearance(animated: Bool) {
        track.fillColor = isOn ? GameTheme.freezeBlue.blended(with: GameTheme.background, amount: 0.28) : GameTheme.background.withAlphaComponent(0.7)
        track.strokeColor = isOn ? GameTheme.jade : GameTheme.divider
        knob.fillColor = GameTheme.ivory
        let targetX: CGFloat = isOn ? 9.5 : -9.5
        if animated && !SaveStore.shared.settings.reduceMotion {
            knob.run(.moveTo(x: targetX, duration: 0.18))
        } else {
            knob.position.x = targetX
        }
        accessibilityValue = isOn ? "On" : "Off"
    }
}

final class ProgressBarNode: SKNode {
    private let width: CGFloat
    private let track: SKShapeNode
    private let fill: SKShapeNode
    private let valueLabel: SKLabelNode?
    private(set) var progress: CGFloat = 0

    init(width: CGFloat, height: CGFloat = 8, showsValue: Bool = false) {
        self.width = width
        track = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: height / 2)
        fill = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: height / 2)
        valueLabel = showsValue ? GameTheme.label("0%", size: 10, color: GameTheme.textSecondary) : nil
        super.init()
        track.fillColor = GameTheme.background.withAlphaComponent(0.88)
        track.strokeColor = GameTheme.divider
        track.lineWidth = 1
        fill.fillColor = GameTheme.freezeBlue
        fill.strokeColor = .clear
        fill.position.x = 0
        fill.xScale = 0.001
        addChild(track)
        addChild(fill)
        if let valueLabel {
            valueLabel.position = CGPoint(x: width / 2 + 22, y: 0)
            addChild(valueLabel)
        }
    }

    required init?(coder aDecoder: NSCoder) { nil }

    func setProgress(_ newValue: CGFloat, animated: Bool = true) {
        progress = ScalarMath.clamp(newValue, 0, 1)
        let scale = max(0.001, progress)
        fill.position.x = -width * (1 - scale) / 2
        if animated && !SaveStore.shared.settings.reduceMotion {
            fill.run(.scaleX(to: scale, duration: 0.18))
        } else {
            fill.xScale = scale
        }
        valueLabel?.text = "\(Int(progress * 100))%"
    }

    func setTint(_ color: UIColor) {
        fill.fillColor = color
    }
}

final class StarRowNode: SKNode {
    private var stars: [SKNode] = []
    private let litColor = GameTheme.brassLight
    private let dimColor = UIColor.white.withAlphaComponent(0.18)

    init(count: Int, size: CGFloat = 22, spacing: CGFloat = 27) {
        super.init()
        let delivered = GameAssets.sprite(GameAssets.star, fitting: CGSize(width: size * 1.25, height: size * 1.25))
        for index in 0..<3 {
            let star: SKNode
            if let delivered {
                // Each star needs its own tint, so the cached texture is shared and
                // only the sprite instances differ.
                let sprite = SKSpriteNode(texture: delivered.texture)
                sprite.size = delivered.size
                star = sprite
            } else {
                star = GameTheme.label("\u{2605}", size: size, color: dimColor)
            }
            star.position.x = CGFloat(index - 1) * spacing
            addChild(star)
            stars.append(star)
        }
        setCount(count, animated: false)
    }

    required init?(coder aDecoder: NSCoder) { nil }

    func setCount(_ count: Int, animated: Bool = false) {
        for (index, star) in stars.enumerated() {
            let lit = index < count
            if let sprite = star as? SKSpriteNode {
                sprite.color = lit ? .clear : UIColor.black
                sprite.colorBlendFactor = lit ? 0 : 0.72
                sprite.alpha = lit ? 1 : 0.42
            } else if let label = star as? SKLabelNode {
                label.fontColor = lit ? litColor : dimColor
            }
            if animated && lit && !SaveStore.shared.settings.reduceMotion {
                star.setScale(0.1)
                star.run(.sequence([.wait(forDuration: Double(index) * 0.12), .scale(to: 1, duration: 0.22)]))
            }
        }
        accessibilityLabel = "\(count) of 3 stars"
    }
}

class BaseScene: SKScene, PressableNodeDelegate {
    private let backgroundLayer = SKNode()
    /// Set when room art is present, which lets the procedural viewport go
    /// translucent instead of painting the artwork out.
    private var hasBackdrop = false
    /// The backdrop is a sibling of `backgroundLayer`, not a child of it, because
    /// it sits at a negative `zPosition`. Held here so a rebuild can take the
    /// previous one down: `buildBackground` runs more than once now, and an
    /// untracked layer would stack a fresh copy of the artwork on every resize.
    private var backdropLayer: SKNode?

    /// The header's copy and the nodes it built, kept so the chrome can be laid
    /// out again when the scene's size changes.
    private var headerSpec: (title: String, subtitle: String?, backAction: Bool)?
    private var headerNodes: [SKNode] = []
    /// The y of the header's lowest edge, for scenes that scroll content
    /// underneath it. Written by `refreshHeader`, so it always describes the
    /// size the scene has now.
    private(set) var headerBottomY: CGFloat = 0

    /// Full-bleed room art for this scene. Scenes that want a chapter-specific
    /// illustration override this.
    var backdropAsset: String? { environment.assetName }

    var environment: GameAssets.Environment { .darkPuzzleRoom }

    override init(size: CGSize) {
        super.init(size: size)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        scaleMode = .resizeFill
        backgroundColor = GameTheme.background
        addChild(backgroundLayer)
    }

    required init?(coder aDecoder: NSCoder) { nil }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        buildBackground()
        HapticService.shared.prepare()
    }

    func buildBackground() {
        buildBackdrop()
        backgroundLayer.removeAllChildren()
        // The decorative chrome takes its accent from the equipped skin, so a
        // skin changes the whole room rather than just the tiles. The vermilion
        // contrast marks stay fixed to keep the warm/cool split the scene reads
        // from.
        let accent = SaveStore.shared.settings.tileSkin.accent
        let viewportSize = CGSize(width: max(0, size.width - 18), height: max(0, size.height - 26))
        let viewport = SKShapeNode(path: GameTheme.chamferedPath(size: viewportSize, cut: 14))
        viewport.fillColor = hasBackdrop ? GameTheme.boardDark.withAlphaComponent(0.40) : GameTheme.boardDark
        viewport.strokeColor = accent.withAlphaComponent(0.25)
        viewport.lineWidth = 1
        backgroundLayer.addChild(viewport)

        let ringCenter = CGPoint(x: size.width * 0.34, y: size.height * 0.27)
        for index in 0..<3 {
            let radius = CGFloat(96 + index * 28)
            let ring = SKShapeNode(circleOfRadius: radius)
            ring.fillColor = .clear
            ring.strokeColor = (index == 1 ? GameTheme.vermilion : accent).withAlphaComponent(index == 1 ? 0.06 : 0.08)
            ring.lineWidth = index == 0 ? 1.4 : 0.8
            ring.position = ringCenter
            backgroundLayer.addChild(ring)
        }
        for index in 0..<24 {
            let angle = CGFloat(index) * .pi / 12
            let length: CGFloat = index % 3 == 0 ? 13 : 7
            let tick = SKShapeNode(rectOf: CGSize(width: 1, height: length))
            tick.fillColor = (index % 6 == 0 ? GameTheme.vermilion : accent).withAlphaComponent(0.14)
            tick.strokeColor = .clear
            tick.position = CGPoint(x: 0, y: 110).rotated(by: -angle) + ringCenter
            tick.zRotation = -angle
            backgroundLayer.addChild(tick)
        }

        let horizonY = -size.height * 0.08
        for index in 0..<9 {
            let startX = -size.width / 2 + CGFloat(index) * size.width / 8
            let path = CGMutablePath()
            path.move(to: CGPoint(x: startX, y: -size.height / 2 + 14))
            path.addLine(to: CGPoint(x: 0, y: horizonY))
            let ray = SKShapeNode(path: path)
            ray.strokeColor = accent.withAlphaComponent(0.055)
            ray.lineWidth = 0.7
            backgroundLayer.addChild(ray)
        }
        for index in 0..<12 {
            let fraction = CGFloat(index) / 11
            let eased = fraction * fraction
            let y = horizonY - eased * (size.height / 2 + horizonY - 14)
            let line = SKShapeNode(rectOf: CGSize(width: max(0, size.width - 30), height: 0.7))
            line.fillColor = accent.withAlphaComponent(0.045 + fraction * 0.025)
            line.strokeColor = .clear
            line.position.y = y
            backgroundLayer.addChild(line)
        }

        let riftPath = CGMutablePath()
        riftPath.move(to: CGPoint(x: -size.width / 2 + 9, y: size.height * 0.18))
        riftPath.addLine(to: CGPoint(x: -size.width * 0.31, y: size.height * 0.12))
        riftPath.addLine(to: CGPoint(x: -size.width * 0.27, y: -size.height * 0.06))
        riftPath.addLine(to: CGPoint(x: -size.width * 0.16, y: -size.height * 0.16))
        let rift = SKShapeNode(path: riftPath)
        rift.strokeColor = GameTheme.vermilion.withAlphaComponent(0.22)
        rift.lineWidth = 2
        rift.glowWidth = 1
        backgroundLayer.addChild(rift)

        for side in [-1.0, 1.0] {
            let rail = SKShapeNode(rectOf: CGSize(width: min(68, size.width * 0.18), height: 2))
            rail.fillColor = side < 0 ? accent : GameTheme.vermilion
            rail.strokeColor = .clear
            rail.position = CGPoint(x: CGFloat(side) * (size.width / 2 - 48), y: size.height / 2 - 14)
            backgroundLayer.addChild(rail)
        }
    }

    /// Room art is drawn aspect-filled behind everything and then dimmed, so the
    /// chrome, panels and body text keep the contrast they had over flat black.
    private func buildBackdrop() {
        backdropLayer?.removeFromParent()
        backdropLayer = nil
        hasBackdrop = false
        guard let asset = backdropAsset, let texture = GameAssets.backdrop(asset) else { return }
        let source = texture.size()
        guard source.width > 0, source.height > 0 else { return }
        hasBackdrop = true
        let layer = SKNode()
        layer.zPosition = -3
        let scale = max(size.width / source.width, size.height / source.height)
        let art = SKSpriteNode(texture: texture)
        art.size = CGSize(width: source.width * scale, height: source.height * scale)
        art.alpha = 0.62
        layer.addChild(art)
        let scrim = SKShapeNode(rectOf: CGSize(width: size.width, height: size.height))
        scrim.fillColor = GameTheme.background.withAlphaComponent(0.52)
        scrim.strokeColor = .clear
        scrim.zPosition = 1
        layer.addChild(scrim)
        backdropLayer = layer
        addChild(layer)
    }

    /// Draws the scene's fixed header. Returns the y of its lowest edge, so a
    /// scene that scrolls content underneath can keep that content clear of it
    /// instead of guessing at the header's height.
    @discardableResult
    func addHeader(title: String, subtitle: String? = nil, backAction: Bool = true) -> CGFloat {
        headerSpec = (title, subtitle, backAction)
        return refreshHeader()
    }

    /// Lays the header out again for the scene's current size.
    ///
    /// A scene is handed to the view the moment it is presented, which can be
    /// before that view has been laid out. The first pass then measures a size
    /// of zero and every y it derives from the safe area is meaningless — the
    /// title lands in the middle of the screen and the scroll band a scene
    /// derives from the header's edge is hundreds of points too low, which
    /// silently strands the top of a scrolling path out of reach. The scene is
    /// resized as soon as the view has real bounds, so the chrome is rebuilt
    /// rather than left where the empty pass put it.
    @discardableResult
    func refreshHeader() -> CGFloat {
        guard let spec = headerSpec else { return headerBottomY }
        headerNodes.forEach { $0.removeFromParent() }
        headerNodes.removeAll()

        let title = spec.title
        let subtitle = spec.subtitle
        let backAction = spec.backAction
        let y = safeTop - 35
        let titleNode = GameTheme.label(title, size: 20, weight: .bold)
        titleNode.fontName = GameTheme.titleFont(size: 20).fontName
        titleNode.position = CGPoint(x: 0, y: y)
        titleNode.name = "sceneHeader"
        addChild(titleNode)
        headerNodes.append(titleNode)
        // `calculateAccumulatedFrame` is already measured in the parent's
        // coordinate system, so it carries the node's own position: adding
        // `position.y` on top counts it twice and reports the header as
        // reaching some 350pt lower than it does. A scene that derives a scroll
        // band from that edge then has its band top pushed off the top of the
        // screen, which silently strands the last stops of a long path out of
        // reach however far the player drags.
        var lowestEdge = titleNode.calculateAccumulatedFrame().minY
        if let subtitle {
            let subtitleNode = GameTheme.label(subtitle, size: 11, color: GameTheme.textSecondary, weight: .medium)
            subtitleNode.position = CGPoint(x: 0, y: y - 27)
            subtitleNode.name = "sceneSubtitle"
            addChild(subtitleNode)
            headerNodes.append(subtitleNode)
            lowestEdge = min(lowestEdge, subtitleNode.calculateAccumulatedFrame().minY)
        }
        if backAction {
            let back = PressableNode(identifier: "back", title: "", icon: "\u{2039}", size: CGSize(width: 48, height: 48), style: .quiet)
            back.position = CGPoint(x: -size.width / 2 + 34, y: y)
            back.delegate = self
            addChild(back)
            headerNodes.append(back)
            // The back control is a 48pt square centred on the title, so on a
            // short header it, not the text, is what reaches lowest.
            lowestEdge = min(lowestEdge, back.calculateAccumulatedFrame().minY)
        }
        // Published here rather than returned for the caller to keep, so a
        // scene that scrolls underneath the header can never be reading an edge
        // measured for a size the scene no longer has.
        headerBottomY = lowestEdge
        return lowestEdge
    }

    /// Lays the chrome out again for the size and safe area the scene has now.
    ///
    /// Called on a resize *and* when the view's safe area arrives, because those
    /// are not the same moment. A scene is handed to the view before that view
    /// has been laid out, so the first pass measures a size of zero and a safe
    /// area of nothing — `safeTop` falls back to its 18pt minimum and the header
    /// lands ~44pt too high. The insets only become real once the view has been
    /// laid out, and the view's bounds do not change when they do, so
    /// `didChangeSize` never fires a second time on its own. Waiting for it left
    /// the header corrected and everything laid out from it still wrong.
    func refreshLayout() {
        // Everything rebuilt here is proportional to the scene, so a pass
        // measured at zero has to be thrown away rather than re-measured: the
        // viewport would be zero-wide, the rings collapsed onto the centre and
        // the room art scaled by zero.
        buildBackground()
        refreshHeader()
        layoutDidChange()
    }

    /// Rebuilds whatever a subclass lays out from the chrome's edges.
    ///
    /// Override this rather than `didChangeSize`. A safe-area change has to get
    /// the same treatment as a resize, and an override of the size callback
    /// would miss every one of them.
    func layoutDidChange() {}

    /// Removes everything a subclass added, leaving the base's own chrome.
    ///
    /// Most subclasses build straight into the scene rather than into a
    /// container, so a relayout that has to place them again needs a way to take
    /// the previous pass down first. The background, the backdrop and the header
    /// belong to the base and are deliberately kept: `refreshLayout` has already
    /// rebuilt those by the time this is called.
    func removeSceneContent() {
        for node in children where node !== backgroundLayer
            && node !== backdropLayer
            && !headerNodes.contains(node) {
            node.removeFromParent()
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        refreshLayout()
    }

    func transitionIn() {
        guard !SaveStore.shared.settings.reduceMotion else { return }
        alpha = 0
        run(.fadeIn(withDuration: 0.22))
    }

    func pressableNodeDidActivate(_ node: PressableNode) {
        if node.identifier == "back" { GameCoordinator.shared.goBack() }
    }
}
