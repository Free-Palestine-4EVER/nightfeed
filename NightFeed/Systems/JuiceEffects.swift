import SpriteKit

/// Shared "feel" helpers — hit particles, damage numbers, screen shake, haptics.
/// Every subsystem (weapons on hit, spawner on death, XP system on level-up) calls into this
/// rather than building its own one-off SKEmitterNode/SKAction, so the game feel stays consistent.
enum JuiceEffects {

    // MARK: - Hit particle bursts (pooled emitters, never allocated per-hit)

    static func makeHitBurstTemplate() -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = dotTexture
        emitter.particleBirthRate = 0
        emitter.numParticlesToEmit = 10
        emitter.particleLifetime = 0.35
        emitter.particleLifetimeRange = 0.15
        emitter.particleSpeed = 160
        emitter.particleSpeedRange = 90
        emitter.emissionAngleRange = .pi * 2
        emitter.particleAlpha = 0.9
        emitter.particleAlphaSpeed = -2.6
        emitter.particleScale = 0.5
        emitter.particleScaleRange = 0.25
        emitter.particleScaleSpeed = -0.9
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        return emitter
    }

    /// Fires a one-shot burst using a pooled emitter, returning it to the pool automatically once spent.
    static func hitBurst(at position: CGPoint, color: SKColor, scale: CGFloat = 1.0) {
        let emitter = PoolManager.shared.dequeueEmitter()
        emitter.position = position
        emitter.particleColor = color
        emitter.particleScale = 0.5 * scale
        emitter.isHidden = false
        emitter.resetSimulation()
        emitter.particleBirthRate = 800
        emitter.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.02),
            SKAction.run { emitter.particleBirthRate = 0 },
            SKAction.wait(forDuration: 0.5),
            SKAction.run { emitter.isHidden = true }
        ]))
    }

    // MARK: - Damage numbers

    static func damageNumber(_ amount: Int, isCrit: Bool, at position: CGPoint) {
        let label = PoolManager.shared.dequeueDamageLabel()
        label.text = isCrit ? "\(amount)!" : "\(amount)"
        label.fontSize = isCrit ? 30 : 20
        label.fontColor = isCrit ? SKColor(red: 1, green: 0.82, blue: 0.2, alpha: 1) : SKColor(red: 1, green: 0.95, blue: 0.92, alpha: 1)
        label.position = CGPoint(x: position.x + CGFloat.random(in: -8...8), y: position.y + 14)
        label.alpha = 1
        label.setScale(isCrit ? 1.15 : 0.9)
        label.zRotation = 0
        label.isHidden = false
        label.removeAllActions()
        let rise = SKAction.moveBy(x: CGFloat.random(in: -6...6), y: 34, duration: 0.55)
        rise.timingMode = .easeOut
        let fade = SKAction.sequence([SKAction.wait(forDuration: 0.25), SKAction.fadeOut(withDuration: 0.3)])
        let pop = SKAction.sequence([SKAction.scale(to: (isCrit ? 1.35 : 1.05), duration: 0.08), SKAction.scale(to: (isCrit ? 1.1 : 0.9), duration: 0.1)])
        label.run(SKAction.group([rise, fade, pop])) { [weak label] in
            label?.isHidden = true
        }
    }

    // MARK: - Button press/release feedback

    /// Standard press-down scale for a tappable button/card/chip — quick and responsive.
    static func pressDown(_ node: SKNode) {
        node.run(SKAction.scale(to: 0.94, duration: 0.08))
    }

    /// Standard release feedback: eases back with a brief overshoot past 1.0 before settling, so
    /// lifting a finger always reads as a small, satisfying bounce rather than a flat snap-back.
    /// Combined duration stays well under 150ms so it never reads as sluggish.
    static func releaseBounce(_ node: SKNode) {
        node.run(SKAction.sequence([
            SKAction.scale(to: 1.04, duration: 0.07),
            SKAction.scale(to: 1.0, duration: 0.06)
        ]))
    }

    /// Brief scale punch for a label whose displayed value just changed (gold, tier, etc.), so the
    /// change registers as an event instead of silently snapping to the new number. Short enough that
    /// rapid successive changes never visually stack up.
    static func numberPunch(_ node: SKNode) {
        node.run(SKAction.sequence([
            SKAction.scale(to: 1.16, duration: 0.09),
            SKAction.scale(to: 1.0, duration: 0.12)
        ]))
    }

    // MARK: - Staggered entrances

    /// Slides + fades (and, by default, scales-with-a-slight-overshoot) `node` in from its current
    /// position, after `delay`. Reads the node's CURRENT position/scale as the landing target, so
    /// callers should lay the node out at its real final position/scale first (typically because the
    /// scene's own layout() already ran) — only a transient pre-entrance offset is undone.
    /// `fade`/`scale` let a caller skip whichever channel a node's own continuous ambient action (a
    /// breathing pulse, a glow) already drives, so the two animations never fight over the same
    /// property.
    static func popIn(_ node: SKNode?, delay: TimeInterval, distance: CGFloat = 12,
                       fade: Bool = true, scale: Bool = true, completion: (() -> Void)? = nil) {
        guard let node else { return }
        let targetPosition = node.position
        let targetScale = node.xScale
        node.position = CGPoint(x: targetPosition.x, y: targetPosition.y - distance)
        if fade { node.alpha = 0 }
        if scale { node.setScale(targetScale * 0.9) }

        var actions: [SKAction] = [SKAction.move(to: targetPosition, duration: 0.32)]
        if fade { actions.append(SKAction.fadeIn(withDuration: 0.3)) }
        if scale {
            actions.append(SKAction.sequence([
                SKAction.scale(to: targetScale * 1.04, duration: 0.22),
                SKAction.scale(to: targetScale, duration: 0.1)
            ]))
        }
        let sequence = SKAction.sequence([SKAction.wait(forDuration: delay), SKAction.group(actions)])
        if let completion {
            node.run(sequence, completion: completion)
        } else {
            node.run(sequence)
        }
    }

    // MARK: - Idle ambient motion

    /// Slow, subtle idle "breathing" scale loop for an otherwise-static decorative node (icon/badge/
    /// glow) — small amplitude and slow period so it reads as alive, not busy. `phase` staggers the
    /// start so multiple nodes running this don't all pulse in lockstep.
    static func idleBreathe(_ node: SKNode, amplitude: CGFloat = 0.08, period: TimeInterval = 1.6, phase: TimeInterval = 0) {
        let base = node.xScale
        let pulse = SKAction.sequence([
            SKAction.scale(to: base * (1 + amplitude), duration: period),
            SKAction.scale(to: base, duration: period)
        ])
        pulse.timingMode = .easeInEaseOut
        node.run(SKAction.sequence([SKAction.wait(forDuration: phase), SKAction.repeatForever(pulse)]))
    }

    // MARK: - Screen shake

    static func shake(node: SKNode, magnitude: CGFloat, duration: TimeInterval) {
        node.removeAction(forKey: "shake")
        let steps = max(4, Int(duration / 0.03))
        var actions: [SKAction] = []
        for i in 0..<steps {
            let falloff = 1.0 - CGFloat(i) / CGFloat(steps)
            let dx = CGFloat.random(in: -magnitude...magnitude) * falloff
            let dy = CGFloat.random(in: -magnitude...magnitude) * falloff
            actions.append(SKAction.moveBy(x: dx, y: dy, duration: duration / Double(steps)))
        }
        actions.append(SKAction.move(to: .zero, duration: 0.03))
        node.run(SKAction.sequence(actions), withKey: "shake")
    }

    // MARK: - Shared textures

    private static let dotTexture: SKTexture = ProceduralTextures.render(size: CGSize(width: 16, height: 16)) { ctx, size in
        ctx.setFillColor(SKColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(origin: .zero, size: size))
    }
}
