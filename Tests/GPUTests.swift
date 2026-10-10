import ImageIO
import Metal
import XCTest
import simd
@testable import LensingMirror

/// The Metal side: the shader agrees with the CPU tracer, the overlay finds the right
/// curves, frames are fast enough, and exports are valid files.
final class GPUTests: XCTestCase {
    static var engine: LensEngine!

    override class func setUp() {
        engine = try! LensEngine(device: MTLCreateSystemDefaultDevice()!)
    }

    private var engine: LensEngine { Self.engine }

    private func buildMap(_ s: LensSetup, _ w: Int, _ h: Int) -> (LensMap, [Float]) {
        let cb = engine.queue.makeCommandBuffer()!
        let map = engine.makeMap(MapKey(setup: s, width: w, height: h), reusing: nil, in: cb)!
        let buffer = engine.readback(map, in: cb)!
        cb.commit(); cb.waitUntilCompleted()
        XCTAssertNil(cb.error)
        let ptr = buffer.contents().bindMemory(to: Float.self, capacity: w * h * 4)
        return (map, Array(UnsafeBufferPointer(start: ptr, count: w * h * 4)))
    }

    private func setup(spin: Double, D: Double = 48, S: Double = 40) -> LensSetup {
        LensSetup(spin: spin, distance: D, plane: S, tanHalfFov: tan(20 * Double.pi / 180))
    }

    func testStructLayoutsMatchTheShader() {
        XCTAssertEqual(MemoryLayout<MapParams>.stride, 160)
        XCTAssertEqual(MemoryLayout<CompositeParams>.stride, 48)
    }

    func testShaderMatchesCPUTracer() {
        for spin in [0.0, 0.9] {
            let s = setup(spin: spin), w = 96, h = 64
            let (_, texels) = buildMap(s, w, h)
            let frame = CameraFrame(spin: spin, distance: s.distance)
            var agree = 0, compared = 0
            for iy in stride(from: 1, to: h, by: 5) {
                for ix in stride(from: 2, to: w, by: 7) {
                    let x = ((Double(ix) + 0.5) / Double(w) * 2 - 1) * Double(w) / Double(h)
                    let y = 1 - (Double(iy) + 0.5) / Double(h) * 2
                    let i = (iy * w + ix) * 4
                    let gpuKind = Int(texels[i + 2])
                    compared += 1
                    switch LensTracer.trace(s, frame: frame, x: x, y: y) {
                    case .captured: if gpuKind == 0 { agree += 1 }
                    case .missed: if gpuKind == 2 { agree += 1 }
                    case .mirror(let p):
                        if gpuKind == 1, abs(Double(texels[i]) - p.x) < 0.02, abs(Double(texels[i + 1]) - p.y) < 0.02 { agree += 1 }
                    }
                }
            }
            // Float vs double may flip a ray that grazes the shadow edge; nothing else.
            XCTAssertGreaterThanOrEqual(Double(agree) / Double(compared), 0.98, "spin \(spin): \(agree)/\(compared)")
        }
    }

    func testOverlayFindsSchwarzschildShadowAndRing() throws {
        let s = setup(spin: 0, D: 30, S: 30), w = 480, h = 320
        let (_, texels) = buildMap(s, w, h)
        let curves = texels.withUnsafeBufferPointer { LensCurves.extract(texels: $0, width: w, height: h) }
        let shadow = try XCTUnwrap(LensCurves.meanRadius(curves.photonSphere))
        let expectedShadow = tan(Schwarzschild.shadowAngle(distance: 30)) / s.tanHalfFov
        XCTAssertEqual(Double(shadow), expectedShadow, accuracy: 2.0 / Double(h) * 2)   // within ~2 texels

        // Ring: bisect with the CPU tracer for where the source flips sides.
        let frame = CameraFrame(spin: 0, distance: 30)
        var lo = expectedShadow, hi = 1.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if case .mirror(let p) = LensTracer.trace(s, frame: frame, x: 0, y: mid), p.y > 0 { hi = mid } else { lo = mid }
        }
        let ring = try XCTUnwrap(LensCurves.meanRadius(curves.einsteinRing))
        XCTAssertEqual(Double(ring), (lo + hi) / 2, accuracy: 2.0 / Double(h) * 2)
        XCTAssertEqual(curves.einsteinRing.compactMap { $0 }.count, LensCurves.directions, "ring is closed")
        // Both are circles: every point at the same radius.
        for p in curves.einsteinRing.compactMap({ $0 }) { XCTAssertEqual(simd_length(p), ring, accuracy: 0.02) }
    }

    func testKerrShadowIsShiftedAndFlattened() throws {
        let w = 480, h = 320
        let (_, texels) = buildMap(setup(spin: 0.95, D: 30, S: 30), w, h)
        let curves = texels.withUnsafeBufferPointer { LensCurves.extract(texels: $0, width: w, height: h) }
        let pts = curves.photonSphere.compactMap { $0 }
        XCTAssertEqual(pts.count, LensCurves.directions)
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let centreX = (xs.max()! + xs.min()!) / 2, centreY = (ys.max()! + ys.min()!) / 2
        XCTAssertGreaterThan(abs(centreX), 0.01, "shadow shifts sideways with spin")
        XCTAssertEqual(centreY, 0, accuracy: 0.01, "but not up or down")
    }

    /// Steady state is a lookup per pixel; it has to fit in a 60 fps frame with room to spare.
    func testCompositeFitsInAFrame() {
        let (map, _) = buildMap(setup(spin: 0.7), 1180, 760)
        let source = TestPattern.frame(device: engine.device)!
        let w = 2360, h = 1520     // a Retina window
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: engine.colorFormat, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget]; d.storageMode = .private
        let target = engine.device.makeTexture(descriptor: d)!
        var times: [Double] = []
        for _ in 0..<10 {
            let cb = engine.queue.makeCommandBuffer()!
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            let enc = cb.makeRenderCommandEncoder(descriptor: pass)!
            engine.encodeComposite(enc, panes: [PaneDraw(map: map, rect: CGRect(x: 0, y: 0, width: w, height: h))],
                                   source: source, mirror: true)
            enc.endEncoding()
            cb.commit(); cb.waitUntilCompleted()
            times.append(cb.gpuEndTime - cb.gpuStartTime)
        }
        let median = times.sorted()[times.count / 2]
        print("composite \(w)×\(h): \(String(format: "%.2f", median * 1000)) ms")
        XCTAssertLessThan(median, 1.0 / 60 / 2)
    }

    private func gpuMilliseconds(_ encode: (MTLCommandBuffer) -> Void) -> Double {
        var times: [Double] = []
        for _ in 0..<3 {
            let cb = engine.queue.makeCommandBuffer()!
            encode(cb)
            cb.commit(); cb.waitUntilCompleted()
            times.append((cb.gpuEndTime - cb.gpuStartTime) * 1000)
        }
        return times.sorted()[1]
    }

    /// Previews (while a slider moves) are traced every frame; full maps a band at a time.
    func testMapBuildTimes() {
        for spin in [0.0, 0.7, 0.99] {
            let preview = gpuMilliseconds { _ = engine.makeMap(MapKey(setup: setup(spin: spin).preview, width: 354, height: 228), reusing: nil, in: $0) }
            let full = gpuMilliseconds { _ = engine.makeMap(MapKey(setup: setup(spin: spin), width: 1180, height: 760), reusing: nil, in: $0) }
            print(String(format: "spin %.2f  preview 354×228: %.1f ms   full 1180×760: %.0f ms (%.2f ms per row)",
                         spin, preview, full, full / 760))
            XCTAssertLessThan(preview, 1000.0 / 30, "slider drags stay interactive")
            XCTAssertLessThan(full / 760, 9, "at least one row fits in a frame's budget")
        }
    }

    func testSnapshotAndGIFExport() throws {
        let (map, _) = buildMap(setup(spin: 0.7), 160, 100)
        let source = TestPattern.frame(device: engine.device)!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var frames: [CGImage] = []
        for _ in 0..<4 {
            let cb = engine.queue.makeCommandBuffer()!
            let buffer = engine.encodeOffscreen(width: 320, height: 200, panes: [PaneDraw(map: map, rect: CGRect(x: 0, y: 0, width: 320, height: 200))],
                                                source: source, mirror: false, in: cb)!
            cb.commit(); cb.waitUntilCompleted()
            frames.append(try XCTUnwrap(LensEngine.image(from: buffer, width: 320, height: 200)))
        }
        let png = try Exporter.url(in: dir.path, ext: "png")
        try Exporter.writePNG(frames[0], to: png)
        let gif = dir.appendingPathComponent("loop.gif")
        try Exporter.writeGIF(frames, fps: 15, to: gif)
        let pngSource = try XCTUnwrap(CGImageSourceCreateWithURL(png as CFURL, nil))
        XCTAssertEqual(CGImageSourceCreateImageAtIndex(pngSource, 0, nil)?.width, 320)
        let gifSource = try XCTUnwrap(CGImageSourceCreateWithURL(gif as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(gifSource), 4)
        // The centre pixel is inside the shadow: black.
        let px = try XCTUnwrap(frames[0].dataProvider?.data as Data?)
        let i = (100 * 320 + 160) * 4
        XCTAssertEqual(px[i] , 0); XCTAssertEqual(px[i + 1], 0); XCTAssertEqual(px[i + 2], 0)
    }
}

final class SupportTests: XCTestCase {
    func testFileNamesReadLikeScreenshots() {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 9; c.hour = 20; c.minute = 31; c.second = 5
        let date = Calendar.current.date(from: c)!
        XCTAssertEqual(Exporter.fileName("png", date: date), "Lensing Mirror 2026-10-09 at 20.31.05.png")
    }

    func testGIFCaptureCollectsFramesInOrder() {
        let gif = GIFCapture(seconds: 1, fps: 4, width: 8, height: 8)
        XCTAssertEqual(gif.frameCount, 4)
        var claimed: [Int] = []
        var t = 0.0
        while claimed.count < 4 { if let i = gif.claimFrame(at: t) { claimed.append(i) }; t += 1.0 / 60 }
        XCTAssertEqual(claimed, [0, 1, 2, 3])
        XCTAssertEqual(t, 0.75, accuracy: 0.05, "one frame every quarter second")
        XCTAssertNil(gif.claimFrame(at: t + 10))
    }

    func testFeedbackIsAppendedLocally() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/Feedback.jsonl")
        try FeedbackStore.append(.idea, "first", to: url)
        try FeedbackStore.append(.bug, "second\nline", to: url)
        XCTAssertEqual(FeedbackStore.count(at: url), 2)
    }

    func testCurveExtractionOnASyntheticMap() {
        // A disc of radius 0.3 is captured; outside, the source is the screen point scaled
        // by (1 − 0.25/ρ²), which flips sign at ρ = 0.5: a ring of radius 0.5.
        let w = 300, h = 200
        var texels = [Float](repeating: 0, count: w * h * 4)
        for iy in 0..<h {
            for ix in 0..<w {
                let x = (Float(ix) + 0.5) / Float(w) * 2 * 1.5 - 1.5, y = 1 - (Float(iy) + 0.5) / Float(h) * 2
                let rho2 = x * x + y * y, i = (iy * w + ix) * 4
                if rho2 < 0.09 { continue }
                let k = 1 - 0.25 / rho2
                texels[i] = x * k; texels[i + 1] = y * k; texels[i + 2] = 1
            }
        }
        let c = texels.withUnsafeBufferPointer { LensCurves.extract(texels: $0, width: w, height: h) }
        XCTAssertEqual(LensCurves.meanRadius(c.photonSphere)!, 0.3, accuracy: 0.01)
        XCTAssertEqual(LensCurves.meanRadius(c.einsteinRing)!, 0.5, accuracy: 0.005)
    }
}
