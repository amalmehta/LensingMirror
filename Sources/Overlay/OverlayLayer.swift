import SwiftUI

/// Where each pane sits in the window, as a fraction of it (origin top-left).
struct PaneLayout: Equatable {
    let index: Int
    let spin: Double
    let unitRect: CGRect

    var isSchwarzschild: Bool { spin == 0 }
    var title: String { isSchwarzschild ? "Schwarzschild · no spin" : String(format: "Kerr · spin %.2f", spin) }

    func rect(in size: CGSize) -> CGRect {
        CGRect(x: unitRect.minX * size.width, y: unitRect.minY * size.height,
               width: unitRect.width * size.width, height: unitRect.height * size.height)
    }

    static func layouts(compare: Bool, spin: Double) -> [PaneLayout] {
        compare
            ? [PaneLayout(index: 0, spin: 0, unitRect: CGRect(x: 0, y: 0, width: 0.5, height: 1)),
               PaneLayout(index: 1, spin: spin, unitRect: CGRect(x: 0.5, y: 0, width: 0.5, height: 1))]
            : [PaneLayout(index: 0, spin: spin, unitRect: CGRect(x: 0, y: 0, width: 1, height: 1))]
    }
}

/// Einstein ring and photon sphere drawn over the live picture.
struct OverlayLayer: View {
    let layouts: [PaneLayout]
    let curves: [Int: LensCurves]

    var body: some View {
        Canvas { ctx, size in
            for layout in layouts {
                guard let c = curves[layout.index] else { continue }
                let rect = layout.rect(in: size)
                let ring = Path(LensCurves.path(c.einsteinRing, aspect: c.aspect, in: rect))
                let sphere = Path(LensCurves.path(c.photonSphere, aspect: c.aspect, in: rect))
                let halo = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                ctx.stroke(ring, with: .color(.black.opacity(0.45)), style: halo)
                ctx.stroke(sphere, with: .color(.black.opacity(0.45)), style: halo)
                ctx.stroke(ring, with: .color(Palette.einsteinRing), style: StrokeStyle(lineWidth: 1.8, dash: [7, 5]))
                ctx.stroke(sphere, with: .color(Palette.photonSphere), style: StrokeStyle(lineWidth: 1.8))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Key for the overlay's two curves.
struct OverlayLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row(Palette.einsteinRing, dashed: true, "Einstein ring", "where the point straight behind the hole appears")
            row(Palette.photonSphere, dashed: false, "Photon sphere", "edge of the shadow, where light can orbit")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .environment(\.colorScheme, .dark)
    }

    private func row(_ color: Color, dashed: Bool, _ name: String, _ help: String) -> some View {
        HStack(spacing: 7) {
            Path { p in p.move(to: CGPoint(x: 0, y: 5)); p.addLine(to: CGPoint(x: 22, y: 5)) }
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [5, 3] : []))
                .frame(width: 22, height: 10)
            Text(name).font(.caption.weight(.semibold))
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Draws the overlay onto an exported image (snapshot or GIF frame).
enum OverlayDrawing {
    static func compose(_ image: CGImage, layouts: [PaneLayout], curves: [Int: LensCurves]) -> CGImage {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)   // top-left origin, like the window
        let lineScale = max(1, CGFloat(h) / 720)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        for layout in layouts {
            guard let c = curves[layout.index] else { continue }
            let rect = layout.rect(in: CGSize(width: w, height: h))
            for (points, color, dashed) in [(c.einsteinRing, Palette.exportRing, true), (c.photonSphere, Palette.exportSphere, false)] {
                let path = LensCurves.path(points, aspect: c.aspect, in: rect)
                ctx.setLineDash(phase: 0, lengths: [])
                ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.45)); ctx.setLineWidth(4 * lineScale)
                ctx.addPath(path); ctx.strokePath()
                ctx.setLineDash(phase: 0, lengths: dashed ? [7 * lineScale, 5 * lineScale] : [])
                ctx.setStrokeColor(color); ctx.setLineWidth(1.8 * lineScale)
                ctx.addPath(path); ctx.strokePath()
            }
        }
        return ctx.makeImage() ?? image
    }
}
