import SpriteKit
import UIKit

/// Shared helper for rendering procedural (code-drawn) art into cached SKTextures.
/// Every visual in NightFeed is generated this way — no image assets are bundled.
enum ProceduralTextures {
    static func render(size: CGSize, opaque: Bool = false, draw: (CGContext, CGSize) -> Void) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = opaque
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            draw(ctx.cgContext, size)
        }
        return SKTexture(image: image)
    }

    static func radialGlow(color: UIColor, radius: CGFloat) -> SKTexture {
        let size = CGSize(width: radius * 2, height: radius * 2)
        return render(size: size) { ctx, size in
            let colors = [color.withAlphaComponent(0.9).cgColor, color.withAlphaComponent(0.0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        }
    }
}
