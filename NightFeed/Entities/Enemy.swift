import SpriteKit

/// Pooled enemy node. Never destroyed once created — `configure` re-arms it on spawn,
/// `prepareForReuse` retires it back to PoolManager on death/despawn.
final class Enemy: SKSpriteNode {
    private(set) var kind: EnemyKind = .swarmling
    var hp: CGFloat = 0
    var maxHP: CGFloat = 0
    var moveSpeed: CGFloat = 0
    var contactDamage: CGFloat = 0
    var xpValue: Int = 0
    var goldValue: Int = 0
    var isAlive: Bool = false
    var isMiniBoss: Bool { kind.isMiniBoss }
    /// Simple per-instance wander offset so bloodbats don't all fly in lockstep.
    var wanderSeed: CGFloat = 0

    private var lastContactTick: TimeInterval = -999
    private var healthBarFill: SKShapeNode?
    private weak var bodySprite: SKSpriteNode?

    static func makeNode() -> Enemy {
        let enemy = Enemy(texture: nil, color: .clear, size: CGSize(width: 44, height: 44))
        enemy.zPosition = ZPosition.enemy
        enemy.isHidden = true

        let shadow = SKShapeNode(ellipseOf: CGSize(width: 30, height: 12))
        shadow.fillColor = SKColor.black.withAlphaComponent(0.35)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -18)
        shadow.zPosition = -1
        enemy.addChild(shadow)

        let body = SKSpriteNode(texture: nil, size: CGSize(width: 44, height: 44))
        enemy.addChild(body)
        enemy.bodySprite = body

        return enemy
    }

    func configure(kind: EnemyKind, stats: EnemyLevelStats, position: CGPoint, wanderSeed: CGFloat) {
        self.kind = kind
        self.hp = stats.hp
        self.maxHP = stats.hp
        self.moveSpeed = stats.moveSpeed
        self.contactDamage = stats.contactDamage
        self.xpValue = stats.xpValue
        self.goldValue = stats.goldValue
        self.wanderSeed = wanderSeed
        self.isAlive = true
        self.position = position
        self.setScale(stats.visualScale)
        self.alpha = 1
        self.isHidden = false
        self.lastContactTick = -999
        self.zRotation = 0
        bodySprite?.texture = Enemy.proceduralTexture(for: kind)
        removeAction(forKey: "hitFlash")
        colorBlendFactor = 0

        if kind.isMiniBoss {
            attachHealthBar()
        } else if let bar = healthBarFill {
            bar.parent?.removeFromParent()
            healthBarFill = nil
        }
    }

    func prepareForReuse() {
        isAlive = false
        isHidden = true
        removeAllActions()
        healthBarFill?.parent?.removeFromParent()
        healthBarFill = nil
    }

    /// Returns true if this hit killed the enemy.
    @discardableResult
    func takeDamage(_ amount: CGFloat) -> Bool {
        guard isAlive else { return false }
        hp -= amount
        flashHit()
        updateHealthBar()
        if hp <= 0 {
            isAlive = false
            return true
        }
        return false
    }

    private func flashHit() {
        removeAction(forKey: "hitFlash")
        colorBlendFactor = 1
        color = .white
        run(SKAction.sequence([
            SKAction.wait(forDuration: 0.07),
            SKAction.run { [weak self] in self?.colorBlendFactor = 0 }
        ]), withKey: "hitFlash")
    }

    func canTickContactDamage(now: TimeInterval) -> Bool {
        guard now - lastContactTick >= PlayerConfig.contactDamageInterval else { return false }
        lastContactTick = now
        return true
    }

    private func attachHealthBar() {
        let track = SKShapeNode(rectOf: CGSize(width: 78, height: 9), cornerRadius: 3)
        track.fillColor = SKColor.black.withAlphaComponent(0.6)
        track.strokeColor = SKColor.white.withAlphaComponent(0.4)
        track.lineWidth = 1
        track.position = CGPoint(x: 0, y: 48)
        track.zPosition = 5
        addChild(track)

        let fill = SKShapeNode(rectOf: CGSize(width: 74, height: 5), cornerRadius: 2)
        fill.fillColor = SKColor(red: 0.85, green: 0.12, blue: 0.2, alpha: 1)
        fill.strokeColor = .clear
        fill.position = CGPoint(x: 0, y: 48)
        fill.zPosition = 6
        addChild(fill)
        healthBarFill = fill
    }

    private func updateHealthBar() {
        guard let bar = healthBarFill else { return }
        let pct = max(0, hp / maxHP)
        bar.xScale = max(0.001, pct)
    }

    // MARK: - Procedural textures, generated once per kind and cached for the lifetime of the app.
    private static var textureCache: [EnemyKind: SKTexture] = [:]

    static func proceduralTexture(for kind: EnemyKind) -> SKTexture {
        if let cached = textureCache[kind] { return cached }
        let tex = ProceduralTextures.render(size: CGSize(width: 88, height: 88)) { ctx, size in
            draw(kind: kind, in: ctx, size: size)
        }
        textureCache[kind] = tex
        return tex
    }

    private static func draw(kind: EnemyKind, in ctx: CGContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        let cx = size.width / 2, cy = size.height / 2

        switch kind {
        case .swarmling:
            ctx.setFillColor(SKColor(red: 0.55, green: 0.12, blue: 0.66, alpha: 1).cgColor)
            ctx.fillEllipse(in: rect.insetBy(dx: 20, dy: 20))
            ctx.setFillColor(SKColor(red: 0.92, green: 0.87, blue: 1.0, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 11, y: cy + 2, width: 7, height: 7))
            ctx.fillEllipse(in: CGRect(x: cx + 4, y: cy + 2, width: 7, height: 7))

        case .bloodbat:
            ctx.setFillColor(SKColor(red: 0.66, green: 0.06, blue: 0.13, alpha: 1).cgColor)
            let wing = CGMutablePath()
            wing.move(to: CGPoint(x: 8, y: cy))
            wing.addQuadCurve(to: CGPoint(x: cx, y: cy + 16), control: CGPoint(x: cx - 16, y: cy + 34))
            wing.addQuadCurve(to: CGPoint(x: size.width - 8, y: cy), control: CGPoint(x: cx + 16, y: cy + 34))
            wing.addQuadCurve(to: CGPoint(x: cx, y: cy - 12), control: CGPoint(x: cx, y: cy - 4))
            wing.closeSubpath()
            ctx.addPath(wing)
            ctx.fillPath()
            ctx.setFillColor(SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 6, y: cy - 2, width: 5, height: 5))
            ctx.fillEllipse(in: CGRect(x: cx + 1, y: cy - 2, width: 5, height: 5))

        case .hollowBrute:
            ctx.setFillColor(SKColor(red: 0.2, green: 0.16, blue: 0.23, alpha: 1).cgColor)
            ctx.fillEllipse(in: rect.insetBy(dx: 10, dy: 10))
            ctx.setStrokeColor(SKColor(red: 0.85, green: 0.22, blue: 0.26, alpha: 1).cgColor)
            ctx.setLineWidth(4)
            ctx.strokeEllipse(in: rect.insetBy(dx: 12, dy: 12))
            ctx.setFillColor(SKColor(red: 0.85, green: 0.22, blue: 0.26, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 12, y: cy - 2, width: 8, height: 8))
            ctx.fillEllipse(in: CGRect(x: cx + 4, y: cy - 2, width: 8, height: 8))

        case .nightmaw:
            ctx.setFillColor(SKColor(red: 0.07, green: 0.02, blue: 0.1, alpha: 1).cgColor)
            ctx.fillEllipse(in: rect.insetBy(dx: 4, dy: 4))
            ctx.setStrokeColor(SKColor(red: 1, green: 0.38, blue: 0.16, alpha: 1).cgColor)
            ctx.setLineWidth(6)
            ctx.strokeEllipse(in: rect.insetBy(dx: 5, dy: 5))
            ctx.setFillColor(SKColor(red: 1, green: 0.92, blue: 0.55, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 18, y: cy, width: 11, height: 15))
            ctx.fillEllipse(in: CGRect(x: cx + 7, y: cy, width: 11, height: 15))
        }
    }
}
