import SpriteKit

/// Pooled world-pickup potion (see PotionKind/PotionSystem/PotionConfig). Idles with a gentle bob +
/// pulsing glow, flickers faster once it's about to expire, and is retired back to the pool by
/// PotionSystem either on pickup or on lifetime expiry — mirrors XPGem's pooled-entity shape.
final class Potion: SKSpriteNode {
    private(set) var isActive: Bool = false
    private(set) var kind: PotionKind = .crimsonVigor

    private var elapsed: TimeInterval = 0
    private var isFlickering: Bool = false

    static func makeNode() -> Potion {
        let size = CGSize(width: PotionConfig.visualRadius * 2, height: PotionConfig.visualRadius * 2)
        let node = Potion(texture: Potion.texture(for: .crimsonVigor), color: .clear, size: size)
        node.zPosition = ZPosition.xpGem
        node.isHidden = true
        return node
    }

    func configure(kind: PotionKind, at position: CGPoint) {
        self.kind = kind
        self.texture = Potion.texture(for: kind)
        self.position = position
        self.isActive = true
        self.isHidden = false
        self.alpha = 1
        self.zRotation = 0
        self.elapsed = 0
        self.isFlickering = false
        self.setScale(kind == .risingMoon ? 1.15 : 1.0)
        removeAllActions()
        startIdleAnimation()
    }

    func prepareForReuse() {
        isActive = false
        isHidden = true
        isFlickering = false
        removeAllActions()
        alpha = 1
    }

    /// Called once per frame by PotionSystem. Returns true once this potion's lifetime
    /// (PotionConfig.lifetime) has elapsed and it should be retired back to the pool.
    func update(deltaTime: TimeInterval) -> Bool {
        guard isActive else { return false }
        elapsed += deltaTime
        if elapsed >= PotionConfig.lifetime { return true }

        // Last ~25% of lifetime: swap the idle bob/glow for a faster, more urgent flicker so the
        // player can see it's about to despawn.
        if !isFlickering && elapsed >= PotionConfig.lifetime * 0.75 {
            isFlickering = true
            startFlicker()
        }
        return false
    }

    // MARK: - Idle animation

    private func startIdleAnimation() {
        run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 0, y: 4, duration: 0.6),
            SKAction.moveBy(x: 0, y: -4, duration: 0.6)
        ])), withKey: "bob")

        run(SKAction.repeatForever(SKAction.group([
            SKAction.sequence([SKAction.scale(by: 1.1, duration: 0.55), SKAction.scale(by: 1 / 1.1, duration: 0.55)]),
            SKAction.sequence([SKAction.fadeAlpha(to: 0.72, duration: 0.55), SKAction.fadeAlpha(to: 1.0, duration: 0.55)])
        ])), withKey: "glow")
    }

    private func startFlicker() {
        removeAction(forKey: "bob")
        removeAction(forKey: "glow")
        run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 0, y: 3, duration: 0.16),
            SKAction.moveBy(x: 0, y: -3, duration: 0.16)
        ])), withKey: "bob")
        run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.14),
            SKAction.fadeAlpha(to: 1.0, duration: 0.14)
        ])), withKey: "glow")
    }

    // MARK: - Procedural visuals

    /// Per-kind color identity. Exposed so PotionSystem can tint its pickup burst to match.
    static func accentColor(for kind: PotionKind) -> SKColor { palette(for: kind).glow }

    private struct PotionPalette {
        let fill: SKColor
        let rim: SKColor
        let glow: SKColor
        let glyph: SKColor
    }

    private static func palette(for kind: PotionKind) -> PotionPalette {
        switch kind {
        case .crimsonVigor:
            return PotionPalette(fill: SKColor(red: 0.92, green: 0.22, blue: 0.1, alpha: 1),
                                  rim: SKColor(red: 1, green: 0.58, blue: 0.16, alpha: 1),
                                  glow: SKColor(red: 1, green: 0.35, blue: 0.1, alpha: 1),
                                  glyph: SKColor(red: 1, green: 0.94, blue: 0.85, alpha: 1))
        case .nightHaste:
            return PotionPalette(fill: SKColor(red: 0.1, green: 0.62, blue: 0.95, alpha: 1),
                                  rim: SKColor(red: 0.55, green: 0.95, blue: 1, alpha: 1),
                                  glow: SKColor(red: 0.25, green: 0.78, blue: 1, alpha: 1),
                                  glyph: .white)
        case .voidAegis:
            return PotionPalette(fill: SKColor(red: 0.94, green: 0.93, blue: 0.86, alpha: 1),
                                  rim: SKColor(red: 1, green: 0.86, blue: 0.4, alpha: 1),
                                  glow: SKColor(red: 1, green: 0.95, blue: 0.75, alpha: 1),
                                  glyph: SKColor(red: 0.5, green: 0.4, blue: 0.1, alpha: 1))
        case .hungerSurge:
            return PotionPalette(fill: SKColor(red: 0.13, green: 0.72, blue: 0.34, alpha: 1),
                                  rim: SKColor(red: 0.55, green: 1, blue: 0.55, alpha: 1),
                                  glow: SKColor(red: 0.25, green: 0.85, blue: 0.4, alpha: 1),
                                  glyph: .white)
        case .bloodFrenzy:
            return PotionPalette(fill: SKColor(red: 0.46, green: 0.04, blue: 0.09, alpha: 1),
                                  rim: SKColor(red: 0.58, green: 0.16, blue: 0.78, alpha: 1),
                                  glow: SKColor(red: 0.7, green: 0.1, blue: 0.35, alpha: 1),
                                  glyph: SKColor(red: 0.86, green: 0.56, blue: 1, alpha: 1))
        case .voidMagnet:
            return PotionPalette(fill: SKColor(red: 0.44, green: 0.2, blue: 0.74, alpha: 1),
                                  rim: SKColor(red: 0.25, green: 0.85, blue: 0.76, alpha: 1),
                                  glow: SKColor(red: 0.52, green: 0.36, blue: 0.86, alpha: 1),
                                  glyph: SKColor(red: 0.78, green: 1, blue: 0.95, alpha: 1))
        case .risingMoon:
            return PotionPalette(fill: SKColor(red: 1, green: 0.85, blue: 0.24, alpha: 1),
                                  rim: SKColor(red: 1, green: 0.97, blue: 0.72, alpha: 1),
                                  glow: SKColor(red: 1, green: 0.9, blue: 0.4, alpha: 1),
                                  glyph: SKColor(red: 0.35, green: 0.22, blue: 0.04, alpha: 1))
        }
    }

    private static let texturesByKind: [PotionKind: SKTexture] = {
        var dict: [PotionKind: SKTexture] = [:]
        for kind in PotionKind.allCases { dict[kind] = makeTexture(for: kind) }
        return dict
    }()

    private static func texture(for kind: PotionKind) -> SKTexture {
        texturesByKind[kind] ?? texturesByKind[.crimsonVigor]!
    }

    /// Draws a shared vial silhouette (color/rim per kind) topped with a small per-kind glyph, sitting
    /// in front of a soft radial glow — Rising Moon gets an extra, wider glow pass since it's the rarest.
    private static func makeTexture(for kind: PotionKind) -> SKTexture {
        let p = palette(for: kind)
        let canvasSize = CGSize(width: 40, height: 40)
        return ProceduralTextures.render(size: canvasSize) { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            if kind == .risingMoon {
                drawGlow(ctx: ctx, center: center, color: p.glow, radius: 19, alpha: 0.45)
            }
            drawGlow(ctx: ctx, center: center, color: p.glow, radius: kind == .risingMoon ? 14 : 15, alpha: 0.6)

            let bodyCenter = CGPoint(x: center.x, y: center.y - 2)
            drawVialBody(ctx: ctx, center: bodyCenter, fill: p.fill, rim: p.rim)
            drawGlyph(kind, ctx: ctx, center: CGPoint(x: bodyCenter.x, y: bodyCenter.y - 4), color: p.glyph)
        }
    }

    private static func drawGlow(ctx: CGContext, center: CGPoint, color: SKColor, radius: CGFloat, alpha: CGFloat) {
        let colors = [color.withAlphaComponent(alpha).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    private static func drawVialBody(ctx: CGContext, center: CGPoint, fill: SKColor, rim: SKColor) {
        let cx = center.x, cy = center.y

        // Rounded bulb body, a simple closed bezier teardrop.
        let bulb = CGMutablePath()
        bulb.move(to: CGPoint(x: cx - 3, y: cy + 6))
        bulb.addLine(to: CGPoint(x: cx - 7, y: cy - 2))
        bulb.addQuadCurve(to: CGPoint(x: cx, y: cy - 13), control: CGPoint(x: cx - 9, y: cy - 11))
        bulb.addQuadCurve(to: CGPoint(x: cx + 7, y: cy - 2), control: CGPoint(x: cx + 9, y: cy - 11))
        bulb.addLine(to: CGPoint(x: cx + 3, y: cy + 6))
        bulb.closeSubpath()

        ctx.setFillColor(fill.withAlphaComponent(0.94).cgColor)
        ctx.addPath(bulb)
        ctx.fillPath()
        ctx.setStrokeColor(rim.cgColor)
        ctx.setLineWidth(1.6)
        ctx.addPath(bulb)
        ctx.strokePath()

        // Glass highlight streak.
        ctx.setStrokeColor(SKColor.white.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(1.2)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: cx - 4, y: cy - 8))
        ctx.addLine(to: CGPoint(x: cx - 2, y: cy + 2))
        ctx.strokePath()

        // Neck.
        let neckRect = CGRect(x: cx - 3, y: cy + 6, width: 6, height: 6)
        let neckPath = CGPath(roundedRect: neckRect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
        ctx.setFillColor(SKColor(white: 0.85, alpha: 0.9).cgColor)
        ctx.addPath(neckPath)
        ctx.fillPath()
        ctx.setStrokeColor(rim.cgColor)
        ctx.setLineWidth(1.2)
        ctx.addPath(neckPath)
        ctx.strokePath()

        // Cork.
        let corkRect = CGRect(x: cx - 4, y: cy + 11, width: 8, height: 3)
        let corkPath = CGPath(roundedRect: corkRect, cornerWidth: 1.4, cornerHeight: 1.4, transform: nil)
        ctx.setFillColor(SKColor(red: 0.36, green: 0.23, blue: 0.12, alpha: 1).cgColor)
        ctx.addPath(corkPath)
        ctx.fillPath()
    }

    private static func drawGlyph(_ kind: PotionKind, ctx: CGContext, center: CGPoint, color: SKColor) {
        let cx = center.x, cy = center.y
        ctx.setFillColor(color.cgColor)
        ctx.setStrokeColor(color.cgColor)

        switch kind {
        case .crimsonVigor:
            // Small flame.
            let flame = CGMutablePath()
            flame.move(to: CGPoint(x: cx, y: cy - 6))
            flame.addCurve(to: CGPoint(x: cx, y: cy + 7),
                            control1: CGPoint(x: cx - 6, y: cy - 2), control2: CGPoint(x: cx - 4, y: cy + 5))
            flame.addCurve(to: CGPoint(x: cx, y: cy - 6),
                            control1: CGPoint(x: cx + 4, y: cy + 5), control2: CGPoint(x: cx + 6, y: cy - 2))
            flame.closeSubpath()
            ctx.addPath(flame)
            ctx.fillPath()

        case .nightHaste:
            // Small lightning bolt.
            let bolt = CGMutablePath()
            bolt.move(to: CGPoint(x: cx + 2, y: cy + 7))
            bolt.addLine(to: CGPoint(x: cx - 4, y: cy + 0))
            bolt.addLine(to: CGPoint(x: cx, y: cy + 0))
            bolt.addLine(to: CGPoint(x: cx - 2, y: cy - 7))
            bolt.addLine(to: CGPoint(x: cx + 4, y: cy - 1))
            bolt.addLine(to: CGPoint(x: cx, y: cy - 1))
            bolt.closeSubpath()
            ctx.addPath(bolt)
            ctx.fillPath()

        case .voidAegis:
            // Small shield.
            let shield = CGMutablePath()
            shield.move(to: CGPoint(x: cx, y: cy + 7))
            shield.addLine(to: CGPoint(x: cx + 6, y: cy + 3))
            shield.addLine(to: CGPoint(x: cx + 6, y: cy - 3))
            shield.addQuadCurve(to: CGPoint(x: cx, y: cy - 8), control: CGPoint(x: cx + 4, y: cy - 7))
            shield.addQuadCurve(to: CGPoint(x: cx - 6, y: cy - 3), control: CGPoint(x: cx - 4, y: cy - 7))
            shield.addLine(to: CGPoint(x: cx - 6, y: cy + 3))
            shield.closeSubpath()
            ctx.addPath(shield)
            ctx.fillPath()

        case .hungerSurge:
            // Small heart.
            let r: CGFloat = 3.4
            ctx.fillEllipse(in: CGRect(x: cx - r * 2, y: cy - 1, width: r * 2, height: r * 2))
            ctx.fillEllipse(in: CGRect(x: cx, y: cy - 1, width: r * 2, height: r * 2))
            let tip = CGMutablePath()
            tip.move(to: CGPoint(x: cx - r * 2 + 0.5, y: cy))
            tip.addLine(to: CGPoint(x: cx + r * 2 - 0.5, y: cy))
            tip.addLine(to: CGPoint(x: cx, y: cy - 8))
            tip.closeSubpath()
            ctx.addPath(tip)
            ctx.fillPath()

        case .bloodFrenzy:
            // Three claw slashes.
            ctx.setLineWidth(1.8)
            ctx.setLineCap(.round)
            for offset: CGFloat in [-4, 0, 4] {
                ctx.move(to: CGPoint(x: cx - 5 + offset, y: cy + 6))
                ctx.addLine(to: CGPoint(x: cx + 3 + offset, y: cy - 6))
            }
            ctx.strokePath()

        case .voidMagnet:
            // Small 4-point star/sparkle.
            let star = CGMutablePath()
            star.move(to: CGPoint(x: cx, y: cy + 8))
            star.addLine(to: CGPoint(x: cx + 2, y: cy + 2))
            star.addLine(to: CGPoint(x: cx + 8, y: cy))
            star.addLine(to: CGPoint(x: cx + 2, y: cy - 2))
            star.addLine(to: CGPoint(x: cx, y: cy - 8))
            star.addLine(to: CGPoint(x: cx - 2, y: cy - 2))
            star.addLine(to: CGPoint(x: cx - 8, y: cy))
            star.addLine(to: CGPoint(x: cx - 2, y: cy + 2))
            star.closeSubpath()
            ctx.addPath(star)
            ctx.fillPath()

        case .risingMoon:
            // Crescent moon: a filled disc with an offset disc cut out via clear blend mode.
            ctx.fillEllipse(in: CGRect(x: cx - 6, y: cy - 6, width: 12, height: 12))
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: CGRect(x: cx - 2, y: cy - 6, width: 12, height: 12))
            ctx.setBlendMode(.normal)
        }
    }
}
