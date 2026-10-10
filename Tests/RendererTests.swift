import ImageIO
import MetalKit
import XCTest
@testable import LensingMirror

/// Drives the real frame loop (MirrorRenderer.draw) the way the window does, without clicks:
/// preview → full map, overlay curves, compare mode, and in-app snapshot and GIF export.
@MainActor
final class RendererTests: XCTestCase {
    func testFrameLoopOverlayCompareAndExports() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LensingMirrorTests-\(UUID().uuidString)")
        let prefs = Preferences(defaults: UserDefaults(suiteName: "LensingMirrorTests.\(UUID().uuidString)")!)
        prefs.exportFolder = dir.path
        prefs.gifSeconds = 1; prefs.gifFPS = 10; prefs.gifWidth = 320
        let model = AppModel(prefs: prefs)
        model.startSource()                                   // the test pattern while testing
        XCTAssertEqual(model.sourceStatus, .testPattern)
        let renderer = try XCTUnwrap(model.renderer)

        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 480, height: 300), device: renderer.engine.device)
        view.colorPixelFormat = renderer.engine.colorFormat
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view

        func pump(until done: () -> Bool, timeout: Double = 20) async {
            let end = Date().addingTimeInterval(timeout)
            while !done() && Date() < end {
                renderer.draw(in: view)
                try? await Task.sleep(for: .milliseconds(16))
            }
        }

        // Settle: preview first, then the full map arrives in bands and the overlay is found.
        await pump(until: { model.curves[0].map { LensCurves.meanRadius($0.einsteinRing) != nil } ?? false
                            && CACurrentMediaTime() - model.lastLensChange > 2 })
        let ring = try XCTUnwrap(model.curves[0].flatMap { LensCurves.meanRadius($0.einsteinRing) })
        let sphere = try XCTUnwrap(model.curves[0].flatMap { LensCurves.meanRadius($0.photonSphere) })
        XCTAssertGreaterThan(ring, sphere, "the Einstein ring lies outside the shadow")

        // Compare: two panes, two sets of curves.
        model.compare = true
        await pump(until: { model.curves[0] != nil && model.curves[1] != nil && model.curves[1]!.aspect < 1 })
        XCTAssertNotNil(model.curves[1])

        // Snapshot through the renderer.
        model.takeSnapshot()
        await pump(until: { model.toast != nil })
        XCTAssertEqual(model.toast?.message, "Snapshot saved")
        let png = try XCTUnwrap(model.toast?.file)
        XCTAssertEqual(png.pathExtension, "png")

        // A one-second, 10 fps GIF.
        model.toast = nil
        model.toggleGIF()
        XCTAssertNotNil(model.gifProgress)
        await pump(until: { model.toast != nil })
        XCTAssertEqual(model.toast?.message, "GIF saved")
        let gif = try XCTUnwrap(model.toast?.file)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(gif as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 10)
        XCTAssertNil(model.gifProgress)
        try? FileManager.default.removeItem(at: dir)
    }
}
