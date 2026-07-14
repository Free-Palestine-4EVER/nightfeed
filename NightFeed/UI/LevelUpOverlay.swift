import SpriteKit

/// The "clean 3-card upgrade UI" shown on every level-up. Pure view — GameScene owns touch hit-testing
/// (consistent with MenuScene/GameOverScene's manual name-based routing) and calls `flashSelected`/`dismiss`/
/// `reroll` once it resolves a tap to a card's name; this type just builds and animates the cards.
final class LevelUpOverlay: SKNode {
    private(set) var choices: [UpgradeChoice] = []
    private var cardNodes: [SKShapeNode] = []
    private var hasDismissed = false
    private var cardLayer: SKNode!
    private var lastScreenSize: CGSize = .zero

    static func make(choices: [UpgradeChoice], screenSize: CGSize) -> LevelUpOverlay {
        let overlay = LevelUpOverlay()
        overlay.zPosition = ZPosition.levelUpOverlay
        overlay.choices = choices
        overlay.lastScreenSize = screenSize
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

        let layer = SKNode()
        layer.zPosition = 1
        addChild(layer)
        cardLayer = layer

        layoutCards(choices: choices, screenSize: screenSize, animated: true)

        // Shuffle button — re-rolls the current 3 cards without consuming a level-up. Sits just below
        // the lowest card, well clear of the cards themselves so it can never be mistaken for one.
        let shuffleY = -(cardBottomY(choices: choices, screenSize: screenSize)) - 34
        let shuffle = SKShapeNode(rectOf: CGSize(width: 168, height: 40), cornerRadius: 12)
        shuffle.name = "levelUpShuffle"
        shuffle.fillColor = SKColor(red: 0.14, green: 0.08, blue: 0.18, alpha: 0.9)
        shuffle.strokeColor = SKColor(red: 0.55, green: 0.24, blue: 0.66, alpha: 0.6)
        shuffle.lineWidth = 1.5
        shuffle.position = CGPoint(x: 0, y: shuffleY)
        shuffle.zPosition = 1
        shuffle.alpha = 0
        addChild(shuffle)
        shuffleButtonNode = shuffle

        let shuffleLabel = SKLabelNode(text: "🔀 Shuffle")
        shuffleLabel.name = "levelUpShuffle"
        shuffleLabel.fontName = "AvenirNext-DemiBold"
        shuffleLabel.fontSize = 14
        shuffleLabel.fontColor = SKColor(white: 1, alpha: 0.8)
        shuffleLabel.verticalAlignmentMode = .center
        shuffleLabel.position = shuffle.position
        shuffleLabel.zPosition = 1
        shuffleLabel.alpha = 0
        addChild(shuffleLabel)
        shuffleLabelNode = shuffleLabel

        shuffle.run(SKAction.sequence([SKAction.wait(forDuration: 0.32), SKAction.fadeIn(withDuration: 0.2)]))
        shuffleLabel.run(SKAction.sequence([SKAction.wait(forDuration: 0.32), SKAction.fadeIn(withDuration: 0.2)]))
    }

    private var shuffleButtonNode: SKShapeNode!
    private var shuffleLabelNode: SKLabelNode!

    private func cardBottomY(choices: [UpgradeChoice], screenSize: CGSize) -> CGFloat {
        let cardHeight: CGFloat = 96
        let spacing: CGFloat = 18
        let totalHeight = CGFloat(choices.count) * cardHeight + CGFloat(max(0, choices.count - 1)) * spacing
        return totalHeight / 2
    }

    private func layoutCards(choices: [UpgradeChoice], screenSize: CGSize, animated: Bool) {
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
            card.setScale(animated ? 0.85 : 1.0)
            card.alpha = animated ? 0 : 1
            cardLayer.addChild(card)
            cardNodes.append(card)

            if animated {
                let delay = 0.1 + Double(index) * 0.07
                card.run(SKAction.sequence([
                    SKAction.wait(forDuration: delay),
                    SKAction.group([
                        SKAction.fadeIn(withDuration: 0.22),
                        SKAction.scale(to: 1.0, duration: 0.22)
                    ])
                ])) {
                    if isEvolution {
                        JuiceEffects.idleBreathe(card, amplitude: 0.025, period: 1.1)
                    }
                }
            } else if isEvolution {
                JuiceEffects.idleBreathe(card, amplitude: 0.025, period: 1.1)
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

        let iconDiameter: CGFloat = 40
        let icon = SKShapeNode(circleOfRadius: iconDiameter / 2)
        icon.name = "upgradeCard_\(index)"
        icon.position = CGPoint(x: -size.width / 2 + 18 + iconDiameter / 2, y: 2)
        let iconColor = Self.color(for: choice.kind)
        icon.fillColor = iconColor.withAlphaComponent(0.18)
        icon.strokeColor = iconColor
        icon.lineWidth = 1.5
        icon.glowWidth = isEvolution ? 3 : 1
        card.addChild(icon)
        let glyph = Self.glyphNode(for: choice.kind, color: iconColor)
        glyph.name = "upgradeCard_\(index)"
        icon.addChild(glyph)

        let textLeft = -size.width / 2 + 18 + iconDiameter + 12

        let badge = badgeLabel(for: choice.kind)
        badge.name = "upgradeCard_\(index)"
        badge.fontName = "AvenirNext-Bold"
        badge.fontSize = 11
        badge.fontColor = isEvolution ? SKColor(red: 1, green: 0.85, blue: 0.4, alpha: 1) : SKColor(red: 0.85, green: 0.6, blue: 1.0, alpha: 1)
        badge.horizontalAlignmentMode = .left
        badge.position = CGPoint(x: textLeft, y: size.height / 2 - 22)
        card.addChild(badge)

        let title = SKLabelNode(text: choice.title)
        title.name = "upgradeCard_\(index)"
        title.fontName = "AvenirNext-Bold"
        title.fontSize = 19
        title.fontColor = .white
        title.horizontalAlignmentMode = .left
        title.position = CGPoint(x: textLeft, y: 6)
        card.addChild(title)

        let subtitle = SKLabelNode(text: choice.subtitle)
        subtitle.name = "upgradeCard_\(index)"
        subtitle.fontName = "AvenirNext-Medium"
        subtitle.fontSize = 12
        subtitle.fontColor = SKColor(white: 1, alpha: 0.68)
        subtitle.horizontalAlignmentMode = .left
        subtitle.position = CGPoint(x: textLeft, y: -18)
        subtitle.preferredMaxLayoutWidth = size.width - (textLeft + size.width / 2) - 18
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

    /// Per-kind accent color, reusing WeaponSystem's own palette conventions where a weapon is
    /// involved, and a small hand-picked set for passives so every card has a distinct icon color.
    private static func color(for kind: UpgradeChoice.Kind) -> SKColor {
        switch kind {
        case .newWeapon(let weapon), .weaponLevelUp(let weapon): return weaponColor(weapon)
        case .newPassive(let passive), .passiveLevelUp(let passive): return passiveColor(passive)
        case .evolution: return SKColor(red: 1, green: 0.82, blue: 0.35, alpha: 1)
        }
    }

    private static func weaponColor(_ kind: WeaponKind) -> SKColor {
        switch kind {
        case .fangBolt: return SKColor(red: 0.93, green: 0.91, blue: 1.0, alpha: 1)
        case .emberOrbit: return SKColor(red: 1.0, green: 0.55, blue: 0.2, alpha: 1)
        case .novaPulse: return SKColor(red: 1.0, green: 0.75, blue: 0.3, alpha: 1)
        case .bloodLance: return SKColor(red: 0.85, green: 0.15, blue: 0.2, alpha: 1)
        case .batSwarm: return SKColor(red: 0.65, green: 0.4, blue: 0.9, alpha: 1)
        case .reaperWhirl: return SKColor(red: 0.8, green: 0.15, blue: 0.25, alpha: 1)
        case .voidRift: return SKColor(red: 0.55, green: 0.25, blue: 0.85, alpha: 1)
        case .starShard: return SKColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 1)
        }
    }

    private static func passiveColor(_ kind: PassiveKind) -> SKColor {
        switch kind {
        case .swiftFeet: return SKColor(red: 0.5, green: 0.9, blue: 0.6, alpha: 1)
        case .bloodEdge: return SKColor(red: 0.85, green: 0.2, blue: 0.25, alpha: 1)
        case .rapidPulse: return SKColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1)
        case .vitality: return SKColor(red: 0.95, green: 0.35, blue: 0.4, alpha: 1)
        case .magnetHeart: return SKColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1)
        case .ironHide: return SKColor(red: 0.7, green: 0.7, blue: 0.75, alpha: 1)
        case .multishot: return SKColor(red: 1.0, green: 0.6, blue: 0.3, alpha: 1)
        case .critFocus: return SKColor(red: 1.0, green: 0.9, blue: 0.4, alpha: 1)
        case .ashenWake: return SKColor(red: 0.55, green: 0.9, blue: 0.7, alpha: 1)
        case .secondWind: return SKColor(red: 0.85, green: 0.55, blue: 1.0, alpha: 1)
        }
    }

    /// A small procedural glyph inside the icon circle — simple, readable geometric shapes rather than
    /// full illustrations, drawn via CoreGraphics like every other texture in this codebase.
    private static func glyphNode(for kind: UpgradeChoice.Kind, color: SKColor) -> SKSpriteNode {
        let size = CGSize(width: 22, height: 22)
        let texture = ProceduralTextures.render(size: size) { ctx, sz in
            let cx = sz.width / 2, cy = sz.height / 2
            ctx.setStrokeColor(color.cgColor)
            ctx.setFillColor(color.cgColor)
            ctx.setLineWidth(2.2)
            ctx.setLineCap(.round)

            switch kind {
            case .newWeapon(let w), .weaponLevelUp(let w):
                drawWeaponGlyph(w, ctx: ctx, cx: cx, cy: cy, size: sz)
            case .newPassive(let p), .passiveLevelUp(let p):
                drawPassiveGlyph(p, ctx: ctx, cx: cx, cy: cy, size: sz)
            case .evolution:
                // Four-point star burst — a level above any single weapon/passive glyph.
                let path = CGMutablePath()
                for i in 0..<8 {
                    let angle = CGFloat(i) * .pi / 4
                    let r: CGFloat = i % 2 == 0 ? sz.width * 0.42 : sz.width * 0.16
                    let pt = CGPoint(x: cx + cos(angle) * r, y: cy + sin(angle) * r)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                path.closeSubpath()
                ctx.addPath(path)
                ctx.fillPath()
            }
        }
        return SKSpriteNode(texture: texture, size: size)
    }

    private static func drawWeaponGlyph(_ weapon: WeaponKind, ctx: CGContext, cx: CGFloat, cy: CGFloat, size: CGSize) {
        switch weapon {
        case .fangBolt: // lightning bolt
            let path = CGMutablePath()
            path.move(to: CGPoint(x: cx + 3, y: size.height - 3))
            path.addLine(to: CGPoint(x: cx - 4, y: cy + 1))
            path.addLine(to: CGPoint(x: cx + 1, y: cy + 1))
            path.addLine(to: CGPoint(x: cx - 3, y: 3))
            path.addLine(to: CGPoint(x: cx + 5, y: cy - 1))
            path.addLine(to: CGPoint(x: cx, y: cy - 1))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.fillPath()
        case .emberOrbit: // orbiting dot ring
            ctx.strokeEllipse(in: CGRect(x: cx - 8, y: cy - 8, width: 16, height: 16))
            ctx.fillEllipse(in: CGRect(x: cx + 5, y: cy - 2, width: 4, height: 4))
        case .novaPulse: // concentric burst rings
            ctx.strokeEllipse(in: CGRect(x: cx - 4, y: cy - 4, width: 8, height: 8))
            ctx.strokeEllipse(in: CGRect(x: cx - 9, y: cy - 9, width: 18, height: 18))
        case .bloodLance: // a long line/lance through center
            ctx.move(to: CGPoint(x: cx - 8, y: cy - 8))
            ctx.addLine(to: CGPoint(x: cx + 8, y: cy + 8))
            ctx.strokePath()
        case .batSwarm: // two wing triangles
            let l = CGMutablePath()
            l.move(to: CGPoint(x: cx, y: cy))
            l.addLine(to: CGPoint(x: cx - 9, y: cy + 5))
            l.addLine(to: CGPoint(x: cx - 7, y: cy - 3))
            l.closeSubpath()
            let r = CGMutablePath()
            r.move(to: CGPoint(x: cx, y: cy))
            r.addLine(to: CGPoint(x: cx + 9, y: cy + 5))
            r.addLine(to: CGPoint(x: cx + 7, y: cy - 3))
            r.closeSubpath()
            ctx.addPath(l); ctx.fillPath()
            ctx.addPath(r); ctx.fillPath()
        case .reaperWhirl: // curved scythe blade
            let path = CGMutablePath()
            path.addArc(center: CGPoint(x: cx, y: cy), radius: 8, startAngle: 0.3, endAngle: .pi * 1.5, clockwise: false)
            ctx.addPath(path)
            ctx.strokePath()
        case .voidRift: // inward spiral
            let path = CGMutablePath()
            path.addArc(center: CGPoint(x: cx, y: cy), radius: 8, startAngle: 0, endAngle: .pi * 1.3, clockwise: false)
            path.addArc(center: CGPoint(x: cx, y: cy), radius: 4, startAngle: .pi * 1.3, endAngle: .pi * 2.6, clockwise: false)
            ctx.addPath(path)
            ctx.strokePath()
        case .starShard: // diamond shard
            let path = CGMutablePath()
            path.move(to: CGPoint(x: cx, y: cy + 9))
            path.addLine(to: CGPoint(x: cx + 6, y: cy))
            path.addLine(to: CGPoint(x: cx, y: cy - 9))
            path.addLine(to: CGPoint(x: cx - 6, y: cy))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.fillPath()
        }
    }

    private static func drawPassiveGlyph(_ passive: PassiveKind, ctx: CGContext, cx: CGFloat, cy: CGFloat, size: CGSize) {
        switch passive {
        case .swiftFeet: // forward chevron
            let path = CGMutablePath()
            path.move(to: CGPoint(x: cx - 5, y: cy + 6))
            path.addLine(to: CGPoint(x: cx + 5, y: cy))
            path.addLine(to: CGPoint(x: cx - 5, y: cy - 6))
            ctx.addPath(path)
            ctx.strokePath()
        case .bloodEdge: // small blade
            ctx.move(to: CGPoint(x: cx, y: cy + 9))
            ctx.addLine(to: CGPoint(x: cx, y: cy - 7))
            ctx.strokePath()
            ctx.move(to: CGPoint(x: cx - 4, y: cy - 7))
            ctx.addLine(to: CGPoint(x: cx + 4, y: cy - 7))
            ctx.strokePath()
        case .rapidPulse: // double chevron
            for dx: CGFloat in [-3, 3] {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: cx + dx - 4, y: cy + 5))
                path.addLine(to: CGPoint(x: cx + dx + 2, y: cy))
                path.addLine(to: CGPoint(x: cx + dx - 4, y: cy - 5))
                ctx.addPath(path)
                ctx.strokePath()
            }
        case .vitality: // heart
            let path = CGMutablePath()
            path.move(to: CGPoint(x: cx, y: cy - 7))
            path.addCurve(to: CGPoint(x: cx - 8, y: cy + 4), control1: CGPoint(x: cx - 4, y: cy - 3), control2: CGPoint(x: cx - 8, y: cy - 1))
            path.addArc(center: CGPoint(x: cx - 4, y: cy + 5), radius: 4, startAngle: .pi, endAngle: 0, clockwise: false)
            path.addArc(center: CGPoint(x: cx + 4, y: cy + 5), radius: 4, startAngle: .pi, endAngle: 0, clockwise: false)
            path.addCurve(to: CGPoint(x: cx, y: cy - 7), control1: CGPoint(x: cx + 8, y: cy - 1), control2: CGPoint(x: cx + 4, y: cy - 3))
            ctx.addPath(path)
            ctx.fillPath()
        case .magnetHeart: // horseshoe magnet
            let path = CGMutablePath()
            path.addArc(center: CGPoint(x: cx, y: cy), radius: 7, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.fillEllipse(in: CGRect(x: cx - 8, y: cy + 4, width: 3, height: 4))
            ctx.fillEllipse(in: CGRect(x: cx + 5, y: cy + 4, width: 3, height: 4))
        case .ironHide: // shield
            let path = CGMutablePath()
            path.move(to: CGPoint(x: cx, y: cy + 9))
            path.addLine(to: CGPoint(x: cx + 7, y: cy + 4))
            path.addLine(to: CGPoint(x: cx + 7, y: cy - 4))
            path.addLine(to: CGPoint(x: cx, y: cy - 9))
            path.addLine(to: CGPoint(x: cx - 7, y: cy - 4))
            path.addLine(to: CGPoint(x: cx - 7, y: cy + 4))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.strokePath()
        case .multishot: // 3 parallel arrows
            for dx: CGFloat in [-6, 0, 6] {
                ctx.move(to: CGPoint(x: cx + dx, y: cy - 8))
                ctx.addLine(to: CGPoint(x: cx + dx, y: cy + 8))
                ctx.strokePath()
            }
        case .critFocus: // crosshair
            ctx.strokeEllipse(in: CGRect(x: cx - 7, y: cy - 7, width: 14, height: 14))
            ctx.move(to: CGPoint(x: cx, y: cy - 10)); ctx.addLine(to: CGPoint(x: cx, y: cy + 10)); ctx.strokePath()
            ctx.move(to: CGPoint(x: cx - 10, y: cy)); ctx.addLine(to: CGPoint(x: cx + 10, y: cy)); ctx.strokePath()
        case .ashenWake: // small leaf/plus
            ctx.move(to: CGPoint(x: cx, y: cy - 8)); ctx.addLine(to: CGPoint(x: cx, y: cy + 8)); ctx.strokePath()
            ctx.move(to: CGPoint(x: cx - 6, y: cy)); ctx.addLine(to: CGPoint(x: cx + 6, y: cy)); ctx.strokePath()
        case .secondWind: // wing sweep
            let path = CGMutablePath()
            path.addArc(center: CGPoint(x: cx, y: cy - 4), radius: 9, startAngle: .pi * 0.9, endAngle: .pi * 0.1, clockwise: true)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    /// A quick press-flash before GameScene removes the whole overlay.
    func flashSelected(index: Int) {
        guard index >= 0, index < cardNodes.count else { return }
        cardNodes[index].run(SKAction.sequence([
            SKAction.scale(to: 1.06, duration: 0.06),
            SKAction.scale(to: 1.0, duration: 0.08)
        ]))
    }

    /// Rebuilds the card set in place with a fresh roll — the overlay itself stays open/showing.
    func reroll(choices: [UpgradeChoice]) {
        self.choices = choices
        for card in cardNodes { card.removeFromParent() }
        cardNodes.removeAll()
        layoutCards(choices: choices, screenSize: lastScreenSize, animated: false)
        // A quick pop across all cards reads as "reshuffled" without a full re-entrance animation.
        for card in cardNodes {
            card.run(SKAction.sequence([SKAction.scale(to: 0.92, duration: 0.06), SKAction.scale(to: 1.0, duration: 0.1)]))
        }
        shuffleButtonNode.run(SKAction.sequence([SKAction.scale(to: 0.94, duration: 0.06), SKAction.scale(to: 1.0, duration: 0.1)]))
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
