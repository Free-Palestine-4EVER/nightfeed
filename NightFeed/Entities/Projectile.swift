import SpriteKit

/// Pooled traveling projectile used by straight-shot, piercing and homing weapons.
/// Orbiters, the melee whirl and AoE bursts are NOT projectiles — WeaponSystem manages those directly
/// since there are only ever a handful of them (no pooling needed at that scale).
final class Projectile: SKSpriteNode {
    private(set) var weaponKind: WeaponKind = .fangBolt
    var damage: CGFloat = 0
    var isCrit: Bool = false
    var pierceRemaining: Int = 0
    var velocity: CGVector = .zero
    var isActive: Bool = false
    var isHoming: Bool = false
    var homingTargetProvider: (() -> Enemy?)?

    private var traveled: CGFloat = 0
    private var maxRange: CGFloat = 900
    private var hitEnemyIDs: Set<ObjectIdentifier> = []
    private let turnRatePerSecond: CGFloat = 6.0

    static func makeNode() -> Projectile {
        let node = Projectile(texture: nil, color: .clear, size: CGSize(width: 20, height: 20))
        node.zPosition = ZPosition.projectile
        node.isHidden = true
        return node
    }

    func configure(kind: WeaponKind, damage: CGFloat, isCrit: Bool, position: CGPoint,
                   direction: CGVector, speed: CGFloat, pierce: Int, maxRange: CGFloat,
                   homing: Bool, homingTarget: (() -> Enemy?)?) {
        self.weaponKind = kind
        self.damage = damage
        self.isCrit = isCrit
        self.position = position
        self.pierceRemaining = pierce
        self.maxRange = maxRange
        self.traveled = 0
        self.isActive = true
        self.isHoming = homing
        self.homingTargetProvider = homingTarget
        self.hitEnemyIDs.removeAll(keepingCapacity: true)
        self.isHidden = false
        self.alpha = 1
        self.texture = Projectile.proceduralTexture(for: kind)
        self.setScale(isCrit ? 1.35 : 1.0)

        let len = max(0.001, sqrt(direction.dx * direction.dx + direction.dy * direction.dy))
        self.velocity = CGVector(dx: direction.dx / len * speed, dy: direction.dy / len * speed)
        self.zRotation = atan2(velocity.dy, velocity.dx)
    }

    func prepareForReuse() {
        isActive = false
        isHidden = true
        homingTargetProvider = nil
        removeAllActions()
    }

    /// Advances the projectile; returns true when it should be retired (exceeded range).
    func step(deltaTime: TimeInterval) -> Bool {
        guard isActive else { return true }

        if isHoming, let target = homingTargetProvider?(), target.isAlive {
            let toTargetX: CGFloat = target.position.x - position.x
            let toTargetY: CGFloat = target.position.y - position.y
            let distSq: CGFloat = toTargetX * toTargetX + toTargetY * toTargetY
            let dist: CGFloat = max(0.001, sqrt(distSq))
            let desiredX: CGFloat = toTargetX / dist
            let desiredY: CGFloat = toTargetY / dist

            let speedSq: CGFloat = velocity.dx * velocity.dx + velocity.dy * velocity.dy
            let speed: CGFloat = sqrt(speedSq)
            let currentLen: CGFloat = max(0.001, speed)
            let currentX: CGFloat = velocity.dx / currentLen
            let currentY: CGFloat = velocity.dy / currentLen

            let t: CGFloat = CGFloat(min(1.0, turnRatePerSecond * deltaTime))
            let blendedX: CGFloat = currentX + (desiredX - currentX) * t
            let blendedY: CGFloat = currentY + (desiredY - currentY) * t
            let blendedLenSq: CGFloat = blendedX * blendedX + blendedY * blendedY
            let blendedLen: CGFloat = max(0.001, sqrt(blendedLenSq))
            velocity = CGVector(dx: blendedX / blendedLen * speed, dy: blendedY / blendedLen * speed)
        }

        let dx = velocity.dx * CGFloat(deltaTime)
        let dy = velocity.dy * CGFloat(deltaTime)
        position = CGPoint(x: position.x + dx, y: position.y + dy)
        zRotation = atan2(velocity.dy, velocity.dx)
        traveled += sqrt(dx * dx + dy * dy)
        return traveled >= maxRange
    }

    /// Returns true if this enemy hasn't been hit by this projectile flight yet (and records it now).
    /// Also returns true (and decrements pierce) — caller should retire the projectile once pierce runs out.
    func registerHit(on enemy: Enemy) -> Bool {
        let id = ObjectIdentifier(enemy)
        guard !hitEnemyIDs.contains(id) else { return false }
        hitEnemyIDs.insert(id)
        return true
    }

    var isOutOfPierce: Bool {
        if pierceRemaining <= 0 { return true }
        pierceRemaining -= 1
        return pierceRemaining < 0
    }

    // MARK: - Procedural textures, cached per weapon kind.
    private static var textureCache: [WeaponKind: SKTexture] = [:]

    static func proceduralTexture(for kind: WeaponKind) -> SKTexture {
        if let cached = textureCache[kind] { return cached }
        let tex = ProceduralTextures.render(size: CGSize(width: 40, height: 40)) { ctx, size in
            draw(kind: kind, in: ctx, size: size)
        }
        textureCache[kind] = tex
        return tex
    }

    private static func draw(kind: WeaponKind, in ctx: CGContext, size: CGSize) {
        let cx = size.width / 2, cy = size.height / 2
        switch kind {
        case .fangBolt:
            ctx.setFillColor(SKColor(red: 0.65, green: 0.9, blue: 1.0, alpha: 1).cgColor)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: size.width - 4, y: cy))
            path.addLine(to: CGPoint(x: 6, y: cy + 7))
            path.addLine(to: CGPoint(x: 14, y: cy))
            path.addLine(to: CGPoint(x: 6, y: cy - 7))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.fillPath()
        case .bloodLance:
            ctx.setFillColor(SKColor(red: 0.85, green: 0.15, blue: 0.2, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 2, y: cy - 3, width: size.width - 10, height: 6))
            let tip = CGMutablePath()
            tip.move(to: CGPoint(x: size.width - 2, y: cy))
            tip.addLine(to: CGPoint(x: size.width - 14, y: cy + 8))
            tip.addLine(to: CGPoint(x: size.width - 14, y: cy - 8))
            tip.closeSubpath()
            ctx.addPath(tip)
            ctx.fillPath()
        case .batSwarm:
            ctx.setFillColor(SKColor(red: 0.55, green: 0.2, blue: 0.75, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 9, y: cy - 6, width: 18, height: 12))
        case .starShard:
            ctx.setFillColor(SKColor(red: 0.75, green: 0.92, blue: 1.0, alpha: 1).cgColor)
            let shard = CGMutablePath()
            shard.move(to: CGPoint(x: cx + 12, y: cy))
            shard.addLine(to: CGPoint(x: cx, y: cy + 7))
            shard.addLine(to: CGPoint(x: cx - 12, y: cy))
            shard.addLine(to: CGPoint(x: cx, y: cy - 7))
            shard.closeSubpath()
            ctx.addPath(shard)
            ctx.fillPath()
        default:
            ctx.setFillColor(SKColor(red: 1, green: 0.95, blue: 0.7, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 8, y: cy - 8, width: 16, height: 16))
        }
    }
}
