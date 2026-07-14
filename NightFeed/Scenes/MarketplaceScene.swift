import SpriteKit

/// Snapshot of a Firestore `listings/{id}` doc (see backend/functions/src/types.ts `ListingDoc`),
/// shaped for display. `isMine` is expected to be computed by whoever produces these (comparing
/// `sellerUid` against the signed-in uid) — see `FirebaseManager.observeListings` below. Declared at
/// file scope (not nested in MarketplaceScene) so FirebaseManager can reference it as a plain type.
struct ListingSnapshot {
    let id: String
    let sellerUid: String
    let droneKind: String
    let droneLevel: Int
    let priceCrystals: Int
    let status: String // "active" | "sold" | "cancelled"
    let isMine: Bool
}

/// The player-to-player Fleet Marketplace — list an owned drone in exchange for Crystals, or buy one
/// another player has listed. Crystals only: no real money, no external token, nothing here has value
/// outside the game (see the footer note built in buildFooterNote()). This is the deliberate safe
/// alternative to real-money NFT-style drone trading — same currency as StarshipHangarScene, same
/// visual/interaction family (Palette, makeButton, panel/row/tab conventions, manual name-based touch
/// routing, no SpriteKit physics) so it reads as "another shop screen" in the same game.
///
/// Backend contract (backend/functions/src/marketplace.ts, already written): three callables —
/// createListing({droneKind, priceCrystals}), cancelListing({listingId}), purchaseListing({listingId})
/// — routed through `FirebaseManager.shared.call(name:data:)`. Listings stream in live via
/// `FirebaseManager.shared.observeListings(onUpdate:)`. FirebaseManager itself is being wired up by a
/// concurrent workstream and is assumed here, not implemented here.
final class MarketplaceScene: SKScene {

    // MARK: - Palette (same family as StarshipHangarScene — this is "another shop screen")

    private enum Palette {
        static let bgTop = SKColor(red: 0.05, green: 0.04, blue: 0.12, alpha: 1)
        static let bgBottom = SKColor(red: 0.015, green: 0.012, blue: 0.03, alpha: 1)
        static let violet = SKColor(red: 0.55, green: 0.12, blue: 0.66, alpha: 1)
        static let violetDim = SKColor(red: 0.30, green: 0.10, blue: 0.38, alpha: 1)
        static let ember = SKColor(red: 1.0, green: 0.45, blue: 0.16, alpha: 1)
        static let emberBright = SKColor(red: 1.0, green: 0.66, blue: 0.28, alpha: 1)
        static let moonlight = SKColor(red: 0.93, green: 0.91, blue: 1.0, alpha: 1)
        static let moonlightDim = SKColor(red: 0.93, green: 0.91, blue: 1.0, alpha: 0.55)
        static let moonlightFaint = SKColor(red: 0.93, green: 0.91, blue: 1.0, alpha: 0.34)
        static let blood = SKColor(red: 0.80, green: 0.10, blue: 0.18, alpha: 1)
        static let success = SKColor(red: 0.38, green: 0.85, blue: 0.48, alpha: 1)
        static let panelFill = SKColor(red: 0.08, green: 0.045, blue: 0.12, alpha: 0.93)
        static let panelStroke = SKColor(red: 0.52, green: 0.24, blue: 0.58, alpha: 0.55)
        static let rowFill = SKColor(red: 0.13, green: 0.08, blue: 0.18, alpha: 0.9)
        static let dim = SKColor(white: 1, alpha: 0.32)
        static let crystal = SKColor(red: 0.38, green: 0.86, blue: 0.95, alpha: 1)
        static let crystalDim = SKColor(red: 0.38, green: 0.86, blue: 0.95, alpha: 0.5)
        static let crystalText = SKColor(red: 0.03, green: 0.09, blue: 0.11, alpha: 1)
    }

    static func newScene() -> MarketplaceScene {
        let scene = MarketplaceScene(size: CGSize(width: 393, height: 852))
        scene.scaleMode = .resizeFill
        return scene
    }

    // MARK: - Layers

    private let backgroundLayer = SKNode()
    private let starLayer = SKNode()
    private let panelLayer = SKNode()
    private let browseTabLayer = SKNode()
    private let myListingsTabLayer = SKNode()
    private let sellTabLayer = SKNode()

    // MARK: - Background refs

    private var nebulaGlow: SKSpriteNode!
    private var crystalDustEmitter: SKEmitterNode!
    private var starFractions: [(CGPoint, CGFloat)] = []
    private var starNodes: [SKShapeNode] = []

    // MARK: - Header refs

    private var panelBG: SKShapeNode!
    private var titleLabel: SKLabelNode!
    private var subtitleLabel: SKLabelNode!
    private var closeButton: SKShapeNode!
    private var closeLabel: SKLabelNode!
    private var crystalIconNode: SKSpriteNode!
    private var crystalBalanceLabel: SKLabelNode!
    private var footerNoteLabel: SKLabelNode!

    private var tabButtons: [SKShapeNode] = []
    private var tabLabels: [SKLabelNode] = []
    private var selectedTab = 0
    private static let tabTitles = ["BROWSE", "MY LISTINGS", "SELL"]

    private var pressedNodeName: String?
    private var hasBuiltOnce = false

    // MARK: - Live listing data

    /// Full set of listings this client currently knows about, as pushed by the live Firestore
    /// listener. `browseListings`/`myListings` are cheap derived views, not separately cached, so
    /// there is exactly one source of truth to keep in sync.
    private var allListings: [ListingSnapshot] = []

    private var browseListings: [ListingSnapshot] {
        allListings.filter { !$0.isMine && $0.status == "active" }
    }

    private var myListings: [ListingSnapshot] {
        allListings.filter { $0.isMine }
    }

    /// listingIds currently mid-flight on a buy/cancel call — gates the button from double-firing and
    /// swaps its label to a busy state until the callable resolves.
    private var pendingListingIds: Set<String> = []
    /// DroneKinds currently mid-flight on a createListing call — same guard, for the Sell tab.
    private var pendingSellKinds: Set<DroneKind> = []

    /// Player-chosen price per DroneKind on the Sell tab, defaulted lazily the first time a row is
    /// refreshed (see priceSelection(for:)).
    private var sellPriceSelections: [DroneKind: Int] = [:]

    /// One-shot transient denial/success message, keyed by the listingId it belongs to. Cleared by a
    /// scene-level timed SKAction (see showTransientBrowseMessage/showTransientMyListingsMessage) —
    /// keying the SKAction on a fixed string means a new message restarts the same timer instead of
    /// stacking.
    private struct TransientMessage { let targetId: String; let text: String; let isError: Bool }
    private var browseMessage: TransientMessage?
    private var myListingsMessage: TransientMessage?
    private var sellMessages: [DroneKind: (text: String, isError: Bool)] = [:]

    // MARK: - Pricing constants (mirrors backend/functions/src/types.ts)

    private static let priceStep = 25
    private static let minPrice = 10
    private static let maxPrice = 20000

    // MARK: - Row pools

    private struct BrowseRowNodes {
        let container: SKNode
        let background: SKShapeNode
        let icon: SKSpriteNode
        let nameLabel: SKLabelNode
        let priceLabel: SKLabelNode
        let buyButton: SKShapeNode
        let buyLabel: SKLabelNode
        let messageLabel: SKLabelNode
    }
    private var browseRowPool: [BrowseRowNodes] = []
    private var browseEmptyLabel: SKLabelNode!
    private var browseOverflowLabel: SKLabelNode!
    private static let maxVisibleBrowseRows = 5

    private struct MyListingRowNodes {
        let container: SKNode
        let background: SKShapeNode
        let icon: SKSpriteNode
        let nameLabel: SKLabelNode
        let priceLabel: SKLabelNode
        let statusLabel: SKLabelNode
        let cancelButton: SKShapeNode
        let cancelLabel: SKLabelNode
        let messageLabel: SKLabelNode
    }
    private var myListingsRowPool: [MyListingRowNodes] = []
    private var myListingsEmptyLabel: SKLabelNode!
    private var myListingsOverflowLabel: SKLabelNode!
    private static let maxVisibleMyListingsRows = 5

    private struct SellRowNodes {
        let container: SKNode
        let background: SKShapeNode
        let icon: SKSpriteNode
        let nameLabel: SKLabelNode
        let levelLabel: SKLabelNode
        let noteLabel: SKLabelNode
        let priceLabel: SKLabelNode
        let stepDownButton: SKShapeNode
        let stepDownLabel: SKLabelNode
        let stepUpButton: SKShapeNode
        let stepUpLabel: SKLabelNode
        let listButton: SKShapeNode
        let listLabel: SKLabelNode
        let messageLabel: SKLabelNode
    }
    private var sellRows: [DroneKind: SellRowNodes] = [:]
    private var sellEmptyLabel: SKLabelNode!

    // MARK: - Row geometry

    private static let rowWidth: CGFloat = 320
    private static let listingRowHeight: CGFloat = 88
    private static let sellRowHeight: CGFloat = 136
    private static let rowSpacing: CGFloat = 8
    private static let headerTotalHeight: CGFloat = 168
    private static let footerAreaHeight: CGFloat = 44

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = Palette.bgBottom

        if !hasBuiltOnce {
            addChild(backgroundLayer)
            addChild(starLayer)
            addChild(panelLayer)
            panelLayer.addChild(browseTabLayer)
            panelLayer.addChild(myListingsTabLayer)
            panelLayer.addChild(sellTabLayer)
            backgroundLayer.zPosition = ZPosition.menuUI - 5
            starLayer.zPosition = ZPosition.menuUI - 3
            panelLayer.zPosition = ZPosition.menuUI

            buildBackground()
            buildStars()
            buildPanelBackground()
            buildHeader()
            buildTabs()
            buildFooterNote()
            buildBrowseRows()
            buildMyListingsRows()
            buildSellRows()
            hasBuiltOnce = true

            startObservingListings()
        }

        refreshAll()
        refreshTabVisibility()
        layout(size: size)

        AudioManager.shared.startMusic()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard hasBuiltOnce else { return }
        layout(size: size)
    }

    // MARK: - Live data

    /// Registers the Firestore listener exactly once per scene instance. FirebaseManager's contract
    /// (per the concurrent Firebase-wiring workstream) doesn't specify a callback thread, so hop to
    /// main defensively before touching any SpriteKit node.
    private func startObservingListings() {
        FirebaseManager.shared.observeListings { [weak self] snapshots in
            DispatchQueue.main.async {
                guard let self else { return }
                self.allListings = snapshots
                self.refreshBrowseTab()
                self.refreshMyListingsTab()
                self.refreshSellTab()
            }
        }
    }

    // MARK: - Background (same recipe as StarshipHangarScene, kept independent to avoid cross-file coupling)

    private func buildBackground() {
        let bg = SKSpriteNode(texture: Self.gradientTexture(top: Palette.bgTop, bottom: Palette.bgBottom, size: CGSize(width: 4, height: 512)))
        bg.name = "bgGradient"
        bg.zPosition = 0
        backgroundLayer.addChild(bg)

        let glow = SKSpriteNode(texture: ProceduralTextures.radialGlow(color: Palette.crystalDim, radius: 240))
        glow.name = "nebulaGlow"
        glow.alpha = 0.4
        glow.zPosition = 1
        glow.blendMode = .add
        backgroundLayer.addChild(glow)
        nebulaGlow = glow

        let glowPulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.55, duration: 2.8),
            SKAction.fadeAlpha(to: 0.3, duration: 2.8)
        ])
        glow.run(SKAction.repeatForever(glowPulse))

        let emitter = SKEmitterNode()
        emitter.particleTexture = ProceduralTextures.radialGlow(color: Palette.crystal, radius: 6)
        emitter.particleBirthRate = 4
        emitter.particleLifetime = 8
        emitter.particleLifetimeRange = 3
        emitter.particleSpeed = 16
        emitter.particleSpeedRange = 10
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi / 8
        emitter.yAcceleration = 4
        emitter.particleAlpha = 0.0
        emitter.particleAlphaSequence = Self.dustAlphaSequence
        emitter.particleScale = 0.3
        emitter.particleScaleRange = 0.2
        emitter.particleScaleSpeed = -0.015
        emitter.particleColorBlendFactor = 1
        emitter.particleColor = Palette.crystal
        emitter.particleBlendMode = .add
        emitter.zPosition = 2
        backgroundLayer.addChild(emitter)
        crystalDustEmitter = emitter
    }

    private static let dustAlphaSequence: SKKeyframeSequence = {
        SKKeyframeSequence(keyframeValues: [0.0, 0.75, 0.5, 0.0], times: [0.0, 0.15, 0.7, 1.0])
    }()

    private func buildStars() {
        var rng = SystemRandomNumberGenerator()
        starFractions.removeAll()
        starNodes.removeAll()
        for _ in 0..<36 {
            let fx = CGFloat.random(in: 0...1, using: &rng)
            let fy = CGFloat.random(in: 0...1, using: &rng)
            let r = CGFloat.random(in: 0.6...1.5, using: &rng)
            starFractions.append((CGPoint(x: fx, y: fy), r))
            let dot = SKShapeNode(circleOfRadius: r)
            dot.fillColor = Palette.moonlight
            dot.strokeColor = .clear
            dot.alpha = CGFloat.random(in: 0.12...0.5, using: &rng)
            starLayer.addChild(dot)
            starNodes.append(dot)
            let twinkle = SKAction.sequence([
                SKAction.fadeAlpha(to: dot.alpha * 0.3, duration: Double.random(in: 1.4...3.2)),
                SKAction.fadeAlpha(to: dot.alpha, duration: Double.random(in: 1.4...3.2))
            ])
            dot.run(SKAction.repeatForever(twinkle))
        }
    }

    // MARK: - Panel background

    private func buildPanelBackground() {
        let panel = SKShapeNode()
        panel.fillColor = Palette.panelFill
        panel.strokeColor = Palette.panelStroke
        panel.lineWidth = 1.5
        panel.zPosition = 1
        panel.name = "marketplacePanelBG"
        panelLayer.addChild(panel)
        panelBG = panel
    }

    // MARK: - Header

    private func buildHeader() {
        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "FLEET MARKETPLACE"
        title.fontSize = 19
        title.fontColor = Palette.moonlight
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        title.zPosition = 2
        panelLayer.addChild(title)
        titleLabel = title

        let subtitle = SKLabelNode(fontNamed: "AvenirNext-Medium")
        subtitle.text = "PLAYER-TO-PLAYER · CRYSTALS ONLY"
        subtitle.fontSize = 10.5
        subtitle.fontColor = Palette.crystalDim
        subtitle.horizontalAlignmentMode = .center
        subtitle.verticalAlignmentMode = .center
        subtitle.zPosition = 2
        panelLayer.addChild(subtitle)
        subtitleLabel = subtitle

        let (close, closeText) = Self.makeButton(text: "X", width: 40, height: 40,
                                                  fill: Palette.rowFill, stroke: Palette.panelStroke,
                                                  textColor: Palette.moonlight, fontSize: 18, fontName: "AvenirNext-DemiBold")
        close.name = "marketplaceClose"
        closeText.name = "marketplaceClose"
        close.zPosition = 2
        closeText.zPosition = 3
        panelLayer.addChild(close)
        panelLayer.addChild(closeText)
        closeButton = close
        closeLabel = closeText

        let icon = SKSpriteNode(texture: Self.gemTexture(diameter: 20, color: Palette.crystal))
        icon.name = "crystalIcon"
        icon.zPosition = 2
        panelLayer.addChild(icon)
        crystalIconNode = icon

        let balance = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        balance.fontSize = 17
        balance.fontColor = Palette.crystal
        balance.horizontalAlignmentMode = .left
        balance.verticalAlignmentMode = .center
        balance.zPosition = 2
        panelLayer.addChild(balance)
        crystalBalanceLabel = balance
    }

    // MARK: - Footer note ("in-game-only economy" framing — always visible, regardless of tab)

    private func buildFooterNote() {
        let label = SKLabelNode(fontNamed: "AvenirNext-Regular")
        label.text = "Crystals have no real-world value — this is an in-game trading post only."
        label.fontSize = 9.5
        label.fontColor = Palette.moonlightFaint
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.numberOfLines = 2
        label.preferredMaxLayoutWidth = Self.rowWidth
        label.lineBreakMode = .byWordWrapping
        label.zPosition = 2
        panelLayer.addChild(label)
        footerNoteLabel = label
    }

    // MARK: - Tabs

    private func buildTabs() {
        for (index, title) in Self.tabTitles.enumerated() {
            let (btn, label) = Self.makeButton(text: title, width: 106, height: 32,
                                                fill: Palette.rowFill, stroke: Palette.panelStroke,
                                                textColor: Palette.moonlightDim, fontSize: 11.5, fontName: "AvenirNext-DemiBold")
            btn.name = "marketTab_\(index)"
            label.name = "marketTab_\(index)"
            btn.zPosition = 2
            label.zPosition = 3
            panelLayer.addChild(btn)
            panelLayer.addChild(label)
            tabButtons.append(btn)
            tabLabels.append(label)
        }
    }

    // MARK: - Browse rows (tab 0) — a fixed pool of row slots, rebound to whichever listings are
    // visible on each refresh. SpriteKit has no scroll view in this codebase (see StarshipHangarScene's
    // fixed-panel tab convention), so the list is capped at maxVisibleBrowseRows with an overflow note
    // rather than actually scrolling.

    private func buildBrowseRows() {
        for _ in 0..<Self.maxVisibleBrowseRows {
            let container = SKNode()
            container.zPosition = 2
            browseTabLayer.addChild(container)

            let bg = SKShapeNode(rectOf: CGSize(width: Self.rowWidth, height: Self.listingRowHeight), cornerRadius: 12)
            bg.fillColor = Palette.rowFill
            bg.strokeColor = Palette.panelStroke.withAlphaComponent(0.4)
            bg.lineWidth = 1
            container.addChild(bg)

            let icon = SKSpriteNode(texture: Self.gemTexture(diameter: 28, color: Palette.crystal))
            icon.position = CGPoint(x: -Self.rowWidth / 2 + 28, y: Self.listingRowHeight / 2 - 24)
            container.addChild(icon)

            let name = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            name.fontSize = 14
            name.fontColor = Palette.moonlight
            name.horizontalAlignmentMode = .left
            name.verticalAlignmentMode = .center
            name.position = CGPoint(x: -Self.rowWidth / 2 + 54, y: Self.listingRowHeight / 2 - 24)
            container.addChild(name)

            let price = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            price.fontSize = 13
            price.fontColor = Palette.crystal
            price.horizontalAlignmentMode = .left
            price.verticalAlignmentMode = .center
            price.position = CGPoint(x: -Self.rowWidth / 2 + 54, y: Self.listingRowHeight / 2 - 46)
            container.addChild(price)

            let (buy, buyText) = Self.makeButton(text: "BUY", width: 88, height: 30,
                                                  fill: Palette.crystal, stroke: Palette.moonlight,
                                                  textColor: Palette.crystalText,
                                                  fontSize: 12, fontName: "AvenirNext-Heavy")
            buy.position = CGPoint(x: Self.rowWidth / 2 - 58, y: 0)
            container.addChild(buy)
            container.addChild(buyText)

            let message = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            message.fontSize = 10.5
            message.fontColor = Palette.blood
            message.horizontalAlignmentMode = .left
            message.verticalAlignmentMode = .center
            message.numberOfLines = 2
            message.preferredMaxLayoutWidth = 150
            message.lineBreakMode = .byWordWrapping
            message.position = CGPoint(x: -Self.rowWidth / 2 + 54, y: Self.listingRowHeight / 2 - 46)
            message.isHidden = true
            container.addChild(message)

            browseRowPool.append(BrowseRowNodes(container: container, background: bg, icon: icon, nameLabel: name,
                                                 priceLabel: price, buyButton: buy, buyLabel: buyText, messageLabel: message))
        }

        let empty = SKLabelNode(fontNamed: "AvenirNext-Medium")
        empty.text = "No active listings right now — check back soon."
        empty.fontSize = 12.5
        empty.fontColor = Palette.moonlightDim
        empty.horizontalAlignmentMode = .center
        empty.verticalAlignmentMode = .center
        empty.numberOfLines = 2
        empty.preferredMaxLayoutWidth = Self.rowWidth - 20
        empty.zPosition = 2
        empty.isHidden = true
        browseTabLayer.addChild(empty)
        browseEmptyLabel = empty

        let overflow = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        overflow.fontSize = 10.5
        overflow.fontColor = Palette.moonlightFaint
        overflow.horizontalAlignmentMode = .center
        overflow.verticalAlignmentMode = .center
        overflow.zPosition = 2
        overflow.isHidden = true
        browseTabLayer.addChild(overflow)
        browseOverflowLabel = overflow
    }

    // MARK: - My Listings rows (tab 1)

    private func buildMyListingsRows() {
        for _ in 0..<Self.maxVisibleMyListingsRows {
            let container = SKNode()
            container.zPosition = 2
            myListingsTabLayer.addChild(container)

            let bg = SKShapeNode(rectOf: CGSize(width: Self.rowWidth, height: Self.listingRowHeight), cornerRadius: 12)
            bg.fillColor = Palette.rowFill
            bg.strokeColor = Palette.panelStroke.withAlphaComponent(0.4)
            bg.lineWidth = 1
            container.addChild(bg)

            let icon = SKSpriteNode(texture: Self.gemTexture(diameter: 28, color: Palette.crystal))
            icon.position = CGPoint(x: -Self.rowWidth / 2 + 28, y: Self.listingRowHeight / 2 - 24)
            container.addChild(icon)

            let name = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            name.fontSize = 14
            name.fontColor = Palette.moonlight
            name.horizontalAlignmentMode = .left
            name.verticalAlignmentMode = .center
            name.position = CGPoint(x: -Self.rowWidth / 2 + 54, y: Self.listingRowHeight / 2 - 24)
            container.addChild(name)

            let price = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            price.fontSize = 13
            price.fontColor = Palette.crystal
            price.horizontalAlignmentMode = .left
            price.verticalAlignmentMode = .center
            price.position = CGPoint(x: -Self.rowWidth / 2 + 54, y: Self.listingRowHeight / 2 - 46)
            container.addChild(price)

            let status = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            status.fontSize = 11.5
            status.horizontalAlignmentMode = .right
            status.verticalAlignmentMode = .center
            status.position = CGPoint(x: Self.rowWidth / 2 - 14, y: Self.listingRowHeight / 2 - 24)
            container.addChild(status)

            let (cancel, cancelText) = Self.makeButton(text: "CANCEL", width: 96, height: 30,
                                                        fill: Palette.rowFill, stroke: Palette.blood,
                                                        textColor: Palette.moonlight,
                                                        fontSize: 11.5, fontName: "AvenirNext-Heavy")
            cancel.position = CGPoint(x: Self.rowWidth / 2 - 62, y: 0)
            container.addChild(cancel)
            container.addChild(cancelText)

            let message = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            message.fontSize = 10.5
            message.fontColor = Palette.blood
            message.horizontalAlignmentMode = .left
            message.verticalAlignmentMode = .center
            message.numberOfLines = 2
            message.preferredMaxLayoutWidth = 150
            message.lineBreakMode = .byWordWrapping
            message.position = CGPoint(x: -Self.rowWidth / 2 + 54, y: Self.listingRowHeight / 2 - 46)
            message.isHidden = true
            container.addChild(message)

            myListingsRowPool.append(MyListingRowNodes(container: container, background: bg, icon: icon, nameLabel: name,
                                                         priceLabel: price, statusLabel: status, cancelButton: cancel,
                                                         cancelLabel: cancelText, messageLabel: message))
        }

        let empty = SKLabelNode(fontNamed: "AvenirNext-Medium")
        empty.text = "You haven't listed anything yet — try the SELL tab."
        empty.fontSize = 12.5
        empty.fontColor = Palette.moonlightDim
        empty.horizontalAlignmentMode = .center
        empty.verticalAlignmentMode = .center
        empty.numberOfLines = 2
        empty.preferredMaxLayoutWidth = Self.rowWidth - 20
        empty.zPosition = 2
        empty.isHidden = true
        myListingsTabLayer.addChild(empty)
        myListingsEmptyLabel = empty

        let overflow = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        overflow.fontSize = 10.5
        overflow.fontColor = Palette.moonlightFaint
        overflow.horizontalAlignmentMode = .center
        overflow.verticalAlignmentMode = .center
        overflow.zPosition = 2
        overflow.isHidden = true
        myListingsTabLayer.addChild(overflow)
        myListingsOverflowLabel = overflow
    }

    // MARK: - Sell rows (tab 2) — one fixed row per DroneKind, shown only when eligible
    // (owned, per EmpireStore, and not already actively listed, per the live listings data).

    private func buildSellRows() {
        for kind in DroneKind.allCases {
            let container = SKNode()
            container.zPosition = 2
            sellTabLayer.addChild(container)

            let bg = SKShapeNode(rectOf: CGSize(width: Self.rowWidth, height: Self.sellRowHeight), cornerRadius: 12)
            bg.fillColor = Palette.rowFill
            bg.strokeColor = Palette.panelStroke.withAlphaComponent(0.4)
            bg.lineWidth = 1
            container.addChild(bg)

            let icon = SKSpriteNode(texture: Self.droneIconTexture(kind, diameter: 32))
            icon.position = CGPoint(x: -Self.rowWidth / 2 + 30, y: Self.sellRowHeight / 2 - 22)
            container.addChild(icon)

            let name = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            name.text = kind.displayName
            name.fontSize = 14
            name.fontColor = Palette.moonlight
            name.horizontalAlignmentMode = .left
            name.verticalAlignmentMode = .center
            name.position = CGPoint(x: -Self.rowWidth / 2 + 58, y: Self.sellRowHeight / 2 - 22)
            container.addChild(name)

            let level = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            level.fontSize = 11
            level.fontColor = Palette.crystal
            level.horizontalAlignmentMode = .right
            level.verticalAlignmentMode = .center
            level.position = CGPoint(x: Self.rowWidth / 2 - 14, y: Self.sellRowHeight / 2 - 22)
            container.addChild(level)

            let note = SKLabelNode(fontNamed: "AvenirNext-Regular")
            note.text = "Lists this drone for sale — it moves to escrow immediately and leaves your active fleet until sold or cancelled."
            note.fontSize = 9.5
            note.fontColor = Palette.moonlightDim
            note.horizontalAlignmentMode = .left
            note.verticalAlignmentMode = .top
            note.numberOfLines = 3
            note.preferredMaxLayoutWidth = Self.rowWidth - 28
            note.lineBreakMode = .byWordWrapping
            note.position = CGPoint(x: -Self.rowWidth / 2 + 14, y: Self.sellRowHeight / 2 - 42)
            container.addChild(note)

            let message = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            message.fontSize = 10.5
            message.fontColor = Palette.blood
            message.horizontalAlignmentMode = .left
            message.verticalAlignmentMode = .top
            message.numberOfLines = 3
            message.preferredMaxLayoutWidth = Self.rowWidth - 28
            message.lineBreakMode = .byWordWrapping
            message.position = note.position
            message.isHidden = true
            container.addChild(message)

            let (stepDown, stepDownText) = Self.makeButton(text: "−", width: 32, height: 30,
                                                             fill: Palette.rowFill, stroke: Palette.panelStroke,
                                                             textColor: Palette.moonlight, fontSize: 16, fontName: "AvenirNext-Heavy")
            stepDown.position = CGPoint(x: -Self.rowWidth / 2 + 40, y: -Self.sellRowHeight / 2 + 44)
            stepDown.name = "sellPriceDown_\(kind.rawValue)"
            stepDownText.name = stepDown.name
            stepDownText.position = stepDown.position
            container.addChild(stepDown)
            container.addChild(stepDownText)

            let price = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            price.fontSize = 15
            price.fontColor = Palette.crystal
            price.horizontalAlignmentMode = .center
            price.verticalAlignmentMode = .center
            price.position = CGPoint(x: 0, y: -Self.sellRowHeight / 2 + 44)
            container.addChild(price)

            let (stepUp, stepUpText) = Self.makeButton(text: "+", width: 32, height: 30,
                                                         fill: Palette.rowFill, stroke: Palette.panelStroke,
                                                         textColor: Palette.moonlight, fontSize: 16, fontName: "AvenirNext-Heavy")
            stepUp.position = CGPoint(x: Self.rowWidth / 2 - 40, y: -Self.sellRowHeight / 2 + 44)
            stepUp.name = "sellPriceUp_\(kind.rawValue)"
            stepUpText.name = stepUp.name
            stepUpText.position = stepUp.position
            container.addChild(stepUp)
            container.addChild(stepUpText)

            let (list, listText) = Self.makeButton(text: "LIST FOR SALE", width: 220, height: 30,
                                                     fill: Palette.crystal, stroke: Palette.moonlight,
                                                     textColor: Palette.crystalText,
                                                     fontSize: 12, fontName: "AvenirNext-Heavy")
            list.position = CGPoint(x: 0, y: -Self.sellRowHeight / 2 + 14)
            list.name = "listDrone_\(kind.rawValue)"
            listText.name = list.name
            listText.position = list.position
            container.addChild(list)
            container.addChild(listText)

            sellRows[kind] = SellRowNodes(container: container, background: bg, icon: icon, nameLabel: name,
                                           levelLabel: level, noteLabel: note, priceLabel: price,
                                           stepDownButton: stepDown, stepDownLabel: stepDownText,
                                           stepUpButton: stepUp, stepUpLabel: stepUpText,
                                           listButton: list, listLabel: listText, messageLabel: message)
        }

        let empty = SKLabelNode(fontNamed: "AvenirNext-Medium")
        empty.text = "You have no drones available to sell — unlock or reclaim one in the Hangar first."
        empty.fontSize = 12.5
        empty.fontColor = Palette.moonlightDim
        empty.horizontalAlignmentMode = .center
        empty.verticalAlignmentMode = .center
        empty.numberOfLines = 3
        empty.preferredMaxLayoutWidth = Self.rowWidth - 20
        empty.zPosition = 2
        empty.isHidden = true
        sellTabLayer.addChild(empty)
        sellEmptyLabel = empty
    }

    // MARK: - Layout (called on didMove and every didChangeSize — resizeFill re-sizes the scene)

    private func layout(size: CGSize) {
        let w = size.width, h = size.height

        if let bg = backgroundLayer.childNode(withName: "bgGradient") as? SKSpriteNode {
            bg.size = CGSize(width: w, height: h)
            bg.position = CGPoint(x: w / 2, y: h / 2)
        }
        nebulaGlow.position = CGPoint(x: w * 0.5, y: h * 0.9)
        crystalDustEmitter.particlePosition = CGPoint(x: w / 2, y: -10)
        crystalDustEmitter.particlePositionRange = CGVector(dx: w * 1.1, dy: 0)

        for (i, node) in starNodes.enumerated() {
            let (fraction, _) = starFractions[i]
            node.position = CGPoint(x: fraction.x * w, y: fraction.y * h)
        }

        let listAreaHeight = max(
            CGFloat(Self.maxVisibleBrowseRows) * Self.listingRowHeight + CGFloat(Self.maxVisibleBrowseRows - 1) * Self.rowSpacing,
            CGFloat(Self.maxVisibleMyListingsRows) * Self.listingRowHeight + CGFloat(Self.maxVisibleMyListingsRows - 1) * Self.rowSpacing,
            CGFloat(DroneKind.allCases.count) * Self.sellRowHeight + CGFloat(DroneKind.allCases.count - 1) * Self.rowSpacing
        )
        let panelWidth = min(w - 32, Self.rowWidth + 40)
        let panelHeight = min(h - 64, Self.headerTotalHeight + listAreaHeight + Self.footerAreaHeight + 16)

        let panelRect = CGRect(x: -panelWidth / 2, y: -panelHeight / 2, width: panelWidth, height: panelHeight)
        panelBG.path = CGPath(roundedRect: panelRect, cornerWidth: 20, cornerHeight: 20, transform: nil)
        panelBG.position = CGPoint(x: w / 2, y: h / 2)

        let panelTop = panelBG.position.y + panelHeight / 2
        let panelBottom = panelBG.position.y - panelHeight / 2

        titleLabel.position = CGPoint(x: w / 2, y: panelTop - 26)
        subtitleLabel.position = CGPoint(x: w / 2, y: panelTop - 46)
        closeButton.position = CGPoint(x: w / 2 + panelWidth / 2 - 32, y: panelTop - 30)
        closeLabel.position = closeButton.position

        layoutCrystalBalance(centerY: panelTop - 78, width: w)

        let tabsY = panelTop - 110
        let tabWidth: CGFloat = 106, tabGap: CGFloat = 6
        let totalTabsWidth = CGFloat(tabButtons.count) * tabWidth + CGFloat(max(0, tabButtons.count - 1)) * tabGap
        var tabX = w / 2 - totalTabsWidth / 2 + tabWidth / 2
        for i in 0..<tabButtons.count {
            tabButtons[i].position = CGPoint(x: tabX, y: tabsY)
            tabLabels[i].position = tabButtons[i].position
            tabX += tabWidth + tabGap
        }

        footerNoteLabel.position = CGPoint(x: w / 2, y: panelBottom + 22)

        let listTop = panelTop - Self.headerTotalHeight
        layoutBrowseRows(topY: listTop, centerX: w / 2)
        layoutMyListingsRows(topY: listTop, centerX: w / 2)
        layoutSellRows(topY: listTop, centerX: w / 2)
    }

    private func layoutCrystalBalance(centerY: CGFloat, width w: CGFloat) {
        let text = crystalBalanceLabel.text ?? "0"
        let textWidth = Self.measureWidth(text, fontName: "AvenirNext-DemiBold", fontSize: 17)
        let totalWidth = textWidth + 26
        let iconX = w / 2 - totalWidth / 2 + 10
        let textX = iconX + 16
        crystalBalanceLabel.position = CGPoint(x: textX, y: centerY)
        crystalIconNode.position = CGPoint(x: iconX, y: centerY)
    }

    private func layoutBrowseRows(topY: CGFloat, centerX: CGFloat) {
        var rowY = topY
        for row in browseRowPool {
            row.container.position = CGPoint(x: centerX, y: rowY - Self.listingRowHeight / 2)
            rowY -= (Self.listingRowHeight + Self.rowSpacing)
        }
        browseEmptyLabel.position = CGPoint(x: centerX, y: topY - 60)
        browseOverflowLabel.position = CGPoint(x: centerX, y: rowY + Self.rowSpacing - 6)
    }

    private func layoutMyListingsRows(topY: CGFloat, centerX: CGFloat) {
        var rowY = topY
        for row in myListingsRowPool {
            row.container.position = CGPoint(x: centerX, y: rowY - Self.listingRowHeight / 2)
            rowY -= (Self.listingRowHeight + Self.rowSpacing)
        }
        myListingsEmptyLabel.position = CGPoint(x: centerX, y: topY - 60)
        myListingsOverflowLabel.position = CGPoint(x: centerX, y: rowY + Self.rowSpacing - 6)
    }

    private func layoutSellRows(topY: CGFloat, centerX: CGFloat) {
        var rowY = topY
        for kind in DroneKind.allCases {
            guard let row = sellRows[kind] else { continue }
            row.container.position = CGPoint(x: centerX, y: rowY - Self.sellRowHeight / 2)
            rowY -= (Self.sellRowHeight + Self.rowSpacing)
        }
        sellEmptyLabel.position = CGPoint(x: centerX, y: topY - 60)
    }

    // MARK: - Refresh

    private func refreshAll() {
        refreshCrystalBalance()
        refreshBrowseTab()
        refreshMyListingsTab()
        refreshSellTab()
    }

    private func refreshCrystalBalance() {
        crystalBalanceLabel.text = "\(EmpireStore.shared.crystals)"
        if hasBuiltOnce { layoutCrystalBalance(centerY: crystalBalanceLabel.position.y, width: size.width) }
    }

    private func refreshBrowseTab() {
        let data = Array(browseListings.prefix(Self.maxVisibleBrowseRows))
        browseEmptyLabel.isHidden = !data.isEmpty
        let overflowCount = browseListings.count - data.count
        browseOverflowLabel.isHidden = overflowCount <= 0
        browseOverflowLabel.text = "+\(overflowCount) more listing\(overflowCount == 1 ? "" : "s") not shown"

        for (i, row) in browseRowPool.enumerated() {
            guard i < data.count else {
                row.container.isHidden = true
                continue
            }
            let listing = data[i]
            row.container.isHidden = false
            let kind = DroneKind(rawValue: listing.droneKind)
            row.icon.texture = Self.droneIconTexture(kind ?? .interceptor, diameter: 28)
            row.nameLabel.text = "\(kind?.displayName ?? listing.droneKind.capitalized) · Lv \(listing.droneLevel)"

            let pending = pendingListingIds.contains(listing.id)
            row.buyButton.name = "buyListing_\(listing.id)"
            row.buyLabel.name = row.buyButton.name
            row.buyLabel.text = pending ? "···" : "BUY"
            row.buyButton.alpha = pending ? 0.5 : 1.0

            if let msg = browseMessage, msg.targetId == listing.id {
                row.priceLabel.isHidden = true
                row.messageLabel.isHidden = false
                row.messageLabel.fontColor = msg.isError ? Palette.blood : Palette.success
                row.messageLabel.text = msg.text
            } else {
                row.priceLabel.isHidden = false
                row.messageLabel.isHidden = true
                row.priceLabel.text = "\(listing.priceCrystals) ✦"
            }
        }
    }

    private func refreshMyListingsTab() {
        let data = Array(myListings.prefix(Self.maxVisibleMyListingsRows))
        myListingsEmptyLabel.isHidden = !data.isEmpty
        let overflowCount = myListings.count - data.count
        myListingsOverflowLabel.isHidden = overflowCount <= 0
        myListingsOverflowLabel.text = "+\(overflowCount) older listing\(overflowCount == 1 ? "" : "s") not shown"

        for (i, row) in myListingsRowPool.enumerated() {
            guard i < data.count else {
                row.container.isHidden = true
                continue
            }
            let listing = data[i]
            row.container.isHidden = false
            let kind = DroneKind(rawValue: listing.droneKind)
            row.icon.texture = Self.droneIconTexture(kind ?? .interceptor, diameter: 28)
            row.nameLabel.text = "\(kind?.displayName ?? listing.droneKind.capitalized) · Lv \(listing.droneLevel)"
            row.priceLabel.text = "\(listing.priceCrystals) ✦"

            switch listing.status {
            case "active":
                row.statusLabel.text = "ACTIVE"
                row.statusLabel.fontColor = Palette.crystal
                let pending = pendingListingIds.contains(listing.id)
                row.cancelButton.isHidden = false
                row.cancelLabel.isHidden = false
                row.cancelButton.name = "cancelListing_\(listing.id)"
                row.cancelLabel.name = row.cancelButton.name
                row.cancelLabel.text = pending ? "···" : "CANCEL"
                row.cancelButton.alpha = pending ? 0.5 : 1.0
            case "sold":
                row.statusLabel.text = "SOLD"
                row.statusLabel.fontColor = Palette.success
                row.cancelButton.isHidden = true
                row.cancelLabel.isHidden = true
            default:
                row.statusLabel.text = "CANCELLED"
                row.statusLabel.fontColor = Palette.moonlightFaint
                row.cancelButton.isHidden = true
                row.cancelLabel.isHidden = true
            }

            if let msg = myListingsMessage, msg.targetId == listing.id {
                row.priceLabel.isHidden = true
                row.messageLabel.isHidden = false
                row.messageLabel.fontColor = msg.isError ? Palette.blood : Palette.success
                row.messageLabel.text = msg.text
            } else {
                row.priceLabel.isHidden = false
                row.messageLabel.isHidden = true
            }
        }
    }

    /// Eligible-to-sell kinds: owned locally (EmpireStore) AND without an active listing in the live
    /// Firestore data. The second half of that check is what actually prevents double-listing — the
    /// local EmpireStore "owned" flag has no concept of server-side escrow, so it stays true the whole
    /// time a drone is listed; excluding anything with an active listing is what keeps the Sell tab honest.
    private func sellEligibleKinds() -> [DroneKind] {
        let activeMineKinds = Set(myListings.filter { $0.status == "active" }.map { $0.droneKind })
        return DroneKind.allCases.filter { EmpireStore.shared.isDroneOwned($0) && !activeMineKinds.contains($0.rawValue) }
    }

    private func refreshSellTab() {
        let eligible = Set(sellEligibleKinds())
        sellEmptyLabel.isHidden = !eligible.isEmpty
        for kind in DroneKind.allCases {
            sellRows[kind]?.container.isHidden = !eligible.contains(kind)
            if eligible.contains(kind) { refreshSellRow(kind) }
        }
    }

    private func refreshSellRow(_ kind: DroneKind) {
        guard let row = sellRows[kind] else { return }
        let level = EmpireStore.shared.droneLevel(kind)
        row.levelLabel.text = "LVL \(level)/\(DroneKind.maxLevel)"
        row.priceLabel.text = "\(priceSelection(for: kind)) ✦"

        let pending = pendingSellKinds.contains(kind)
        row.listButton.name = "listDrone_\(kind.rawValue)"
        row.listLabel.name = row.listButton.name
        row.listLabel.text = pending ? "LISTING…" : "LIST FOR SALE"
        row.listButton.alpha = pending ? 0.5 : 1.0

        if let msg = sellMessages[kind] {
            row.noteLabel.isHidden = true
            row.messageLabel.isHidden = false
            row.messageLabel.fontColor = msg.isError ? Palette.blood : Palette.success
            row.messageLabel.text = msg.text
        } else {
            row.noteLabel.isHidden = false
            row.messageLabel.isHidden = true
        }
    }

    private func priceSelection(for kind: DroneKind) -> Int {
        if let existing = sellPriceSelections[kind] { return existing }
        let defaultPrice = Self.defaultPrice(for: kind)
        sellPriceSelections[kind] = defaultPrice
        return defaultPrice
    }

    private static func defaultPrice(for kind: DroneKind) -> Int {
        let base = max(minPrice, kind.unlockCost / 2)
        let rounded = (base / priceStep) * priceStep
        return min(maxPrice, max(minPrice, rounded == 0 ? priceStep : rounded))
    }

    // MARK: - Tab visibility

    private func refreshTabVisibility() {
        browseTabLayer.isHidden = selectedTab != 0
        myListingsTabLayer.isHidden = selectedTab != 1
        sellTabLayer.isHidden = selectedTab != 2
        for (i, btn) in tabButtons.enumerated() {
            let active = i == selectedTab
            btn.fillColor = active ? Palette.crystal : Palette.rowFill
            btn.strokeColor = active ? Palette.moonlight : Palette.panelStroke
            tabLabels[i].fontColor = active ? Palette.crystalText : Palette.moonlightDim
        }
    }

    private func handleMarketTabTap(_ index: Int) {
        guard index != selectedTab, index >= 0, index < tabButtons.count else { return }
        AudioManager.shared.playSFX(.buttonTap)
        selectedTab = index
        refreshTabVisibility()
        let activeLayer: SKNode
        switch selectedTab {
        case 0: activeLayer = browseTabLayer
        case 1: activeLayer = myListingsTabLayer
        default: activeLayer = sellTabLayer
        }
        activeLayer.alpha = 0
        activeLayer.run(SKAction.fadeIn(withDuration: 0.15))
    }

    // MARK: - Touch handling (manual name-based routing, identical pattern to MenuScene/StarshipHangarScene — no physics)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        if let name = topInteractiveName(at: location) {
            pressedNodeName = name
            setPressed(name: name, pressed: true)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let pressed = pressedNodeName else { return }
        let location = touch.location(in: self)
        let stillOver = topInteractiveName(at: location) == pressed
        setPressed(name: pressed, pressed: stillOver)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard let pressed = pressedNodeName else { return }
        setPressed(name: pressed, pressed: false)
        pressedNodeName = nil
        guard topInteractiveName(at: location) == pressed else { return }
        handleTap(name: pressed)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let pressed = pressedNodeName { setPressed(name: pressed, pressed: false) }
        pressedNodeName = nil
    }

    /// SpriteKit's `nodes(at:)` is a purely geometric query — it does NOT respect `isHidden`, so
    /// off-screen (hidden) tab content could still geometrically overlap and "steal" taps meant for
    /// the visible tab. Gate candidates explicitly by `selectedTab` (and by in-flight pending state)
    /// instead of trusting node visibility — same reasoning/pattern as StarshipHangarScene.
    private func topInteractiveName(at location: CGPoint) -> String? {
        let hit = nodes(at: location)
        let matched = hit.filter { node in
            guard let name = node.name else { return false }
            if name == "marketplaceClose" { return true }
            if name.hasPrefix("marketTab_") { return true }
            if name.hasPrefix("buyListing_") {
                guard selectedTab == 0 else { return false }
                let id = String(name.dropFirst("buyListing_".count))
                return !pendingListingIds.contains(id)
            }
            if name.hasPrefix("cancelListing_") {
                guard selectedTab == 1 else { return false }
                let id = String(name.dropFirst("cancelListing_".count))
                return !pendingListingIds.contains(id)
            }
            if name.hasPrefix("sellPriceUp_") || name.hasPrefix("sellPriceDown_") { return selectedTab == 2 }
            if name.hasPrefix("listDrone_") {
                guard selectedTab == 2 else { return false }
                if let kind = DroneKind(rawValue: String(name.dropFirst("listDrone_".count))) {
                    return !pendingSellKinds.contains(kind)
                }
                return true
            }
            return false
        }
        return matched.max(by: { $0.zPosition < $1.zPosition })?.name
    }

    private func setPressed(name: String, pressed: Bool) {
        let scale: CGFloat = pressed ? 0.94 : 1.0
        if name == "marketplaceClose" {
            closeButton.run(SKAction.scale(to: scale, duration: 0.08))
        } else if name.hasPrefix("marketTab_") {
            if let idx = Int(name.dropFirst("marketTab_".count)), idx < tabButtons.count {
                tabButtons[idx].run(SKAction.scale(to: scale, duration: 0.08))
            }
        } else if name.hasPrefix("buyListing_") {
            if let row = browseRowPool.first(where: { $0.buyButton.name == name }) {
                row.buyButton.run(SKAction.scale(to: scale, duration: 0.08))
            }
        } else if name.hasPrefix("cancelListing_") {
            if let row = myListingsRowPool.first(where: { $0.cancelButton.name == name }) {
                row.cancelButton.run(SKAction.scale(to: scale, duration: 0.08))
            }
        } else if name.hasPrefix("sellPriceUp_") {
            if let kind = DroneKind(rawValue: String(name.dropFirst("sellPriceUp_".count))) {
                sellRows[kind]?.stepUpButton.run(SKAction.scale(to: scale, duration: 0.08))
            }
        } else if name.hasPrefix("sellPriceDown_") {
            if let kind = DroneKind(rawValue: String(name.dropFirst("sellPriceDown_".count))) {
                sellRows[kind]?.stepDownButton.run(SKAction.scale(to: scale, duration: 0.08))
            }
        } else if name.hasPrefix("listDrone_") {
            if let kind = DroneKind(rawValue: String(name.dropFirst("listDrone_".count))) {
                sellRows[kind]?.listButton.run(SKAction.scale(to: scale, duration: 0.08))
            }
        }
    }

    private func handleTap(name: String) {
        if name == "marketplaceClose" {
            AudioManager.shared.playSFX(.buttonTap)
            AudioManager.shared.hapticImpact(.light)
            view?.presentScene(CommandDeckScene.newScene(), transition: .crossFade(withDuration: 0.4))
        } else if name.hasPrefix("marketTab_") {
            if let idx = Int(name.dropFirst("marketTab_".count)) { handleMarketTabTap(idx) }
        } else if name.hasPrefix("buyListing_") {
            handleBuyListing(String(name.dropFirst("buyListing_".count)))
        } else if name.hasPrefix("cancelListing_") {
            handleCancelListing(String(name.dropFirst("cancelListing_".count)))
        } else if name.hasPrefix("sellPriceUp_") {
            if let kind = DroneKind(rawValue: String(name.dropFirst("sellPriceUp_".count))) {
                adjustSellPrice(kind: kind, delta: Self.priceStep)
            }
        } else if name.hasPrefix("sellPriceDown_") {
            if let kind = DroneKind(rawValue: String(name.dropFirst("sellPriceDown_".count))) {
                adjustSellPrice(kind: kind, delta: -Self.priceStep)
            }
        } else if name.hasPrefix("listDrone_") {
            if let kind = DroneKind(rawValue: String(name.dropFirst("listDrone_".count))) {
                handleListDrone(kind)
            }
        }
    }

    // MARK: - Price stepper

    private func adjustSellPrice(kind: DroneKind, delta: Int) {
        let current = priceSelection(for: kind)
        let next = min(Self.maxPrice, max(Self.minPrice, current + delta))
        guard next != current else { return }
        sellPriceSelections[kind] = next
        AudioManager.shared.playSFX(.buttonTap)
        AudioManager.shared.hapticImpact(.light)
        refreshSellRow(kind)
    }

    // MARK: - Buy / Cancel / List handlers — each calls through FirebaseManager.shared.call(name:data:),
    // a Cloud Functions callable wrapper the concurrent Firebase-wiring workstream is adding. Optimistic
    // local mutation keeps the UI snappy; the live observeListings() stream is the eventual source of
    // truth and will overwrite/confirm shortly after.

    private func handleBuyListing(_ id: String) {
        guard !pendingListingIds.contains(id) else { return }
        guard let listing = allListings.first(where: { $0.id == id }), listing.status == "active" else { return }
        AudioManager.shared.playSFX(.buttonTap)
        AudioManager.shared.hapticImpact(.light)
        pendingListingIds.insert(id)
        refreshBrowseTab()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await FirebaseManager.shared.call(name: "purchaseListing", data: ["listingId": id])
                self.pendingListingIds.remove(id)
                AudioManager.shared.hapticNotification(.success)
                AudioManager.shared.playSFX(.gemPickup)
                if let idx = self.allListings.firstIndex(where: { $0.id == id }) {
                    self.allListings.remove(at: idx)
                }
                self.refreshCrystalBalance()
                self.refreshBrowseTab()
            } catch {
                self.pendingListingIds.remove(id)
                AudioManager.shared.hapticNotification(.error)
                self.browseMessage = TransientMessage(targetId: id, text: Self.errorMessage(from: error), isError: true)
                self.refreshBrowseTab()
                self.run(SKAction.sequence([
                    SKAction.wait(forDuration: 2.6),
                    SKAction.run { [weak self] in
                        guard let self else { return }
                        self.browseMessage = nil
                        self.refreshBrowseTab()
                    }
                ]), withKey: "clearBrowseMessage")
            }
        }
    }

    private func handleCancelListing(_ id: String) {
        guard !pendingListingIds.contains(id) else { return }
        guard let listing = allListings.first(where: { $0.id == id }), listing.isMine, listing.status == "active" else { return }
        AudioManager.shared.playSFX(.buttonTap)
        AudioManager.shared.hapticImpact(.light)
        pendingListingIds.insert(id)
        refreshMyListingsTab()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await FirebaseManager.shared.call(name: "cancelListing", data: ["listingId": id])
                self.pendingListingIds.remove(id)
                AudioManager.shared.hapticNotification(.success)
                if let idx = self.allListings.firstIndex(where: { $0.id == id }) {
                    let old = self.allListings[idx]
                    self.allListings[idx] = ListingSnapshot(id: old.id, sellerUid: old.sellerUid, droneKind: old.droneKind,
                                                             droneLevel: old.droneLevel, priceCrystals: old.priceCrystals,
                                                             status: "cancelled", isMine: old.isMine)
                }
                self.refreshMyListingsTab()
                self.refreshSellTab()
            } catch {
                self.pendingListingIds.remove(id)
                AudioManager.shared.hapticNotification(.error)
                self.myListingsMessage = TransientMessage(targetId: id, text: Self.errorMessage(from: error), isError: true)
                self.refreshMyListingsTab()
                self.run(SKAction.sequence([
                    SKAction.wait(forDuration: 2.6),
                    SKAction.run { [weak self] in
                        guard let self else { return }
                        self.myListingsMessage = nil
                        self.refreshMyListingsTab()
                    }
                ]), withKey: "clearMyListingsMessage")
            }
        }
    }

    private func handleListDrone(_ kind: DroneKind) {
        guard !pendingSellKinds.contains(kind) else { return }
        let price = priceSelection(for: kind)
        AudioManager.shared.playSFX(.buttonTap)
        AudioManager.shared.hapticImpact(.light)
        pendingSellKinds.insert(kind)
        refreshSellRow(kind)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await FirebaseManager.shared.call(name: "createListing",
                                                           data: ["droneKind": kind.rawValue, "priceCrystals": price])
                self.pendingSellKinds.remove(kind)
                AudioManager.shared.hapticNotification(.success)
                AudioManager.shared.playSFX(.gemPickup)
                // Optimistic placeholder so the row disappears from Sell / appears under My Listings
                // immediately; observeListings() will replace this with the authoritative doc shortly.
                let placeholderId = "pending-\(kind.rawValue)-\(Date().timeIntervalSince1970)"
                self.allListings.append(ListingSnapshot(id: placeholderId, sellerUid: "", droneKind: kind.rawValue,
                                                         droneLevel: EmpireStore.shared.droneLevel(kind),
                                                         priceCrystals: price, status: "active", isMine: true))
                self.sellPriceSelections[kind] = nil
                self.refreshSellTab()
                self.refreshMyListingsTab()
            } catch {
                self.pendingSellKinds.remove(kind)
                AudioManager.shared.hapticNotification(.error)
                self.sellMessages[kind] = (text: Self.errorMessage(from: error), isError: true)
                self.refreshSellRow(kind)
                self.run(SKAction.sequence([
                    SKAction.wait(forDuration: 2.6),
                    SKAction.run { [weak self] in
                        guard let self else { return }
                        self.sellMessages[kind] = nil
                        self.refreshSellRow(kind)
                    }
                ]), withKey: "clearSellMessage_\(kind.rawValue)")
            }
        }
    }

    /// Cloud Functions HttpsError messages (see backend/functions/src/marketplace.ts — "Not enough
    /// Crystals.", "You already own this drone.", etc.) surface through the Firebase Functions SDK as
    /// the thrown NSError's localizedDescription. Falls back to a generic message if that's empty or
    /// looks like a default system-generated string.
    private static func errorMessage(from error: Error) -> String {
        let nsError = error as NSError
        let raw = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.hasPrefix("The operation couldn") else {
            return "That didn't go through — try again."
        }
        return raw
    }

    // MARK: - Procedural icon textures (no image assets — mirrors StarshipHangarScene's icon recipes
    // so the same DroneKind reads identically across both shop screens)

    private static func droneIconTexture(_ kind: DroneKind, diameter: CGFloat) -> SKTexture {
        switch kind {
        case .interceptor: return interceptorIconTexture(diameter: diameter)
        case .aegis: return aegisIconTexture(diameter: diameter)
        case .harvester: return gemTexture(diameter: diameter, color: Palette.crystal)
        }
    }

    private static func interceptorIconTexture(diameter: CGFloat) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        return ProceduralTextures.render(size: size) { ctx, size in
            let w = size.width, h = size.height
            let path = CGMutablePath()
            path.move(to: CGPoint(x: w * 0.5, y: h * 0.92))
            path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.12))
            path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.34))
            path.addLine(to: CGPoint(x: w * 0.14, y: h * 0.12))
            path.closeSubpath()
            ctx.setFillColor(Palette.blood.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.setStrokeColor(Palette.emberBright.cgColor)
            ctx.setLineWidth(1.2)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    private static func aegisIconTexture(diameter: CGFloat) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        return ProceduralTextures.render(size: size) { ctx, size in
            let w = size.width, h = size.height
            let path = CGMutablePath()
            path.move(to: CGPoint(x: w * 0.5, y: h * 0.95))
            path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.72))
            path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.30))
            path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.05))
            path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.30))
            path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.72))
            path.closeSubpath()
            ctx.setFillColor(Palette.violet.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.setStrokeColor(Palette.moonlight.withAlphaComponent(0.7).cgColor)
            ctx.setLineWidth(1.4)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    /// Faceted diamond shape — used for the Harvester drone icon and the header's Crystal currency icon.
    private static func gemTexture(diameter: CGFloat, color: SKColor) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        return ProceduralTextures.render(size: size) { ctx, size in
            let w = size.width, h = size.height
            let path = CGMutablePath()
            path.move(to: CGPoint(x: w * 0.5, y: h * 0.96))
            path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.54))
            path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.04))
            path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.54))
            path.closeSubpath()
            ctx.setFillColor(color.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.setStrokeColor(SKColor.white.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(1.0)
            ctx.move(to: CGPoint(x: w * 0.5, y: h * 0.96))
            ctx.addLine(to: CGPoint(x: w * 0.5, y: h * 0.04))
            ctx.strokePath()
            ctx.move(to: CGPoint(x: w * 0.12, y: h * 0.54))
            ctx.addLine(to: CGPoint(x: w * 0.88, y: h * 0.54))
            ctx.strokePath()
        }
    }

    private static func gradientTexture(top: SKColor, bottom: SKColor, size: CGSize) -> SKTexture {
        ProceduralTextures.render(size: size, opaque: true) { ctx, size in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    // MARK: - Shared button helper (identical to MenuScene.makeButton / StarshipHangarScene.makeButton)

    private static func makeButton(text: String, width: CGFloat, height: CGFloat,
                                    fill: SKColor, stroke: SKColor, textColor: SKColor,
                                    fontSize: CGFloat, fontName: String) -> (SKShapeNode, SKLabelNode) {
        let shape = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: height / 2.6)
        shape.fillColor = fill
        shape.strokeColor = stroke
        shape.lineWidth = 1.6
        let label = SKLabelNode(fontNamed: fontName)
        label.text = text
        label.fontSize = fontSize
        label.fontColor = textColor
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.zPosition = 1
        // Intentionally NOT parented under `shape` — callers add both as siblings to the same
        // parent and keep `label.position == shape.position` in sync (see refresh/layout functions
        // above). Nesting here would double-offset the label once the caller repositions it directly.
        return (shape, label)
    }

    private static func measureWidth(_ text: String, fontName: String, fontSize: CGFloat) -> CGFloat {
        let label = SKLabelNode(fontNamed: fontName)
        label.text = text
        label.fontSize = fontSize
        return label.frame.width
    }
}
