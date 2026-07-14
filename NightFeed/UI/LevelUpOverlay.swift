import SpriteKit

/// The "clean 3-card upgrade UI" shown on every level-up. Pure view — GameScene owns touch hit-testing
/// (consistent with MenuScene/GameOverScene's manual name-based routing) and calls `flashSelected`/`dismiss`
/// once it resolves a tap to a card's name; this type just builds and animates the cards.
final class LevelUpOverlay: SKNode {
    private(set) var choices: [UpgradeChoice] = []
    private var cardNodes: [SKShapeNode] = []
    private var hasDismissed = false

    static func make(choices: [UpgradeChoice], screenSize: CGSize) -> LevelUpOverlay {
        let overlay = LevelUpOverlay()
        overlay.zPosition = ZPosition.levelUpOverlay
        overlay.choices = choices
        overlay.build(choices: choices, screenSize: screenSize)
        return overlay
    }

    private func build(choices: [UpgradeChoice], screenSize: CGSize) {
        let dim = SKShapeNode(rectOf: CGSize(width: screenSize.width * 1.6, height: screenSize.height * 1.6))
        dim.fillColor = SKColor.black.withAlphaComponent(0.75)
        dim.strokeColor = .clear
        dim.zPosition = 0
        dim.alpha = 0
        addChild(dim)
        dim.run(SKAction.fadeIn(withDuration: 0.16))

        let title = SKLabelNode(text: "LEVEL UP")
        title.fontName = "AvenirNext-Heavy"
        title.fontSize = 30
        title.fontColor = SKColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 1)
        title.position = CGPoint(x: 0, y: screenSize.height * 0.26)
        title.zPosition = 1
        title.alpha = 0
        addChild(title)
        title.run(SKAction.sequence([SKAction.wait(forDuration: 0.05), SKAction.fadeIn(withDuration: 0.25)]))

        let glow = SKLabelNode(text: "choose your power")
        glow.fontName = "AvenirNext-Italic"
        glow.fontSize = 14
        glow.fontColor = SKColor(white: 1, alpha: 0.55)
        glow.position = CGPoint(x: 0, y: screenSize.height * 0.26 - 30)
        glow.zPosition = 1
        glow.alpha = 0
        addChild(glow)
        glow.run(SKAction.sequence([SKAction.wait(forDuration: 0.12), SKAction.fadeIn(withDuration: 0.25)]))

        let cardWidth = min(320, screenSize.width * 0.84)
        let cardHeight: CGFloat = 96
        let spacing: CGFloat = 18
        let totalHeight = CGFloat(choices.count) * cardHeight + CGFloat(max(0, choices.count - 1)) * spacing
        var y = totalHeight / 2 - cardHeight / 2

        for (index, choice) in choices.enumerated() {
            let card = makeCard(choice: choice, index: index, size: CGSize(width: cardWidth, height: cardHeight))
            let isEvolution: Bool
            if case .evolution = choice.kind { isEvolution = true } else { isEvolution = false }
            card.position = CGPoint(x: 0, y: y)
            card.setScale(0.85)
            card.alpha = 0
            addChild(card)
            cardNodes.append(card)

            let delay = 0.1 + Double(index) * 0.07
            card.run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.group([
                    SKAction.fadeIn(withDuration: 0.22),
                    SKAction.scale(to: 1.0, duration: 0.22)
                ])
            ])) {
                // The rare ★ EVOLUTION ★ card already stands out with a thicker gold stroke + glow,
                // but that glow sits completely static — a very small idle breathe (kicked off only
                // once the entrance settles, so it never fights that scale-to over the same channel)
                // gives the most exciting choice on the screen a bit of life without touching the
                // ordinary cards.
                if isEvolution {
                    JuiceEffects.idleBreathe(card, amplitude: 0.025, period: 1.1)
                }
            }
            y -= (cardHeight + spacing)
        }
    }

    private func makeCard(choice: UpgradeChoice, index: Int, size: CGSize) -> SKShapeNode {
        let isEvolution: Bool
        if case .evolution = choice.kind { isEvolution = true } else { isEvolution = false }

        let card = SKShapeNode(rectOf: size, cornerRadius: 16)
        card.name = "upgradeCard_\(index)"
        card.fillColor = SKColor(red: 0.1, green: 0.05, blue: 0.14, alpha: 0.96)
        card.strokeColor = isEvolution
            ? SKColor(red: 1, green: 0.8, blue: 0.3, alpha: 1)
            : SKColor(red: 0.55, green: 0.24, blue: 0.66, alpha: 0.75)
        card.lineWidth = isEvolution ? 3 : 1.5
        card.glowWidth = isEvolution ? 7 : 0
        card.zPosition = 1

        let badge = badgeLabel(for: choice.kind)
        badge.name = "upgradeCard_\(index)"
        badge.fontName = "AvenirNext-Bold"
        badge.fontSize = 11
        badge.fontColor = isEvolution ? SKColor(red: 1, green: 0.85, blue: 0.4, alpha: 1) : SKColor(red: 0.85, green: 0.6, blue: 1.0, alpha: 1)
        badge.horizontalAlignmentMode = .left
        badge.position = CGPoint(x: -size.width / 2 + 18, y: size.height / 2 - 22)
        card.addChild(badge)

        let title = SKLabelNode(text: choice.title)
        title.name = "upgradeCard_\(index)"
        title.fontName = "AvenirNext-Bold"
        title.fontSize = 21
        title.fontColor = .white
        title.horizontalAlignmentMode = .left
        title.position = CGPoint(x: -size.width / 2 + 18, y: 6)
        card.addChild(title)

        let subtitle = SKLabelNode(text: choice.subtitle)
        subtitle.name = "upgradeCard_\(index)"
        subtitle.fontName = "AvenirNext-Medium"
        subtitle.fontSize = 12.5
        subtitle.fontColor = SKColor(white: 1, alpha: 0.68)
        subtitle.horizontalAlignmentMode = .left
        subtitle.position = CGPoint(x: -size.width / 2 + 18, y: -18)
        subtitle.preferredMaxLayoutWidth = size.width - 36
        subtitle.numberOfLines = 2
        subtitle.lineBreakMode = .byTruncatingTail
        card.addChild(subtitle)

        return card
    }

    private func badgeLabel(for kind: UpgradeChoice.Kind) -> SKLabelNode {
        let text: String
        switch kind {
        case .newWeapon: text = "NEW WEAPON"
        case .weaponLevelUp: text = "WEAPON UPGRADE"
        case .newPassive: text = "NEW PASSIVE"
        case .passiveLevelUp: text = "PASSIVE UPGRADE"
        case .evolution: text = "★ EVOLUTION ★"
        }
        return SKLabelNode(text: text)
    }

    /// A quick press-flash before GameScene removes the whole overlay.
    func flashSelected(index: Int) {
        guard index >= 0, index < cardNodes.count else { return }
        cardNodes[index].run(SKAction.sequence([
            SKAction.scale(to: 1.06, duration: 0.06),
            SKAction.scale(to: 1.0, duration: 0.08)
        ]))
    }

    /// Guarded against re-entry: a fast double-tap on a card (both taps landing before the ~0.16s
    /// fade finishes) used to fire this twice, which double-fired GameScene's completion closure and
    /// desynced isShowingUpgradeOverlay/levelUpOverlay from the overlay actually still on screen.
    func dismiss(completion: @escaping () -> Void) {
        guard !hasDismissed else { return }
        hasDismissed = true
        run(SKAction.fadeOut(withDuration: 0.16)) { [weak self] in
            self?.removeFromParent()
            completion()
        }
    }
}
