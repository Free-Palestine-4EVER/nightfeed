import SpriteKit

/// Pooled XP pickup. Idles with a small bob, then accelerates toward the player once inside magnet radius.
final class XPGem: SKSpriteNode {
    var xpValue: Int = 0
    var isActive: Bool = false
    private var bobPhase: CGFloat = 0
    private var isMagnetized: Bool = false

    static func makeNode() -> XPGem {
        let node = XPGem(texture: XPGem.sharedTexture, color: .clear, size: CGSize(width: 16, height: 16))
        node.zPosition = ZPosition.xpGem
        node.isHidden = true
        return node
    }

    func configure(xpValue: Int, at position: CGPoint) {
        self.xpValue = xpValue
        self.position = position
        self.isActive = true
        self.isMagnetized = false
        self.isHidden = false
        self.alpha = 1
        self.setScale(xpValue >= 6 ? 1.5 : 1.0)
        self.bobPhase = CGFloat.random(in: 0...(2 * .pi))
        removeAllActions()
        run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 0, y: 4, duration: 0.5),
            SKAction.moveBy(x: 0, y: -4, duration: 0.5)
        ])), withKey: "bob")
    }

    func prepareForReuse() {
        isActive = false
        isHidden = true
        removeAllActions()
    }

    /// Returns true once the gem has reached the player and should be collected.
    func update(deltaTime: TimeInterval, playerPosition: CGPoint, magnetRadius: CGFloat) -> Bool {
        let dx = playerPosition.x - position.x
        let dy = playerPosition.y - position.y
        let distSq = dx * dx + dy * dy

        if !isMagnetized && distSq <= magnetRadius * magnetRadius {
            isMagnetized = true
            removeAction(forKey: "bob")
        }

        guard isMagnetized else { return false }

        let dist = sqrt(distSq)
        if dist <= 18 { return true }

        let step = min(dist, XPConfig.gemMagnetSpeed * CGFloat(deltaTime) * (1 + (1 - dist / max(1, magnetRadius * 2))))
        position = CGPoint(x: position.x + dx / dist * step, y: position.y + dy / dist * step)
        return false
    }

    private static let sharedTexture: SKTexture = ProceduralTextures.render(size: CGSize(width: 24, height: 24)) { ctx, size in
        let cx = size.width / 2, cy = size.height / 2
        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: .pi / 4)
        ctx.setFillColor(SKColor(red: 0.35, green: 0.95, blue: 0.85, alpha: 1).cgColor)
        ctx.fill(CGRect(x: -7, y: -7, width: 14, height: 14))
        ctx.restoreGState()
        ctx.setFillColor(SKColor(red: 0.85, green: 1.0, blue: 0.98, alpha: 0.85).cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6))
    }
}
