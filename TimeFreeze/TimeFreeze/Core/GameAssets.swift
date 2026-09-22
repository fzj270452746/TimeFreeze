import SpriteKit
import UIKit

/// Delivered sprite art is 2048x2048 RGBA with a wide transparent margin — the
/// subject usually fills between 5% and 60% of the canvas — so using it as-is
/// would draw every gate, switch and icon at a fraction of the size asked for.
/// Each sprite is therefore downscaled on first use and cropped to the bounding
/// box of its non-transparent pixels.
///
/// The art already carries a clean alpha channel with anti-aliased edges, so
/// nothing is keyed: transparency is used exactly as delivered. The 2048 px
/// source is cut down to 512 px first, since nothing on screen is drawn above
/// roughly 600 px, and the trimmed result is cached for the life of the process.
///
/// Backdrops are RGB with no alpha and are used untouched — see `backdrop(_:)`.
///
/// Every entry point returns `nil` when an asset is absent, and every caller
/// keeps the procedural drawing it replaced as the fallback. The game has to stay
/// playable and good looking with a partially delivered asset folder.
enum GameAssets {

    // MARK: - Sprite lookup

    /// A trimmed sprite laid out to fit inside `box` without distortion.
    static func sprite(_ name: String, fitting box: CGSize) -> SKSpriteNode? {
        guard let image = trimmedImage(named: name) else { return nil }
        guard box.width > 0, box.height > 0 else { return nil }
        let node = SKSpriteNode(texture: SKTexture(image: image))
        node.size = fittedSize(of: image.size, in: box)
        return node
    }

    /// A trimmed sprite stretched to exactly `size`. Used where the art is a floor
    /// decal that should match the region it marks rather than keep its own aspect.
    static func stretchedSprite(_ name: String, size: CGSize) -> SKSpriteNode? {
        guard let image = trimmedImage(named: name) else { return nil }
        let node = SKSpriteNode(texture: SKTexture(image: image))
        node.size = size
        return node
    }

    /// A trimmed sprite sized by height alone, width following the art.
    static func sprite(_ name: String, height: CGFloat) -> SKSpriteNode? {
        guard let image = trimmedImage(named: name) else { return nil }
        let ratio = image.size.width / max(1, image.size.height)
        return sprite(name, fitting: CGSize(width: height * ratio, height: height))
    }

    /// Full-bleed art — backgrounds and chapter illustrations. These are RGB with
    /// no alpha and cover the whole viewport, so they are used untouched.
    static func backdrop(_ name: String) -> SKTexture? {
        UIImage(named: name) == nil ? nil : SKTexture(imageNamed: name)
    }

    static func has(_ name: String) -> Bool { UIImage(named: name) != nil }

    // MARK: - Cache

    private static var trimmedCache: [String: UIImage] = [:]

    private static func trimmedImage(named name: String) -> UIImage? {
        if let cached = trimmedCache[name] { return cached }
        guard let source = UIImage(named: name) else { return nil }
        let small = downscaled(source, longestSide: 512)
        let trimmed = trimToContent(in: small) ?? small
        trimmedCache[name] = trimmed
        return trimmed
    }

    private static func fittedSize(of source: CGSize, in box: CGSize) -> CGSize {
        let scale = min(box.width / max(1, source.width), box.height / max(1, source.height))
        return CGSize(width: source.width * scale, height: source.height * scale)
    }

    private static func downscaled(_ image: UIImage, longestSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > longestSide else { return image }
        let ratio = longestSide / longest
        let target = CGSize(
            width: max(1, (image.size.width * ratio).rounded()),
            height: max(1, (image.size.height * ratio).rounded())
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // MARK: - Trimming

    /// Crops `image` to the bounding box of its non-transparent pixels, or returns
    /// nil when there is nothing to crop — no alpha channel, no content, or
    /// content that already fills the frame.
    ///
    /// The delivered art keeps a wide empty margin around each subject, and that
    /// margin is what makes a 40 pt icon draw at 5 pt: the sprite is fitted by its
    /// frame, not by what is visible inside it. Cropping to the content box makes
    /// the requested size mean the size of the thing on screen.
    ///
    /// Transparency is taken as delivered. Nothing is keyed, so the anti-aliased
    /// edges the generator produced survive intact and there is no halo to
    /// feather and no interior highlight to accidentally erase.
    private static func trimToContent(in image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let pixelCount = width * height
        guard width > 2, height > 2, pixelCount <= 4_194_304 else { return nil }

        let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount * 4)
        defer { pixels.deallocate() }
        pixels.initialize(repeating: 0, count: pixelCount * 4)

        // Scoped so the context is released before the buffer is read below.
        do {
            guard let context = CGContext(
                data: pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        // Anything at or below this alpha is generator noise in the empty margin;
        // counting it as content would leave the crop box at full size.
        let alphaThreshold: UInt8 = 16
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where pixels[(row + x) * 4 + 3] > alphaThreshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        guard minX > 0 || minY > 0 || maxX < width - 1 || maxY < height - 1 else { return nil }

        let croppedWidth = maxX - minX + 1
        let croppedHeight = maxY - minY + 1
        let cropped = UnsafeMutablePointer<UInt8>.allocate(capacity: croppedWidth * croppedHeight * 4)
        defer { cropped.deallocate() }
        for row in 0..<croppedHeight {
            let source = pixels.advanced(by: ((minY + row) * width + minX) * 4)
            cropped.advanced(by: row * croppedWidth * 4).update(from: source, count: croppedWidth * 4)
        }

        guard let provider = CGDataProvider(
            data: Data(bytes: cropped, count: croppedWidth * croppedHeight * 4) as CFData
        ), let result = CGImage(
            width: croppedWidth,
            height: croppedHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: croppedWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return nil }
        return UIImage(cgImage: result)
    }
}

// MARK: - Named art

/// Every delivered file name lives here, so a rename in `Assets.xcassets` is a
/// one-line change rather than a grep.
extension GameAssets {

    /// Chapter-scoped playfield art. Each environment covers a band of chapters
    /// so the table changes as the campaign moves from wood to stone.
    enum Environment {
        case woodTable
        case darkPuzzleRoom
        case greenFelt
        case marbleTable
        case machineLab
        case stoneTemple

        static func forChapter(_ chapter: Int) -> Environment {
            switch chapter {
            case ..<3: return .woodTable
            case 3...5: return .darkPuzzleRoom
            case 6: return .greenFelt
            case 7: return .marbleTable
            case 8...9: return .machineLab
            default: return .stoneTemple
            }
        }

        var assetName: String {
            switch self {
            case .woodTable: return "bg_env_wood_table_base"
            case .darkPuzzleRoom: return "bg_env_dark_puzzle_room_base"
            case .greenFelt: return "bg_env_green_felt_base"
            case .marbleTable: return "bg_env_marble_table_base"
            case .machineLab: return "bg_env_machine_lab_base"
            case .stoneTemple: return "bg_env_stone_temple_base"
            }
        }
    }

    enum ChapterArt {
        private static let illustrations = [
            "chapter_01_first_freeze",
            "chapter_02_moving_world",
            "chapter_03_moving_gates",
            "chapter_04_tile_control",
            "chapter_05_direction",
            "chapter_06_gravity",
            "chapter_07_portals",
            "chapter_08_machines",
            "chapter_09_chain_reaction",
            "chapter_10_time_master"
        ]

        static func illustration(_ chapter: Int) -> String {
            illustrations[max(0, min(illustrations.count - 1, chapter - 1))]
        }

        static func badge(_ chapter: Int) -> String {
            String(format: "ui_chapter_badge_%02d", max(1, min(10, chapter)))
        }
    }

    enum Icon {
        static let back = "icon_back"
        static let check = "icon_check"
        static let close = "icon_close"
        static let lock = "icon_lock"
        static let pause = "icon_pause"
        static let restart = "icon_restart"
        static let rewind = "icon_rewind"
        static let settings = "icon_settings"
    }

    enum Mechanic {
        static let gate = "mech_gate"
        static let rotatingGate = "mech_rotating_gate"
        static let switchControl = "mech_switch"
        static let pressurePlate = "mech_pressure_plate"
        static let conveyor = "mech_conveyor"
        static let portalIn = "mech_portal_in"
        static let portalOut = "mech_portal_out"
        static let magnet = "mech_magnet"
        static let mirror = "mech_mirror"
        static let rotatingPlatform = "mech_rotating_platform"
        static let pendulum = "mech_pendulum"
        static let freezeZone = "mech_freeze_zone"
        static let noFreezeZone = "mech_no_freeze_zone"
        static let reverseZone = "mech_reverse_zone"
        static let partialFreezeZone = "mech_partial_freeze_zone"
        static let hazard = "mech_hazard"
        static let bridge = "mech_bridge"
    }

    static let star = "ui_star"
}

