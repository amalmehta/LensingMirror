import Foundation
import simd

/*
 * Black hole maths in geometric units G = c = M = 1 (distances in units of the mass M).
 * A Swift port of black_hole_simulator's physics.js (Kerr–Schild section), used to
 * set up the GPU camera, by the tests, and as the reference the Metal shader is checked against.
 *
 * Light rays in Kerr–Schild Cartesian coordinates (x, y, z), spin along +z:
 *   g^{μν} = η^{μν} − f l^μ l^ν,   f = 2 r³ / (r⁴ + a² z²),
 *   l_μ = (1, (r x + a y)/(r² + a²), (r y − a x)/(r² + a²), z / r),
 * with r the Boyer–Lindquist radius:  r⁴ − (ρ² − a²) r² − a² z² = 0.
 * Hamilton's equations for H = ½ g^{μν} p_μ p_ν with p_t = −1:
 *   dx/dλ = p − f (1 + l·p) l,    dp/dλ = ½ ∇[ f (1 + l·p)² ]   (p held fixed).
 * a = 0 is the Schwarzschild hole (in ingoing Eddington–Finkelstein form).
 */
typealias Vec3 = SIMD3<Double>

extension SIMD4 {
    var xyz: SIMD3<Scalar> { SIMD3(x, y, z) }
}

enum Kerr {
    /// Outer event horizon r₊ = 1 + √(1 − a²).
    static func horizon(_ a: Double) -> Double { 1 + (1 - a * a).squareRoot() }

    /// Radius of the circular photon orbit in the equatorial plane.
    static func photonOrbit(_ a: Double, prograde: Bool = true) -> Double {
        let s: Double = prograde ? -1 : 1
        return 2 * (1 + cos(2.0 / 3.0 * acos(s * a)))
    }

    /// Critical impact parameter for equatorial light: rays aimed inside it fall in.
    static func criticalImpact(_ a: Double, prograde: Bool = true) -> Double {
        prograde ? -a + 6 * cos(acos(-a) / 3) : a + 6 * cos(acos(a) / 3)
    }

    static func radius(_ q: SIMD3<Double>, a: Double) -> Double {
        let b = simd_length_squared(q) - a * a
        return (0.5 * (b + (b * b + 4 * a * a * q.z * q.z).squareRoot())).squareRoot()
    }

    static func fields(_ q: SIMD3<Double>, a: Double) -> (r: Double, f: Double, l: SIMD3<Double>) {
        let r = radius(q, a: a)
        let r2 = r * r, den = r2 + a * a, Q = r2 * r2 + a * a * q.z * q.z
        let l = SIMD3((r * q.x + a * q.y) / den, (r * q.y - a * q.x) / den, q.z / r)
        return (r, 2 * r2 * r / Q, l)
    }

    /// Right-hand side of Hamilton's equations: (dx/dλ, dp/dλ).
    static func deriv(_ q: SIMD3<Double>, _ p: SIMD3<Double>, a: Double) -> (v: SIMD3<Double>, dp: SIMD3<Double>) {
        let (r, f, l) = fields(q, a: a)
        let a2 = a * a, r2 = r * r, den = r2 + a2, Q = r2 * r2 + a2 * q.z * q.z
        let c: Double = 1 + simd_dot(l, p)
        let v: Vec3 = p - (f * c) * l
        let dr: Vec3 = (r / Q) * Vec3(r2 * q.x, r2 * q.y, q.z * den)
        let dQ: Vec3 = (4 * r2 * r) * dr + Vec3(0, 0, 2 * a2 * q.z)
        let df: Vec3 = (2 / (Q * Q)) * ((3 * r2 * Q) * dr - (r2 * r) * dQ)
        let A = q.x * p.x + q.y * p.y, B = q.y * p.x - q.x * p.y, N = r * A + a * B
        let t1: Vec3 = (A * dr + r * Vec3(p.x, p.y, 0) + a * Vec3(-p.y, p.x, 0)) / den
        let t2: Vec3 = (N * 2 * r / (den * den)) * dr
        let t3: Vec3 = p.z * (Vec3(0, 0, 1 / r) - (q.z / r2) * dr)
        let dS: Vec3 = t1 - t2 + t3
        return (v, 0.5 * ((c * c) * df + (2 * f * c) * dS))
    }

    /// One classic Runge–Kutta step of size h (negative traces backwards in time).
    static func rk4(_ q: Vec3, _ p: Vec3, h: Double, a: Double,
                    k1: (v: Vec3, dp: Vec3)) -> (q: Vec3, p: Vec3) {
        let hh = 0.5 * h
        let k2 = deriv(q + hh * k1.v, p + hh * k1.dp, a: a)
        let k3 = deriv(q + hh * k2.v, p + hh * k2.dp, a: a)
        let k4 = deriv(q + h * k3.v, p + h * k3.dp, a: a)
        let sv: Vec3 = k1.v + 2 * k2.v + 2 * k3.v + k4.v
        let sp: Vec3 = k1.dp + 2 * k2.dp + 2 * k3.dp + k4.dp
        return (q + (h / 6) * sv, p + (h / 6) * sp)
    }

    /// H = ½(−1 + |p|² − f (1 + l·p)²); zero for light.
    static func hamiltonian(_ q: SIMD3<Double>, _ p: SIMD3<Double>, a: Double) -> Double {
        let (_, f, l) = fields(q, a: a)
        let c = 1 + simd_dot(l, p)
        return 0.5 * (-1 + simd_length_squared(p) - f * c * c)
    }
}

/// Closed-form checks for the non-spinning hole, used by the tests and docs.
enum Schwarzschild {
    /// Angular radius of the shadow seen by a static observer at radius D.
    static func shadowAngle(distance D: Double) -> Double {
        asin(3 * 3.0.squareRoot() / D * (1 - 2 / D).squareRoot())
    }

    /// Weak-field Einstein ring angle for a source plane S behind the hole, observer D in front.
    static func einsteinAngleWeak(distance D: Double, plane S: Double) -> Double {
        (4 * S / (D * (D + S))).squareRoot()
    }
}

/*
 * The camera: a static observer at (−D, 0, 0) looking at the hole along +x, up along
 * the spin axis (+z), right along +y. Its 4-velocity u and an orthonormal spatial
 * triad are built with Gram–Schmidt in the full metric, so pixel angles are the
 * angles that observer would really measure. 4-vectors are (x, y, z, t).
 */
struct CameraFrame {
    let position: SIMD3<Double>
    let f: Double
    let l: SIMD3<Double>
    let u: SIMD4<Double>
    let forward: SIMD4<Double>
    let right: SIMD4<Double>
    let up: SIMD4<Double>

    init(spin a: Double, distance D: Double) {
        let q = SIMD3<Double>(-D, 0, 0)
        let (_, f, l) = Kerr.fields(q, a: a)
        // g(A, B) = η(A, B) + f (l·A)(l·B), with l_t = 1.
        func inner(_ A: SIMD4<Double>, _ B: SIMD4<Double>) -> Double {
            let lA = A.w + simd_dot(l, A.xyz), lB = B.w + simd_dot(l, B.xyz)
            return -A.w * B.w + simd_dot(A.xyz, B.xyz) + f * lA * lB
        }
        let u = SIMD4<Double>(0, 0, 0, 1 / (1 - f).squareRoot())
        func orthonormal(_ e: SIMD4<Double>, _ basis: [SIMD4<Double>]) -> SIMD4<Double> {
            var v = e + inner(u, e) * u
            for b in basis { v -= inner(v, b) * b }
            return v / inner(v, v).squareRoot()
        }
        let forward = orthonormal([1, 0, 0, 0], [])
        let up = orthonormal([0, 0, 1, 0], [forward])
        let right = orthonormal([0, 1, 0, 0], [forward, up])
        self.position = q; self.f = f; self.l = l
        self.u = u; self.forward = forward; self.right = right; self.up = up
    }

    /// Covariant spatial momentum (p_t = −1) of the photon that reaches the camera
    /// from image-plane direction (tx, ty) = (tan of angle right, tan of angle up).
    func initialMomentum(tx: Double, ty: Double) -> SIMD3<Double> {
        let dir: SIMD4<Double> = forward + tx * right + ty * up
        let n: SIMD4<Double> = dir / (1 + tx * tx + ty * ty).squareRoot()
        let pu: SIMD4<Double> = u - n            // arrives moving along −n
        let lp: Double = pu.w + simd_dot(l, pu.xyz)
        let pt: Double = -pu.w + f * lp
        let ps: Vec3 = pu.xyz + (f * lp) * l
        return ps / -pt
    }
}

/// Everything that shapes the lens map, in units of M.
struct LensSetup: Equatable {
    var spin: Double
    var distance: Double      // observer to hole, D
    var plane: Double         // hole to the mirror (webcam) plane behind it, S
    var tanHalfFov: Double    // vertical
    var stepK: Double = 0.05
    var maxSteps: Int = 4000

    /// The quick version traced every frame while a slider moves: a coarser step and a
    /// tighter step cap. Only the thin rings at the shadow's edge differ visibly.
    var preview: LensSetup {
        var s = self
        s.stepK = max(stepK, 0.08)
        s.maxSteps = 500
        return s
    }

    var horizon: Double { Kerr.horizon(spin) }
    /// Light from outside that gets this deep while still heading in can't come back out
    /// (no photon orbit lies inside the prograde equatorial one), so tracing can stop.
    var captureRadius: Double { Kerr.photonOrbit(spin) * 0.98 }
    var escapeRadius: Double { max(distance, plane) * 1.2 + 10 }
    /// Plane coordinates → "unlensed screen" units: the point an undeflected ray from
    /// screen position (x, y) would hit maps back to (x, y).
    var sourceScale: Double { 1 / ((distance + plane) * tanHalfFov) }
}

enum RayFate: Equatable {
    case captured
    case mirror(SIMD2<Double>)   // hit the mirror plane, in unlensed screen units
    case missed                  // escaped without hitting the plane
}

/// CPU twin of the Metal `buildLensMap` kernel, line for line.
enum LensTracer {
    /// Trace the ray seen at screen position (x, y): y in [−1, 1] bottom to top, x scaled by aspect.
    static func trace(_ s: LensSetup, frame: CameraFrame, x: Double, y: Double) -> RayFate {
        let a = s.spin, rh = s.horizon, S = s.plane, rEsc = s.escapeRadius, rCap = s.captureRadius
        var q = frame.position
        var P = frame.initialMomentum(tx: x * s.tanHalfFov, ty: y * s.tanHalfFov)
        func hit(_ h: SIMD3<Double>) -> RayFate { .mirror(SIMD2(h.y, h.z) * s.sourceScale) }
        for _ in 0..<s.maxSteps {
            let k1 = Kerr.deriv(q, P, a: a)
            let r = Kerr.radius(q, a: a)
            // Traced backwards, a ray that came from the horizon creeps toward r₊
            // while its momentum grows without bound in these coordinates.
            if r < rh + 0.02 || simd_length_squared(P) > 1e4 { return .captured }
            if r < rCap && simd_dot(q, -k1.v) < 0 { return .captured }
            if r > rEsc && simd_dot(q, -k1.v) > 0 {
                let t = -k1.v                    // direction the trace moves
                if t.x > 0 && q.x < S { return hit(q + t * ((S - q.x) / t.x)) }
                return .missed
            }
            // Step length in space, not in λ (same rule as the shader). It shrinks only within
            // half an M of the horizon, so rays skimming the photon orbit aren't slowed down.
            let h = -s.stepK * r * min(max((r - rh) * 2, 0.05), 1) / max(simd_length(k1.v), 1)
            let next = Kerr.rk4(q, P, h: h, a: a, k1: k1)
            let nq = next.q
            P = next.p
            if (q.x - S) * (nq.x - S) < 0 { return hit(q + ((S - q.x) / (nq.x - q.x)) * (nq - q)) }
            q = nq
        }
        return .captured
    }
}
