import UIKit

/// Player-selectable tile-face treatments.
///
/// A skin restyles the *body* of a mahjong tile — its face and edge — while the
/// team rail and accent keep the team colour the rules depend on, so no skin can
/// make two teams read alike. Unlocks are derived from campaign stars rather than
/// stored: stars only ever rise, so a skin that was earned can never be re-locked.
enum TileSkin: String, Codable, CaseIterable {
    case classic
    case jade
    case porcelain
    case frost
    case goldleaf
    case silver
    case amber
    case rose
    case pearl

    var title: String {
        switch self {
        case .classic: return "CLASSIC"
        case .jade: return "JADE"
        case .porcelain: return "PORCELAIN"
        case .goldleaf: return "GOLD LEAF"
        case .frost: return "FROST"
        case .silver: return "SILVER"
        case .amber: return "AMBER"
        case .rose: return "ROSE"
        case .pearl: return "PEARL"
        }
    }

    var isDefault: Bool { self == .classic }

    /// Campaign stars needed before this skin can be equipped. Zero means the
    /// skin is available from the start.
    var starRequirement: Int {
        switch self {
        case .classic, .jade, .porcelain, .frost: return 0
        case .goldleaf: return 30
        case .silver: return 60
        case .amber: return 100
        case .rose: return 140
        case .pearl: return 180
        }
    }

    func isUnlocked(given totalStars: Int) -> Bool {
        totalStars >= starRequirement
    }

    /// The face colour the surface is built from. Team tint is layered on top in
    /// the renderer, so a skin and a team never fight over the same channel.
    var surfaceBase: UIColor {
        switch self {
        case .classic: return GameTheme.ivory
        case .jade: return GameTheme.ivory.blended(with: GameTheme.jade, amount: 0.28)
        case .porcelain: return GameTheme.ivory.blended(with: GameTheme.freezeBlue, amount: 0.22)
        case .goldleaf: return GameTheme.ivory.blended(with: GameTheme.brassLight, amount: 0.30)
        case .frost: return GameTheme.ivory.blended(with: GameTheme.freezeBlue, amount: 0.38)
        case .silver: return GameTheme.ivory.blended(with: UIColor(red: 0.72, green: 0.78, blue: 0.85, alpha: 1), amount: 0.30)
        case .amber: return GameTheme.ivory.blended(with: GameTheme.warning, amount: 0.26)
        case .rose: return GameTheme.ivory.blended(with: GameTheme.vermilion, amount: 0.16)
        case .pearl: return GameTheme.ivory.blended(with: GameTheme.freezeWhite, amount: 0.55)
        }
    }

    /// The edge colour. Team colour still bends it, so a red-team tile reads red
    /// on any skin.
    var edgeBase: UIColor {
        switch self {
        case .classic: return GameTheme.ivoryShadow
        case .jade: return GameTheme.jade.blended(with: GameTheme.background, amount: 0.30)
        case .porcelain: return GameTheme.freezeBlue.blended(with: GameTheme.background, amount: 0.35)
        case .goldleaf: return GameTheme.brass
        case .frost: return GameTheme.freezeBlue.blended(with: GameTheme.background, amount: 0.28)
        case .silver: return UIColor(red: 0.42, green: 0.48, blue: 0.58, alpha: 1)
        case .amber: return GameTheme.warning.blended(with: GameTheme.background, amount: 0.30)
        case .rose: return GameTheme.vermilion.blended(with: GameTheme.background, amount: 0.25)
        case .pearl: return GameTheme.freezeWhite.blended(with: GameTheme.background, amount: 0.35)
        }
    }

    /// The interface accent this skin projects — the colour that replaces the
    /// default ice-blue in decorative chrome (backdrop rings, panel rails).
    /// Kept separate from `surfaceBase`: a tile face must stay legible under
    /// the ink symbols, while the accent must read against the near-black ground.
    var accent: UIColor {
        switch self {
        case .classic: return GameTheme.freezeBlue
        case .jade: return GameTheme.jade
        case .porcelain: return GameTheme.freezeBlue
        case .frost: return GameTheme.freezeBlue.blended(with: GameTheme.freezeWhite, amount: 0.25)
        case .goldleaf: return GameTheme.brassLight
        case .silver: return UIColor(red: 0.62, green: 0.72, blue: 0.82, alpha: 1)
        case .amber: return GameTheme.warning
        case .rose: return GameTheme.vermilion
        case .pearl: return GameTheme.freezeWhite
        }
    }
}
