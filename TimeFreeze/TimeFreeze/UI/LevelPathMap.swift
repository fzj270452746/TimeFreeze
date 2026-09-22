import CoreGraphics
import Foundation

/// Where a chapter's levels sit along its vertical path.
///
/// The map is deliberately pure geometry: it knows nothing about progress,
/// rendering or the scene. That keeps the winding shape in one place, so the
/// stop nodes, the trail drawn between them and the camera's scroll limits all
/// agree by construction rather than by three copies of the same arithmetic.
///
/// The path runs bottom to top — the first level of a chapter is the lowest
/// stop and the twentieth is the highest, with the destination beyond it. That
/// direction is what makes finishing a chapter read as arriving somewhere
/// rather than as reaching the end of a list.
struct LevelPathMap {

    /// One stop on the path. `indexInChapter` is 1-based to match the copy in
    /// `CampaignCopy` and the numbering the player sees.
    struct Stop {
        let indexInChapter: Int
        let position: CGPoint

        /// The level id this stop starts, for a 20-level chapter.
        func levelID(chapter: Int) -> Int {
            (chapter - 1) * 20 + indexInChapter
        }
    }

    /// Vertical distance between two consecutive stops. Large enough that a
    /// stop's number, stars and best-freeze line all fit without crowding the
    /// stops above and below it.
    static let stopSpacing: CGFloat = 92

    /// How far the path swings left and right of the centre line. Capped so a
    /// narrow phone keeps the swing inside the viewport.
    static func amplitude(forWidth width: CGFloat) -> CGFloat {
        min(96, max(38, width * 0.24))
    }

    /// Horizontal offset of a stop from the chapter's centre line.
    ///
    /// A sine rather than a random walk: the path has to look the same every
    /// time the chapter is opened, and it has to be a pure function of the
    /// index so the trail, the nodes and the camera all derive the same shape.
    static func offsetX(forIndex index: Int, width: CGFloat) -> CGFloat {
        let phase = Double(index - 1) * 0.42
        return CGFloat(sin(phase)) * amplitude(forWidth: width)
    }

    /// Stops for `chapter`, ordered from level 1 upward.
    ///
    /// The whole path is built around `originY`, which the scene sets to the
    /// bottom of the scrollable band so the first level sits just above the
    /// fixed footer.
    static func stops(chapter: Int, width: CGFloat, originY: CGFloat) -> [Stop] {
        (1...CampaignCopy.levelsPerChapter).map { index in
            Stop(
                indexInChapter: index,
                position: CGPoint(
                    x: offsetX(forIndex: index, width: width),
                    y: originY + CGFloat(index - 1) * stopSpacing
                )
            )
        }
    }

    /// The chapter's destination, one stop beyond the last level.
    static func destination(chapter: Int, width: CGFloat, originY: CGFloat) -> CGPoint {
        CGPoint(
            x: offsetX(forIndex: CampaignCopy.levelsPerChapter + 1, width: width),
            y: originY + CGFloat(CampaignCopy.levelsPerChapter) * stopSpacing
        )
    }

    /// Total scrollable height of the path, destination included.
    static var contentHeight: CGFloat {
        CGFloat(CampaignCopy.levelsPerChapter) * stopSpacing
    }
}
