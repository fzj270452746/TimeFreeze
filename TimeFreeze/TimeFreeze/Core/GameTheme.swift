import SpriteKit
import UIKit

enum GameTheme {
    // Chrono arena: obsidian hardware, luminous time energy and warm tile faces.
    static let background = UIColor(red: 0.018, green: 0.020, blue: 0.036, alpha: 1)
    static let board = UIColor(red: 0.030, green: 0.110, blue: 0.120, alpha: 1)
    static let boardLight = UIColor(red: 0.055, green: 0.175, blue: 0.185, alpha: 1)
    static let boardDark = UIColor(red: 0.020, green: 0.035, blue: 0.055, alpha: 1)
    static let ivory = UIColor(red: 0.965, green: 0.935, blue: 0.835, alpha: 1)
    static let ivoryShadow = UIColor(red: 0.48, green: 0.48, blue: 0.43, alpha: 1)
    static let ink = UIColor(red: 0.035, green: 0.052, blue: 0.075, alpha: 1)
    static let mutedInk = UIColor(red: 0.27, green: 0.31, blue: 0.38, alpha: 1)
    static let brass = UIColor(red: 0.95, green: 0.55, blue: 0.12, alpha: 1)
    static let brassLight = UIColor(red: 1.00, green: 0.79, blue: 0.27, alpha: 1)
    static let freezeBlue = UIColor(red: 0.22, green: 0.96, blue: 0.84, alpha: 1)
    static let freezeWhite = UIColor(red: 0.88, green: 1.00, blue: 0.98, alpha: 1)
    static let jade = UIColor(red: 0.43, green: 0.96, blue: 0.48, alpha: 1)
    static let vermilion = UIColor(red: 1.00, green: 0.20, blue: 0.50, alpha: 1)
    static let warning = UIColor(red: 1.00, green: 0.42, blue: 0.16, alpha: 1)
    static let panel = UIColor(red: 0.035, green: 0.040, blue: 0.070, alpha: 0.98)
    static let divider = UIColor(red: 0.42, green: 0.63, blue: 0.68, alpha: 0.30)
    static let textPrimary = UIColor(red: 0.93, green: 0.97, blue: 0.98, alpha: 1)
    static let textSecondary = UIColor(red: 0.54, green: 0.64, blue: 0.68, alpha: 1)

    static func displayFont(size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
        let name: String
        switch weight.rawValue {
        case ..<UIFont.Weight.regular.rawValue: name = "AvenirNext-Regular"
        case ..<UIFont.Weight.semibold.rawValue: name = "AvenirNext-Medium"
        case ..<UIFont.Weight.bold.rawValue: name = "AvenirNext-DemiBold"
        case ..<UIFont.Weight.heavy.rawValue: name = "AvenirNext-Bold"
        default: name = "AvenirNext-Heavy"
        }
        return UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)
    }

    static func monoFont(size: CGFloat, weight: UIFont.Weight = .medium) -> UIFont {
        let name = weight.rawValue >= UIFont.Weight.bold.rawValue ? "Menlo-Bold" : "Menlo-Regular"
        return UIFont(name: name, size: size) ?? UIFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func titleFont(size: CGFloat) -> UIFont {
        UIFont(name: "AvenirNextCondensed-Heavy", size: size) ?? UIFont.systemFont(ofSize: size, weight: .black)
    }

    static func label(
        _ text: String,
        size: CGFloat,
        color: UIColor = textPrimary,
        weight: UIFont.Weight = .semibold,
        alignment: SKLabelHorizontalAlignmentMode = .center
    ) -> SKLabelNode {
        let node = SKLabelNode(fontNamed: displayFont(size: size, weight: weight).fontName)
        node.text = text
        node.fontSize = size
        node.fontColor = color
        node.horizontalAlignmentMode = alignment
        node.verticalAlignmentMode = .center
        return node
    }

    static func roundedPanel(size: CGSize, radius: CGFloat = 8, fill: UIColor = panel) -> SKShapeNode {
        let accent = SaveStore.shared.settings.tileSkin.accent
        let cut = min(radius, min(size.width, size.height) * 0.18)
        let panel = SKShapeNode(path: chamferedPath(size: size, cut: cut))
        panel.fillColor = fill
        panel.strokeColor = divider
        panel.lineWidth = 1.2
        let insetSize = CGSize(width: max(1, size.width - 8), height: max(1, size.height - 8))
        let inset = SKShapeNode(path: chamferedPath(size: insetSize, cut: max(2, cut - 2)))
        inset.fillColor = .clear
        inset.strokeColor = accent.withAlphaComponent(0.13)
        inset.lineWidth = 0.7
        panel.addChild(inset)

        let topRail = SKShapeNode(rectOf: CGSize(width: min(54, size.width * 0.22), height: 2))
        topRail.fillColor = accent
        topRail.strokeColor = .clear
        topRail.position = CGPoint(x: -size.width / 2 + min(38, size.width * 0.18), y: size.height / 2 - 1)
        panel.addChild(topRail)
        let bottomRail = SKShapeNode(rectOf: CGSize(width: min(34, size.width * 0.14), height: 2))
        bottomRail.fillColor = vermilion
        bottomRail.strokeColor = .clear
        bottomRail.position = CGPoint(x: size.width / 2 - min(27, size.width * 0.13), y: -size.height / 2 + 1)
        panel.addChild(bottomRail)
        return panel
    }

    static func chamferedPath(size: CGSize, cut: CGFloat = 8) -> CGPath {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let bevel = max(0, min(cut, min(halfWidth, halfHeight)))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -halfWidth + bevel, y: halfHeight))
        path.addLine(to: CGPoint(x: halfWidth - bevel, y: halfHeight))
        path.addLine(to: CGPoint(x: halfWidth, y: halfHeight - bevel))
        path.addLine(to: CGPoint(x: halfWidth, y: -halfHeight + bevel))
        path.addLine(to: CGPoint(x: halfWidth - bevel, y: -halfHeight))
        path.addLine(to: CGPoint(x: -halfWidth + bevel, y: -halfHeight))
        path.addLine(to: CGPoint(x: -halfWidth, y: -halfHeight + bevel))
        path.addLine(to: CGPoint(x: -halfWidth, y: halfHeight - bevel))
        path.closeSubpath()
        return path
    }
}

enum LayoutMetrics {
    static let referenceSize = CGSize(width: 390, height: 844)
    static let horizontalMargin: CGFloat = 20
    static let minimumTouch: CGFloat = 44
    static let controlGap: CGFloat = 10
    static let boardRadius: CGFloat = 10
    static let tileSize = CGSize(width: 42, height: 56)
    static let compactTileSize = CGSize(width: 34, height: 46)
    static let topHUDHeight: CGFloat = 86
    static let bottomHUDHeight: CGFloat = 112
}

extension SKScene {
    var safeTop: CGFloat { size.height / 2 - max(view?.safeAreaInsets.top ?? 0, 18) }
    var safeBottom: CGFloat { -size.height / 2 + max(view?.safeAreaInsets.bottom ?? 0, 12) }
}

extension UIColor {
    func blended(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = max(0, min(1, amount))
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t
        )
    }
}
