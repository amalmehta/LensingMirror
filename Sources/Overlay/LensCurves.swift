import CoreGraphics
import simd

/*
 * The overlay's two curves, read straight off a lens map so they follow the exact
 * (spinning or not) geometry the picture uses:
 *   - Photon sphere: the edge of the shadow, where rays stop falling in. Light seen
 *     there has skimmed the unstable photon orbit.
 *   - Einstein ring: where the point straight behind the hole (the centre of the
 *     mirror) appears. Walking outward along each direction, the source position
 *     flips from the far side to the near side; the outermost flip is the primary ring.
 * Points are in pane units: x in [−aspect, aspect], y in [−1, 1], y up, hole at 0.
 */
struct LensCurves: Sendable, Equatable {
    var photonSphere: [SIMD2<Float>?]
    var einsteinRing: [SIMD2<Float>?]
    var aspect: Float

    static let directions = 240

    /// `texels` is the map's RGBA32Float data, row 0 at the top.
    static func extract(texels: UnsafeBufferPointer<Float>, width: Int, height: Int) -> LensCurves {
        let aspect = Float(width) / Float(height)
        func texel(_ ix: Int, _ iy: Int) -> SIMD4<Float> {
            let x = min(max(ix, 0), width - 1), y = min(max(iy, 0), height - 1)
            let i = (y * width + x) * 4
            return SIMD4(texels[i], texels[i + 1], texels[i + 2], texels[i + 3])
        }
        /// (kind, source position) at pane point p; kind 0 captured, 1 mirror, 2 missed.
        func sample(_ p: SIMD2<Float>) -> (Int, SIMD2<Float>) {
            let px = (p.x / aspect + 1) / 2 * Float(width) - 0.5
            let py = (1 - p.y) / 2 * Float(height) - 0.5
            let x0 = Int(px.rounded(.down)), y0 = Int(py.rounded(.down))
            let fx = px - Float(x0), fy = py - Float(y0)
            let t00 = texel(x0, y0), t10 = texel(x0 + 1, y0), t01 = texel(x0, y0 + 1), t11 = texel(x0 + 1, y0 + 1)
            let nearest = texel(Int(px.rounded()), Int(py.rounded()))
            let kind = Int(nearest.z.rounded())
            guard [t00, t10, t01, t11].allSatisfy({ $0.z == 1 }) else { return (kind, SIMD2(nearest.x, nearest.y)) }
            let top = simd_mix(SIMD2(t00.x, t00.y), SIMD2(t10.x, t10.y), SIMD2(repeating: fx))
            let bottom = simd_mix(SIMD2(t01.x, t01.y), SIMD2(t11.x, t11.y), SIMD2(repeating: fx))
            return (1, simd_mix(top, bottom, SIMD2(repeating: fy)))
        }

        var sphere = [SIMD2<Float>?](repeating: nil, count: directions)
        var ring = [SIMD2<Float>?](repeating: nil, count: directions)
        guard sample(.zero).0 == 0 else { return LensCurves(photonSphere: sphere, einsteinRing: ring, aspect: aspect) }
        let step: Float = 1 / Float(height)          // half a texel
        for k in 0..<directions {
            let theta = Float(k) / Float(directions) * 2 * .pi
            let dir = SIMD2(cos(theta), sin(theta))
            let reach = min(abs(dir.x) > 1e-6 ? aspect / abs(dir.x) : .infinity,
                            abs(dir.y) > 1e-6 ? 1 / abs(dir.y) : .infinity) - step
            var rho: Float = 0
            while rho < reach && sample(dir * rho).0 == 0 { rho += step }
            guard rho < reach else { continue }        // the shadow fills this direction
            sphere[k] = dir * (rho - step / 2)
            var previous: Float? = nil
            var r = rho
            while r < reach {
                let (kind, s) = sample(dir * r)
                if kind == 1 {
                    let d = simd_dot(s, dir)
                    if let prev = previous, prev < 0, d >= 0 {
                        ring[k] = dir * (r - step * d / (d - prev))   // linear between the two samples
                    }
                    previous = d
                } else {
                    previous = nil
                }
                r += step
            }
        }
        return LensCurves(photonSphere: sphere, einsteinRing: ring, aspect: aspect)
    }

    /// Mean distance from the hole of the points found (for tests and readouts).
    static func meanRadius(_ points: [SIMD2<Float>?]) -> Float? {
        let found = points.compactMap { $0 }
        guard !found.isEmpty else { return nil }
        return found.map(simd_length).reduce(0, +) / Float(found.count)
    }

    /// A path through the points found, in a rect whose origin is top-left. Gaps split it.
    static func path(_ points: [SIMD2<Float>?], aspect: Float, in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        func place(_ p: SIMD2<Float>) -> CGPoint {
            CGPoint(x: rect.minX + CGFloat((p.x / aspect + 1) / 2) * rect.width,
                    y: rect.minY + CGFloat((1 - p.y) / 2) * rect.height)
        }
        var open = false
        for p in points {
            guard let p else { open = false; continue }
            if open { path.addLine(to: place(p)) } else { path.move(to: place(p)); open = true }
        }
        if points.allSatisfy({ $0 != nil }), points.count > 2 { path.closeSubpath() }
        return path
    }
}
