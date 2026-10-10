import AppKit
import CoreGraphics
import MetalKit

/// A built-in picture for when there's no camera (or it's switched off): a coloured grid
/// with a target in the middle, which makes the bending easy to read.
enum TestPattern {
    static func image(width: Int = 1280, height: Int = 720) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let W = CGFloat(width), H = CGFloat(height), cell: CGFloat = 40
        // Checkerboard whose hue sweeps left to right and brightness top to bottom.
        for j in 0..<Int(H / cell) + 1 {
            for i in 0..<Int(W / cell) + 1 {
                let hue = CGFloat(i) * cell / W
                let dark = (i + j) % 2 == 0
                let c = NSColor(hue: hue * 0.85, saturation: dark ? 0.75 : 0.45,
                                brightness: dark ? 0.55 : 0.92, alpha: 1)
                ctx.setFillColor(c.cgColor)
                ctx.fill(CGRect(x: CGFloat(i) * cell, y: CGFloat(j) * cell, width: cell, height: cell))
            }
        }
        // Bold grid every four cells.
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(3)
        for x in stride(from: CGFloat(0), through: W, by: cell * 4) { ctx.strokeLineSegments(between: [CGPoint(x: x, y: 0), CGPoint(x: x, y: H)]) }
        for y in stride(from: CGFloat(0), through: H, by: cell * 4) { ctx.strokeLineSegments(between: [CGPoint(x: 0, y: y), CGPoint(x: W, y: y)]) }
        // A target behind the hole: its centre becomes the Einstein ring.
        let c = CGPoint(x: W / 2, y: H / 2)
        for (i, r) in [150, 110, 70, 30].enumerated() {
            ctx.setFillColor((i % 2 == 0 ? NSColor.white : NSColor(calibratedRed: 0.9, green: 0.15, blue: 0.2, alpha: 1)).cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - CGFloat(r), y: c.y - CGFloat(r), width: CGFloat(r * 2), height: CGFloat(r * 2)))
        }
        // Label, so left/right and up/down are obvious.
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 54, weight: .heavy),
                                                    .foregroundColor: NSColor.white,
                                                    .strokeColor: NSColor.black, .strokeWidth: -3.0]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let text = NSAttributedString(string: "LENSING MIRROR", attributes: attrs)
        text.draw(at: CGPoint(x: (W - text.size().width) / 2, y: H - 110))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    static func frame(device: MTLDevice) -> SourceFrame? {
        guard let image = image(),
              let texture = try? MTKTextureLoader(device: device).newTexture(cgImage: image, options: [
                  .SRGB: false, .textureUsage: MTLTextureUsage.shaderRead.rawValue, .textureStorageMode: MTLStorageMode.private.rawValue])
        else { return nil }
        return SourceFrame(texture: texture, keepAlive: nil)
    }
}
