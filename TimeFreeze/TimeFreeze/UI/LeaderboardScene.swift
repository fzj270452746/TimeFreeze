import SpriteKit
import UIKit

/// The boards the service can return, in the order the tabs show them.
enum LeaderboardBoard: CaseIterable {
    case campaign
    case endless
    case daily
    case achievements

    var title: String {
        switch self {
        case .campaign: return "CAMPAIGN"
        case .endless: return "ENDLESS"
        case .daily: return "DAILY"
        // Not "MASTERY": that word already names the achievements screen in the
        // menu, and one tab meaning "everyone's marks" next to a menu entry
        // meaning "my marks" reads as the same thing twice.
        case .achievements: return "MARKS"
        }
    }

    /// The column heading above the right-hand number.
    var metric: String {
        switch self {
        case .campaign: return "STARS"
        case .endless: return "STAGE"
        case .daily: return "SCORE"
        case .achievements: return "MARKS"
        }
    }

    var type: CloudLeaderboardType {
        switch self {
        case .campaign: return .campaign
        case .endless: return .endless
        case .daily: return .daily
        case .achievements: return .achievements
        }
    }
}

/// The leaderboard, as a board of tabs over a scrolling list.
///
/// Every value shown here is a projection of the local save. The rows the service
/// returns are never folded back into `PlayerProgress` — the cloud copy is
/// write-only by design, so this screen only ever reads.
final class LeaderboardScene: BaseScene {

    fileprivate enum Layout {
        static let rowHeight: CGFloat = 46
        static let rowGap: CGFloat = 6
        static let tabHeight: CGFloat = 40
    }

    private let board: LeaderboardBoard
    /// Rows live inside a crop node: without it they would draw over the header
    /// and the tabs as the list scrolls under them, which SpriteKit does not
    /// clip on its own.
    private let listCrop = SKCropNode()
    private let listMask = SKShapeNode()
    private let listWorld = SKNode()
    private let tabs = SKNode()
    /// Tab identifier to board, filled in as the tabs are built.
    private var tabBoards: [String: LeaderboardBoard] = [:]
    /// The tab under the finger, driven from the scene's own touches rather than
    /// by the node itself. See `buildTabs()` for why.
    private var pressedTab: PressableNode?
    private let statusLabel = GameTheme.label("", size: 12, color: GameTheme.textSecondary)
    private var rowPitch: CGFloat { Layout.rowHeight + Layout.rowGap }

    private var tabsBottomY: CGFloat = 0
    private var listTopY: CGFloat = 0
    private var listBottomY: CGFloat = 0

    /// Everything the list currently shows, kept so a resize can rebuild the
    /// rows without refetching.
    private var entries: [CloudLeaderboardEntry] = []
    private var me: CloudLeaderboardEntry?
    private var state: LoadState = .loading
    private var loadToken = 0

    private var scrollOffset: CGFloat = 0
    private var scrollMinY: CGFloat = 0
    private var scrollMaxY: CGFloat = 0
    private var dragStartY: CGFloat = 0
    private var dragLastY: CGFloat = 0
    private var dragLastTimestamp: TimeInterval = 0
    private var dragVelocity: CGFloat = 0
    private var isScrollGesture = false
    /// Set once the chrome and the first rows exist, so a resize can tell "not
    /// built yet" from the size it was built at.
    private var isBuilt = false

    private enum LoadState {
        case loading
        case loaded
        case unavailable
        case failed
    }

    init(size: CGSize, board: LeaderboardBoard) {
        self.board = board
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) { nil }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        listMask.fillColor = .white
        listMask.strokeColor = .clear
        listCrop.maskNode = listMask
        listCrop.addChild(listWorld)
        addChild(listCrop)
        // Added after the list so they draw over it and never scroll.
        addHeader(title: GameText.leaderboard, subtitle: GameText.leaderboardSubtitle)
        addChild(tabs)
        buildTabs()
        buildStatus()
        layoutBand()
        isBuilt = true
        load()
        transitionIn()
    }

    override func layoutDidChange() {
        guard isBuilt else { return }
        // The tabs are placed from `safeTop` too, so they are rebuilt rather
        // than merely re-laid out: dropping this left the row of tabs where the
        // first pass had put it, 44pt up and straight through the title.
        buildTabs()
        // Both the band the rows scroll inside and every row position derived
        // from it are invalidated, so they are recomputed rather than nudged.
        layoutBand()
        rebuildRows()
    }

    // MARK: - Chrome

    private func buildTabs() {
        tabs.removeAllChildren()
        tabBoards.removeAll()
        // The tabs that were mid-press no longer exist, so any hold in progress
        // is dropped with them.
        pressedTab = nil
        let available = min(352, size.width - 32)
        let tabWidth = available / CGFloat(LeaderboardBoard.allCases.count)
        tabsBottomY = safeTop - 76 - Layout.tabHeight / 2
        for (index, candidate) in LeaderboardBoard.allCases.enumerated() {
            let isCurrent = candidate == board
            let tab = PressableNode(
                identifier: "tab-\(candidate.type.rawValue)",
                title: candidate.title,
                size: CGSize(width: tabWidth - 6, height: Layout.tabHeight),
                style: isCurrent ? .freeze : .quiet
            )
            tab.position = CGPoint(
                x: -available / 2 + tabWidth * (CGFloat(index) + 0.5),
                y: tabsBottomY
            )
            tab.delegate = self
            // The scene overrides `touchesBegan`, so a tab that tracked touches
            // itself would never receive them: nodes below a scene that handles
            // its own touches are only reached if it forwards to them, and this
            // one must not, because the same touch may turn into a scroll of the
            // list. The scene drives the press instead, through
            // `beginPressFromContainer()` and `activateFromContainer()`.
            tab.isUserInteractionEnabled = false
            // Registered as it is built rather than parsed back out of the
            // identifier on tap: the identifier carries a wire value, and a
            // mismatch between the two would leave a dead tab instead of a
            // compile error.
            tabBoards[tab.identifier] = candidate
            tabs.addChild(tab)
        }
    }

    private func buildStatus() {
        statusLabel.text = ""
        statusLabel.numberOfLines = 0
        statusLabel.position = CGPoint(x: 0, y: 0)
        addChild(statusLabel)
    }

    /// Recomputes the band the list scrolls inside from the furniture actually
    /// built, rather than from constants kept in step by hand.
    private func layoutBand() {
        // Set here rather than in `buildStatus`, which runs once: the label is
        // added to the scene there, so this is the pass that can be repeated.
        statusLabel.preferredMaxLayoutWidth = min(320, size.width - 48)
        listTopY = min(headerBottomY, tabsBottomY - Layout.tabHeight / 2) - 10
        // Leaves room for the pinned "you" row when there is one, so the player's
        // own standing is never hidden behind the footer.
        listBottomY = safeBottom + (me == nil ? 20 : 20 + rowPitch)
        statusLabel.position = CGPoint(x: 0, y: (listTopY + listBottomY) / 2)
        // The crop mask has to cover the full scrollable band; anything outside it
        // is clipped away, which is what keeps rows off the header and tabs.
        let bandHeight = max(1, listTopY - listBottomY)
        listMask.path = CGPath(
            rect: CGRect(
                x: -size.width / 2,
                y: listBottomY,
                width: size.width,
                height: bandHeight
            ),
            transform: nil
        )
    }

    // MARK: - Loading

    private func load() {
        loadToken += 1
        let token = loadToken
        guard SyncEngine.shared.isEnabled else {
            apply(state: .unavailable, entries: [], me: nil)
            return
        }
        apply(state: .loading, entries: [], me: nil)
        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await SyncEngine.shared.fetchLeaderboard(
                    type: board.type,
                    dayKey: board == .daily ? ProceduralLevelGenerator.dayKey(for: Date()) : nil
                )
                // A tab switch or a resize may have started a newer load; the
                // older response is dropped rather than allowed to overwrite it.
                guard token == loadToken else { return }
                apply(state: .loaded, entries: response.entries, me: response.me)
            } catch {
                guard token == loadToken else { return }
                apply(state: .failed, entries: [], me: nil)
            }
        }
    }

    private func apply(state newState: LoadState, entries newEntries: [CloudLeaderboardEntry], me newMe: CloudLeaderboardEntry?) {
        state = newState
        entries = newEntries
        me = newMe
        layoutBand()
        rebuildRows()
    }

    // MARK: - Rows

    private func rebuildRows() {
        listWorld.removeAllChildren()
        // Removed up front so a reload that comes back empty cannot leave the
        // previous pinned row standing over an empty list.
        childNode(withName: "meRow")?.removeFromParent()
        statusLabel.text = statusText()
        guard !entries.isEmpty else {
            scrollOffset = 0
            applyScroll()
            return
        }
        let width = min(352, size.width - 32)
        for (index, entry) in entries.enumerated() {
            let row = LeaderboardRowNode(
                entry: entry,
                isMe: entry.playerID == me?.playerID,
                board: board,
                width: width
            )
            row.position = CGPoint(x: 0, y: listTopY - Layout.rowHeight / 2 - CGFloat(index) * rowPitch)
            listWorld.addChild(row)
        }
        // The footer pins the player's own rank so it is visible even when they
        // are far down the board. It is a sibling of `listWorld`, not a child, so
        // it does not scroll away with the rows.
        rebuildMeRow(width: width)
        let contentHeight = CGFloat(entries.count) * rowPitch - Layout.rowGap
        let bandHeight = listTopY - listBottomY
        scrollMaxY = max(0, contentHeight - bandHeight)
        scrollOffset = ScalarMath.clamp(scrollOffset, scrollMinY, scrollMaxY)
        applyScroll()
    }

    private func rebuildMeRow(width: CGFloat) {
        childNode(withName: "meRow")?.removeFromParent()
        guard let me else { return }
        let row = LeaderboardRowNode(entry: me, isMe: true, board: board, width: width, isPinned: true)
        row.name = "meRow"
        row.position = CGPoint(x: 0, y: listBottomY + Layout.rowHeight / 2)
        addChild(row)
    }

    private func statusText() -> String {
        switch state {
        case .loading: return GameText.loading
        case .unavailable: return GameText.leaderboardOffline
        case .failed: return GameText.leaderboardFailed
        case .loaded: return entries.isEmpty ? GameText.leaderboardEmpty : ""
        }
    }

    private func applyScroll() {
        scrollOffset = ScalarMath.clamp(scrollOffset, scrollMinY, scrollMaxY)
        // Rows are laid out downwards from `listTopY`, so scrolling further down
        // the board moves the layer up: a child at local `y` is drawn at
        // `y + scrollOffset`.
        listWorld.position = CGPoint(x: 0, y: scrollOffset)
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        pressedTab = tabs.children
            .compactMap { $0 as? PressableNode }
            .first { $0.containsScenePoint(point) }
        pressedTab?.beginPressFromContainer()
        dragStartY = point.y
        dragLastY = dragStartY
        dragLastTimestamp = touch.timestamp
        dragVelocity = 0
        isScrollGesture = false
        // A new touch stops any in-flight flick. The layer is snapped to the
        // stored offset first, because cancelling an animation leaves the node
        // wherever it had got to while `scrollOffset` already held the target.
        listWorld.removeAllActions()
        applyScroll()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let y = touch.location(in: self).y
        let delta = y - dragLastY
        if !isScrollGesture, abs(y - dragStartY) > 9 {
            isScrollGesture = true
            // Hand the gesture to the scroll and take the press back off the tab
            // under the finger, so releasing after a drag does not switch board.
            pressedTab?.cancelPress()
            pressedTab = nil
        }
        guard isScrollGesture else { return }
        let elapsed = max(1.0 / 240.0, touch.timestamp - dragLastTimestamp)
        dragVelocity = delta / CGFloat(elapsed)
        // A finger moving up (negative delta) scrolls further down the board.
        scrollOffset -= delta
        applyScroll()
        dragLastY = y
        dragLastTimestamp = touch.timestamp
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let tab = pressedTab
        let wasScroll = isScrollGesture
        pressedTab = nil
        isScrollGesture = false
        guard !wasScroll else {
            guard !SaveStore.shared.settings.reduceMotion else { return }
            // A short projection of the release velocity reads as a flick without
            // carrying the list several screens past where the finger left it.
            let target = ScalarMath.clamp(scrollOffset - dragVelocity * 0.12, scrollMinY, scrollMaxY)
            scrollOffset = target
            listWorld.run(.moveTo(y: target, duration: 0.28))
            return
        }
        tab?.activateFromContainer()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        pressedTab?.cancelPress()
        pressedTab = nil
        isScrollGesture = false
    }

    override func pressableNodeDidActivate(_ node: PressableNode) {
        guard let selected = tabBoards[node.identifier], selected != board else {
            super.pressableNodeDidActivate(node)
            return
        }
        // Rebuilding the scene is what the other scenes do to change their own
        // state; here it also resets the scroll, which is what a tab switch
        // should do.
        GameCoordinator.shared.switchLeaderboardBoard(to: selected)
    }
}

/// One row of the board: rank, name, and the metric that board ranks by.
private final class LeaderboardRowNode: SKNode {
    init(
        entry: CloudLeaderboardEntry,
        isMe: Bool,
        board: LeaderboardBoard,
        width: CGFloat,
        isPinned: Bool = false
    ) {
        super.init()
        let panel = GameTheme.roundedPanel(
            size: CGSize(width: width, height: LeaderboardScene.Layout.rowHeight),
            fill: isMe ? GameTheme.board : GameTheme.panel
        )
        if isPinned {
            panel.strokeColor = GameTheme.freezeBlue.withAlphaComponent(0.7)
        }
        addChild(panel)

        let rankColor = entry.rank <= 3 ? GameTheme.brassLight : GameTheme.textSecondary
        let rank = GameTheme.label("\(entry.rank)", size: 15, color: rankColor, weight: .bold)
        rank.position = CGPoint(x: -width / 2 + 26, y: 0)
        addChild(rank)

        let nameColor = isMe ? GameTheme.freezeWhite : GameTheme.textPrimary
        let name = GameTheme.label(entry.displayName, size: 13, color: nameColor, weight: isMe ? .bold : .medium, alignment: .left)
        name.position = CGPoint(x: -width / 2 + 48, y: 0)
        addChild(name)

        if isMe {
            let badge = GameTheme.label(GameText.you, size: 9, color: GameTheme.freezeBlue, weight: .bold)
            badge.position = CGPoint(x: -width / 2 + 52 + name.frame.width + 16, y: 0)
            addChild(badge)
        }

        let value = Self.value(for: entry, board: board)
        let valueColor = isMe ? GameTheme.freezeWhite : GameTheme.brassLight
        let valueLabel = GameTheme.label(value, size: 14, color: valueColor, weight: .bold, alignment: .right)
        valueLabel.position = CGPoint(x: width / 2 - 18, y: 0)
        addChild(valueLabel)

        accessibilityLabel =
            "\(entry.displayName), rank \(entry.rank), \(value) \(board.metric.lowercased())"
    }

    required init?(coder aDecoder: NSCoder) { nil }

    /// Switches on the board rather than on the metric heading: the heading is
    /// a display string, and an earlier version of this switched on it with a
    /// `default:` branch, so a new board would have quietly rendered whatever
    /// `entry.score` happened to be instead of failing to compile.
    private static func value(for entry: CloudLeaderboardEntry, board: LeaderboardBoard) -> String {
        switch board {
        case .campaign:
            return "\(entry.totalStars ?? 0)"
        case .endless:
            return "\(entry.bestStage ?? 0)"
        case .daily:
            return "\(entry.score ?? 0)"
        case .achievements:
            return "\(entry.achievementsUnlocked ?? 0)"
        }
    }
}
