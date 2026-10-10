import XCTest
import simd
@testable import LensingMirror

/// The CPU physics: closed-form radii, the camera frame, and the ray tracer.
final class PhysicsTests: XCTestCase {
    func testClosedFormRadii() {
        XCTAssertEqual(Kerr.horizon(0), 2, accuracy: 1e-12)
        XCTAssertEqual(Kerr.photonOrbit(0), 3, accuracy: 1e-12)
        XCTAssertEqual(Kerr.criticalImpact(0), 3 * 3.0.squareRoot(), accuracy: 1e-12)
        // Near maximal spin the prograde photon orbit and horizon both approach M.
        XCTAssertEqual(Kerr.photonOrbit(0.999), 1.0, accuracy: 0.1)
        XCTAssertEqual(Kerr.photonOrbit(0.999, prograde: false), 4.0, accuracy: 0.01)
        XCTAssertLessThan(Kerr.criticalImpact(0.9), Kerr.criticalImpact(0.9, prograde: false))
    }

    func testCameraFrameIsOrthonormal() {
        for a in [0.0, 0.5, 0.99] {
            let c = CameraFrame(spin: a, distance: 20)
            func g(_ A: SIMD4<Double>, _ B: SIMD4<Double>) -> Double {
                let lA = A.w + simd_dot(c.l, A.xyz), lB = B.w + simd_dot(c.l, B.xyz)
                return -A.w * B.w + simd_dot(A.xyz, B.xyz) + c.f * lA * lB
            }
            let basis = [c.forward, c.right, c.up]
            XCTAssertEqual(g(c.u, c.u), -1, accuracy: 1e-12)
            for (i, e) in basis.enumerated() {
                XCTAssertEqual(g(e, c.u), 0, accuracy: 1e-12)
                for (j, f) in basis.enumerated() { XCTAssertEqual(g(e, f), i == j ? 1 : 0, accuracy: 1e-12) }
            }
        }
    }

    func testInitialMomentumIsNull() {
        let c = CameraFrame(spin: 0.9, distance: 15)
        for (tx, ty) in [(0.0, 0.0), (0.3, -0.2), (-0.5, 0.4)] {
            let p = c.initialMomentum(tx: tx, ty: ty)
            XCTAssertEqual(Kerr.hamiltonian(c.position, p, a: 0.9), 0, accuracy: 1e-12)
        }
    }

    func testHamiltonianStaysNullAlongARay() {
        let a = 0.9, c = CameraFrame(spin: a, distance: 30)
        var q = c.position, p = c.initialMomentum(tx: 0.25, ty: 0.1)
        for _ in 0..<400 {
            let r = Kerr.radius(q, a: a)
            let k1 = Kerr.deriv(q, p, a: a)
            let h = -0.01 * r / max(simd_length(k1.v), 1)
            (q, p) = Kerr.rk4(q, p, h: h, a: a, k1: k1)
        }
        XCTAssertEqual(Kerr.hamiltonian(q, p, a: a), 0, accuracy: 1e-6)
    }

    /// Bisect the screen height at which rays stop being captured.
    private func shadowEdge(_ s: LensSetup, sign: Double = 1, horizontal: Bool = false) -> Double {
        let frame = CameraFrame(spin: s.spin, distance: s.distance)
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            let fate = horizontal ? LensTracer.trace(s, frame: frame, x: sign * mid, y: 0)
                                  : LensTracer.trace(s, frame: frame, x: 0, y: sign * mid)
            if fate == .captured { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    func testSchwarzschildShadowMatchesClosedForm() {
        let s = LensSetup(spin: 0, distance: 30, plane: 30, tanHalfFov: tan(20 * Double.pi / 180), stepK: 0.0125)
        let expected = tan(Schwarzschild.shadowAngle(distance: 30)) / s.tanHalfFov
        XCTAssertEqual(shadowEdge(s), expected, accuracy: expected * 0.003)
    }

    func testSpinShiftsTheShadowSideways() {
        let s = LensSetup(spin: 0.95, distance: 30, plane: 30, tanHalfFov: tan(20 * Double.pi / 180))
        let right = shadowEdge(s, sign: 1, horizontal: true), left = shadowEdge(s, sign: -1, horizontal: true)
        XCTAssertGreaterThan(abs(right - left), 0.05 * (right + left) / 2, "a spinning hole's shadow is lopsided")
        // Vertical extent is symmetric about the equator.
        XCTAssertEqual(shadowEdge(s, sign: 1), shadowEdge(s, sign: -1), accuracy: 1e-4)
    }

    /// Thin-lens deflection to second order: α(b) = 4/b + (15π/4)/b².
    private func deflection(_ b: Double) -> Double { 4 / b + 15 * .pi / 4 / (b * b) }

    func testEinsteinRingMatchesThinLens() {
        let D = 400.0, S = 400.0
        let s = LensSetup(spin: 0, distance: D, plane: S, tanHalfFov: tan(5 * Double.pi / 180))
        let frame = CameraFrame(spin: 0, distance: D)
        var lo = shadowEdge(s), hi = 1.0
        for _ in 0..<40 {   // the source's y changes sign at the ring
            let mid = (lo + hi) / 2
            if case .mirror(let p) = LensTracer.trace(s, frame: frame, x: 0, y: mid), p.y > 0 { hi = mid } else { lo = mid }
        }
        let traced = atan((lo + hi) / 2 * s.tanHalfFov)
        // θ_E = S/(D+S) · α(D θ_E), solved by damped iteration (the plain one oscillates).
        var expected = Schwarzschild.einsteinAngleWeak(distance: D, plane: S)
        for _ in 0..<60 { expected = (expected * S / (D + S) * deflection(D * expected)).squareRoot() }
        XCTAssertEqual(traced, expected, accuracy: expected * 0.01)
        // First order alone is ~5% small at this distance; the tracer includes the rest.
        XCTAssertGreaterThan(traced, Schwarzschild.einsteinAngleWeak(distance: D, plane: S))
    }

    func testImagesFollowTheLensEquation() {
        let D = 1000.0, S = 1000.0
        let s = LensSetup(spin: 0, distance: D, plane: S, tanHalfFov: tan(5 * Double.pi / 180))
        let frame = CameraFrame(spin: 0, distance: D)
        for y in [0.5, 0.8, 1.0] {
            guard case .mirror(let p) = LensTracer.trace(s, frame: frame, x: 0, y: y) else { return XCTFail() }
            let theta = atan(y * s.tanHalfFov)
            let beta = theta - S / (D + S) * deflection(D * theta)
            XCTAssertEqual(atan(p.y * s.tanHalfFov), beta, accuracy: theta * 0.01, "y = \(y)")
            XCTAssertEqual(p.x, 0, accuracy: 1e-6)
        }
    }
}
