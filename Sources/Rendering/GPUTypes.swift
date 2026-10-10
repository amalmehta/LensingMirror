import simd

/// Mirrors `MapParams` in LensShaders.msl (160 bytes).
struct MapParams {
    var camPos: SIMD4<Float>
    var u: SIMD4<Float>
    var eFwd: SIMD4<Float>
    var eRight: SIMD4<Float>
    var eUp: SIMD4<Float>
    var camL: SIMD4<Float>
    var spin: Float, horizon: Float, plane: Float, tanHalfFov: Float
    var aspect: Float, stepK: Float, rEscape: Float, sourceScale: Float
    var maxSteps: Int32, width: Int32, height: Int32, pad: Int32 = 0
    var rCapture: Float
    var rowOffset: Int32 = 0
    var pad1: Float = 0, pad2: Float = 0

    init(_ s: LensSetup, aspect: Double, width: Int, height: Int) {
        let frame = CameraFrame(spin: s.spin, distance: s.distance)
        func f4(_ v: SIMD4<Double>) -> SIMD4<Float> { SIMD4<Float>(v) }
        camPos = SIMD4<Float>(SIMD3<Float>(frame.position), 0)
        u = f4(frame.u); eFwd = f4(frame.forward); eRight = f4(frame.right); eUp = f4(frame.up)
        camL = SIMD4<Float>(SIMD3<Float>(frame.l), Float(frame.f))
        spin = Float(s.spin); horizon = Float(s.horizon); plane = Float(s.plane)
        tanHalfFov = Float(s.tanHalfFov); self.aspect = Float(aspect); stepK = Float(s.stepK)
        rEscape = Float(s.escapeRadius); sourceScale = Float(s.sourceScale)
        maxSteps = Int32(s.maxSteps); self.width = Int32(width); self.height = Int32(height)
        rCapture = Float(s.captureRadius)
    }
}

/// Mirrors `CompositeParams` in LensShaders.msl (48 bytes).
struct CompositeParams {
    var origin: SIMD2<Float>
    var size: SIMD2<Float>
    var mapSize: SIMD2<Float>
    var camAspect: Float
    var paneAspect: Float
    var mirror: Float
    var pad0: Float = 0
    var pad1: SIMD2<Float> = .zero
}
