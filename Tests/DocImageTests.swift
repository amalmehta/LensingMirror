import Metal
import XCTest
@testable import LensingMirror

/// Renders the README pictures with the real shader and the test pattern.
/// Skipped unless DOC_IMAGES_DIR is set; see docs/INSTRUCTIONS.md.
final class DocImageTests: XCTestCase {
    func testRenderDocImages() throws {
        guard let dir = ProcessInfo.processInfo.environment["DOC_IMAGES_DIR"] else { throw XCTSkip("DOC_IMAGES_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let engine = try LensEngine(device: MTLCreateSystemDefaultDevice()!)
        let source = try XCTUnwrap(TestPattern.frame(device: engine.device))
        let tanHalf = tan(40 * Double.pi / 360)
        // The app's defaults: mass 0.25, distance 12, mirror 10 behind → D = 48 M, S = 40 M.
        func setup(_ spin: Double) -> LensSetup { LensSetup(spin: spin, distance: 48, plane: 40, tanHalfFov: tanHalf) }

        func render(_ layouts: [PaneLayout], width: Int, height: Int, name: String) throws {
            let size = CGSize(width: width, height: height)
            var panes: [PaneDraw] = []
            var curves: [Int: LensCurves] = [:]
            for layout in layouts {
                let rect = layout.rect(in: size)
                let cb = engine.queue.makeCommandBuffer()!
                let map = engine.makeMap(MapKey(setup: setup(layout.spin), width: Int(rect.width), height: Int(rect.height)), reusing: nil, in: cb)!
                let buffer = engine.readback(map, in: cb)!
                cb.commit(); cb.waitUntilCompleted()
                let n = map.key.width * map.key.height * 4
                let ptr = buffer.contents().bindMemory(to: Float.self, capacity: n)
                curves[layout.index] = LensCurves.extract(texels: UnsafeBufferPointer(start: ptr, count: n),
                                                          width: map.key.width, height: map.key.height)
                panes.append(PaneDraw(map: map, rect: rect))
            }
            let cb = engine.queue.makeCommandBuffer()!
            let buffer = engine.encodeOffscreen(width: width, height: height, panes: panes, source: source, mirror: false, in: cb)!
            cb.commit(); cb.waitUntilCompleted()
            let image = OverlayDrawing.compose(LensEngine.image(from: buffer, width: width, height: height)!, layouts: layouts, curves: curves)
            try Exporter.writePNG(image, to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }

        try render(PaneLayout.layouts(compare: true, spin: 0.95), width: 1600, height: 560, name: "compare.png")
        for spin in [0.0, 0.5, 0.9, 0.998] {
            let layout = PaneLayout(index: 0, spin: spin, unitRect: CGRect(x: 0, y: 0, width: 1, height: 1))
            try render([layout], width: 480, height: 360, name: String(format: "spin-%.3f.png", spin))
        }
    }
}
