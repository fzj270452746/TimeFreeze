import SpriteKit
import UIKit

enum MahjongTileRenderer {
    static func makeFaceNode(
        suit: MahjongSuit,
        face: MahjongFace,
        team: TileTeam,
        size: CGSize = LayoutMetrics.tileSize,
        compact: Bool = false,
        skin: TileSkin = .classic
    ) -> SKNode {
        let root = SKNode()
        root.name = "tileFace"
        let shadow = SKShapeNode(rectOf: size, cornerRadius: min(7, size.width * 0.15))
        shadow.fillColor = UIColor.black.withAlphaComponent(0.36)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 2.8, y: -4)
        root.addChild(shadow)
        let edge = SKShapeNode(rectOf: size, cornerRadius: min(7, size.width * 0.15))
        edge.fillColor = edgeColor(team, skin: skin)
        edge.strokeColor = UIColor.black.withAlphaComponent(0.3)
        edge.lineWidth = 1
        edge.position.y = -2
        root.addChild(edge)
        let surfaceSize = CGSize(width: size.width - 3, height: size.height - 5)
        let surface = SKShapeNode(rectOf: surfaceSize, cornerRadius: min(6, size.width * 0.13))
        surface.fillColor = surfaceColor(team, skin: skin)
        surface.strokeColor = UIColor.white.withAlphaComponent(0.58)
        surface.lineWidth = 1.2
        surface.position.y = 1
        root.addChild(surface)
        let teamRail = SKShapeNode(rectOf: CGSize(width: 2, height: surfaceSize.height * 0.38), cornerRadius: 1)
        teamRail.fillColor = accentColor(team)
        teamRail.strokeColor = .clear
        teamRail.position = CGPoint(x: surfaceSize.width / 2 - 3, y: -surfaceSize.height * 0.17)
        surface.addChild(teamRail)
        let highlight = SKShapeNode(rectOf: CGSize(width: surfaceSize.width - 5, height: 1.2), cornerRadius: 0.6)
        highlight.fillColor = UIColor.white.withAlphaComponent(0.52)
        highlight.strokeColor = .clear
        highlight.position = CGPoint(x: -0.5, y: surfaceSize.height / 2 - 5)
        surface.addChild(highlight)
        addSymbol(to: surface, suit: suit, face: face, size: size, compact: compact)
        let shine = SKShapeNode(ellipseOf: CGSize(width: size.width * 0.52, height: size.height * 0.16))
        shine.fillColor = UIColor.white.withAlphaComponent(0.09)
        shine.strokeColor = .clear
        shine.position = CGPoint(x: -size.width * 0.13, y: size.height * 0.25)
        shine.zRotation = -0.22
        surface.addChild(shine)
        return root
    }

    static func updateSelection(_ node: SKNode, selected: Bool, frozen: Bool) {
        node.childNode(withName: "selectionRing")?.removeFromParent()
        guard selected else { return }
        let ring = SKShapeNode(rectOf: CGSize(width: 49, height: 63), cornerRadius: 9)
        ring.name = "selectionRing"
        ring.fillColor = .clear
        ring.strokeColor = frozen ? GameTheme.freezeBlue : GameTheme.brassLight
        ring.glowWidth = frozen ? 5 : 3
        ring.lineWidth = 2
        ring.zPosition = 20
        node.addChild(ring)
    }

    static func makeGhost(from tile: TileDefinition, skin: TileSkin = .classic) -> SKNode {
        let node = makeFaceNode(suit: tile.suit, face: tile.face, team: .blue, skin: skin)
        node.alpha = 0.22
        node.setScale(0.96)
        return node
    }

    private static func surfaceColor(_ team: TileTeam, skin: TileSkin) -> UIColor {
        guard let tint = teamTint(team) else { return skin.surfaceBase }
        return skin.surfaceBase.blended(with: tint, amount: surfaceBlend(team))
    }

    private static func edgeColor(_ team: TileTeam, skin: TileSkin) -> UIColor {
        guard let tint = teamTint(team) else { return skin.edgeBase }
        return skin.edgeBase.blended(with: tint, amount: edgeBlend(team))
    }

    /// The colour a team adds to a tile's body. Ivory tiles are the neutral base,
    /// so they carry no tint of their own.
    private static func teamTint(_ team: TileTeam) -> UIColor? {
        switch team {
        case .ivory: return nil
        case .jade: return GameTheme.jade
        case .red: return GameTheme.vermilion
        case .blue: return GameTheme.freezeBlue
        case .gold: return GameTheme.brassLight
        }
    }

    private static func surfaceBlend(_ team: TileTeam) -> CGFloat {
        switch team {
        case .ivory: return 0
        case .jade: return 0.17
        case .red: return 0.15
        case .blue: return 0.18
        case .gold: return 0.20
        }
    }

    private static func edgeBlend(_ team: TileTeam) -> CGFloat {
        switch team {
        case .ivory: return 0
        case .jade: return 0.45
        case .red: return 0.45
        case .blue: return 0.45
        case .gold: return 0.55
        }
    }

    private static func accentColor(_ team: TileTeam) -> UIColor {
        switch team {
        case .ivory: return GameTheme.brassLight
        case .jade: return GameTheme.jade
        case .red: return GameTheme.vermilion
        case .blue: return GameTheme.freezeBlue
        case .gold: return GameTheme.brassLight
        }
    }

    private static func addSymbol(
        to surface: SKNode,
        suit: MahjongSuit,
        face: MahjongFace,
        size: CGSize,
        compact: Bool
    ) {
        let scale = min(size.width / 42, size.height / 56)
        switch suit {
        case .characters:
            addCharacterSymbol(to: surface, value: face.numericValue ?? 1, scale: scale, compact: compact)
        case .bamboo:
            addBambooSymbol(to: surface, value: face.numericValue ?? 1, scale: scale)
        case .dots:
            addDotSymbol(to: surface, value: face.numericValue ?? 1, scale: scale)
        case .wind:
            addWindSymbol(to: surface, face: face, scale: scale)
        case .dragon:
            addDragonSymbol(to: surface, face: face, scale: scale)
        }
    }

    private static func addCharacterSymbol(to parent: SKNode, value: Int, scale: CGFloat, compact: Bool) {
        let number = GameTheme.label("\(value)", size: (compact ? 15 : 17) * scale, color: GameTheme.ink, weight: .heavy)
        number.position = CGPoint(x: 0, y: 10 * scale)
        parent.addChild(number)
        let wanFont = UIFont(name: "PingFangSC-Semibold", size: (compact ? 17 : 20) * scale)
            ?? UIFont.systemFont(ofSize: (compact ? 17 : 20) * scale, weight: .semibold)
        let wan = SKLabelNode(fontNamed: wanFont.fontName)
        wan.text = "萬"
        wan.fontSize = wanFont.pointSize
        wan.fontColor = GameTheme.vermilion
        wan.horizontalAlignmentMode = .center
        wan.verticalAlignmentMode = .center
        wan.position = CGPoint(x: 0, y: -10 * scale)
        parent.addChild(wan)
    }

    private static func addBambooSymbol(to parent: SKNode, value: Int, scale: CGFloat) {
        let positions = pipPositions(for: value)
        for (index, position) in positions.enumerated() {
            let stem = SKShapeNode(rectOf: CGSize(width: 3.4 * scale, height: 11 * scale), cornerRadius: 1.7 * scale)
            stem.fillColor = index % 3 == 0 ? GameTheme.vermilion : GameTheme.jade
            stem.strokeColor = GameTheme.ink.withAlphaComponent(0.28)
            stem.lineWidth = 0.5
            stem.position = CGPoint(x: position.x * scale, y: position.y * scale)
            stem.zRotation = index % 2 == 0 ? 0.08 : -0.08
            parent.addChild(stem)
            let joint = SKShapeNode(rectOf: CGSize(width: 5 * scale, height: 1.3 * scale), cornerRadius: 0.5)
            joint.fillColor = GameTheme.brassLight
            joint.strokeColor = .clear
            stem.addChild(joint)
        }
    }

    private static func addDotSymbol(to parent: SKNode, value: Int, scale: CGFloat) {
        let positions = pipPositions(for: value)
        for (index, position) in positions.enumerated() {
            let outer = SKShapeNode(circleOfRadius: 4.2 * scale)
            outer.fillColor = index % 3 == 0 ? GameTheme.vermilion : GameTheme.jade
            outer.strokeColor = GameTheme.ink.withAlphaComponent(0.35)
            outer.lineWidth = 0.6
            outer.position = CGPoint(x: position.x * scale, y: position.y * scale)
            parent.addChild(outer)
            let inner = SKShapeNode(circleOfRadius: 1.6 * scale)
            inner.fillColor = GameTheme.ivory
            inner.strokeColor = .clear
            outer.addChild(inner)
        }
    }

    private static func addWindSymbol(to parent: SKNode, face: MahjongFace, scale: CGFloat) {
        let letter = GameTheme.label(face.glyph, size: 25 * scale, color: GameTheme.ink, weight: .black)
        letter.position.y = 1
        parent.addChild(letter)
        let compass = SKShapeNode(circleOfRadius: 14 * scale)
        compass.fillColor = .clear
        compass.strokeColor = GameTheme.brass
        compass.lineWidth = 1
        parent.addChild(compass)
        let direction: CGFloat
        switch face {
        case .east: direction = 0
        case .north: direction = .pi / 2
        case .west: direction = .pi
        case .south: direction = -.pi / 2
        default: direction = 0
        }
        let pointer = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 16 * scale, y: 0))
        path.addLine(to: CGPoint(x: 11 * scale, y: 3 * scale))
        path.addLine(to: CGPoint(x: 11 * scale, y: -3 * scale))
        path.closeSubpath()
        pointer.path = path
        pointer.fillColor = GameTheme.vermilion
        pointer.strokeColor = .clear
        pointer.zRotation = direction
        parent.addChild(pointer)
    }

    private static func addDragonSymbol(to parent: SKNode, face: MahjongFace, scale: CGFloat) {
        let color: UIColor
        let letter: String
        switch face {
        case .redDragon:
            color = GameTheme.vermilion
            letter = "中"
        case .greenDragon:
            color = GameTheme.jade
            letter = "發"
        default:
            color = GameTheme.freezeBlue.blended(with: GameTheme.ink, amount: 0.35)
            letter = "白"
        }
        let diamond = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 17 * scale))
        path.addLine(to: CGPoint(x: 13 * scale, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -17 * scale))
        path.addLine(to: CGPoint(x: -13 * scale, y: 0))
        path.closeSubpath()
        diamond.path = path
        diamond.fillColor = color.withAlphaComponent(0.08)
        diamond.strokeColor = color
        diamond.lineWidth = 2
        parent.addChild(diamond)
        let glyphFont = UIFont(name: "PingFangSC-Semibold", size: 22 * scale)
            ?? UIFont.systemFont(ofSize: 22 * scale, weight: .bold)
        let glyph = SKLabelNode(fontNamed: glyphFont.fontName)
        glyph.text = letter
        glyph.fontSize = glyphFont.pointSize
        glyph.fontColor = color
        glyph.horizontalAlignmentMode = .center
        glyph.verticalAlignmentMode = .center
        parent.addChild(glyph)
    }

    private static func pipPositions(for value: Int) -> [CGPoint] {
        let x: CGFloat = 9
        let y: CGFloat = 13
        switch ScalarMath.clamp(value, 1, 9) {
        case 1: return [.zero]
        case 2: return [CGPoint(x: -x, y: y), CGPoint(x: x, y: -y)]
        case 3: return [CGPoint(x: -x, y: y), .zero, CGPoint(x: x, y: -y)]
        case 4: return [CGPoint(x: -x, y: y), CGPoint(x: x, y: y), CGPoint(x: -x, y: -y), CGPoint(x: x, y: -y)]
        case 5: return [CGPoint(x: -x, y: y), CGPoint(x: x, y: y), .zero, CGPoint(x: -x, y: -y), CGPoint(x: x, y: -y)]
        case 6: return [-y, 0, y].flatMap { py in [CGPoint(x: -x, y: py), CGPoint(x: x, y: py)] }
        case 7: return [CGPoint(x: -x, y: y), CGPoint(x: x, y: y), .zero] + [-y, CGFloat(0)].flatMap { py in [CGPoint(x: -x, y: py), CGPoint(x: x, y: py)] }
        case 8: return [-y, -y / 3, y / 3, y].flatMap { py in [CGPoint(x: -x, y: py), CGPoint(x: x, y: py)] }
        default: return [-y, 0, y].flatMap { py in [CGPoint(x: -x, y: py), CGPoint(x: 0, y: py), CGPoint(x: x, y: py)] }
        }
    }
}
