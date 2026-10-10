@preconcurrency import MetalKit
import QuartzCore
import SwiftUI

/*
 * Drives the window. The expensive part, tracing a ray per pixel, depends only on mass,
 * spin, distance and view, so it's done once into a lens map and reused every frame.
 * A frame is then just a lookup: map texel → spot on the camera image.
 * While a slider moves (or the window resizes) a quick preview map is traced every frame.
 * A quarter-second after it stops, the full map is traced a band of rows per frame,
 * behind the picture, and swapped in when complete, so frames never wait for it.
 */
@MainActor
final class MirrorRenderer: NSObject, MTKViewDelegate {
    let engine: LensEngine
    weak var model: AppModel?
    private var maps: [Int: LensMap] = [:]          // what each pane shows
    private var building: [Int: LensMap] = [:]      // full maps in progress
    private var nextRow: [Int: Int] = [:]
    private var rowsPerFrame = 16.0
    private var overlayKeys: [Int: MapKey] = [:]
    private var overlayGeneration: [Int: Int] = [:]
    private var lastSize: CGSize = .zero
    private var fpsWindowStart: CFTimeInterval = 0
    private var fpsFrames = 0
    var snapshotRequested = false

    static let settleDelay: CFTimeInterval = 0.25
    static let previewScale = 0.3
    /// GPU time per frame the background map build tries to stay within.
    static let frameBudget: CFTimeInterval = 0.009

    init(engine: LensEngine) { self.engine = engine }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let model, let source = model.currentSource(),
              let cb = engine.queue.makeCommandBuffer() else { return }
        let now = CACurrentMediaTime()
        countFrame(now, model)

        let size = view.drawableSize
        guard size.width >= 2, size.height >= 2 else { return }
        if size != lastSize { lastSize = size; model.lastLensChange = now }
        let pointScale = size.width / max(view.bounds.width, 1)
        let interacting = now - model.lastLensChange < Self.settleDelay
        let rayScale = interacting ? min(Self.previewScale, model.prefs.lensResolution.scale) : model.prefs.lensResolution.scale
        let layouts = model.paneLayouts

        var draws: [PaneDraw] = []
        var builtRows = 0
        for layout in layouts {
            let i = layout.index
            let rect = layout.rect(in: size)
            func key(_ scale: Double, _ setup: LensSetup) -> MapKey {
                MapKey(setup: setup, width: max(32, Int(rect.width / pointScale * scale)),
                       height: max(20, Int(rect.height / pointScale * scale)))
            }
            let full = key(model.prefs.lensResolution.scale, model.setup(spin: layout.spin))
            if interacting || maps[i] == nil {
                let preview = key(min(Self.previewScale, model.prefs.lensResolution.scale), model.setup(spin: layout.spin).preview)
                if maps[i]?.key != preview && maps[i]?.key != full {
                    maps[i] = engine.makeMap(preview, reusing: maps[i], in: cb)
                }
                building[i] = nil
            } else if maps[i]?.key != full {
                if building[i]?.key != full { building[i] = engine.allocateMap(full, reusing: building[i]); nextRow[i] = 0 }
                if let map = building[i], let row = nextRow[i] {
                    let count = min(max(1, Int(rowsPerFrame)), full.height - row)
                    engine.encodeRows(map, from: row, count: count, in: cb)
                    builtRows += count
                    nextRow[i] = row + count
                    if row + count >= full.height { maps[i] = map; building[i] = nil }
                }
            }
            guard let map = maps[i] else { continue }
            if model.showOverlay, overlayKeys[i] != map.key { readOverlay(map, pane: i, in: cb) }
            draws.append(PaneDraw(map: map, rect: rect))
        }
        for stale in maps.keys where !layouts.contains(where: { $0.index == stale }) {
            maps[stale] = nil; building[stale] = nil; overlayKeys[stale] = nil; model.curves[stale] = nil
        }
        if builtRows > 0 {
            // Grow or shrink the band so frames keep their 60 fps budget.
            cb.addCompletedHandler { [weak self] cb in
                let t = cb.gpuEndTime - cb.gpuStartTime
                DispatchQueue.main.async {
                    guard let self else { return }
                    let factor = t > Self.frameBudget * 1.3 ? 0.7 : (t < Self.frameBudget * 0.8 ? 1.25 : 1)
                    self.rowsPerFrame = min(max(self.rowsPerFrame * factor, 1), 4096)
                }
            }
        }

        if let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
           let enc = cb.makeRenderCommandEncoder(descriptor: pass) {
            engine.encodeComposite(enc, panes: draws, source: source, mirror: model.mirrorsSource)
            enc.endEncoding()
            cb.present(drawable)
        }
        if snapshotRequested { snapshotRequested = false; encodeSnapshot(size: size, layouts: layouts, cb: cb, source: source) }
        if let gif = model.gifCapture, let index = gif.claimFrame(at: now) {
            encodeGIFFrame(gif, index: index, layouts: layouts, cb: cb, source: source)
        }
        cb.addCompletedHandler { [weak model] cb in
            _ = source                                  // keep the camera buffer alive until the GPU is done
            let ms = (cb.gpuEndTime - cb.gpuStartTime) * 1000
            DispatchQueue.main.async { if let model { model.gpuMilliseconds += (ms - model.gpuMilliseconds) * 0.1 } }
        }
        cb.commit()
    }

    private func countFrame(_ now: CFTimeInterval, _ model: AppModel) {
        fpsFrames += 1
        if fpsWindowStart == 0 { fpsWindowStart = now }
        if now - fpsWindowStart >= 0.5 {
            model.framesPerSecond = Double(fpsFrames) / (now - fpsWindowStart)
            fpsFrames = 0; fpsWindowStart = now
        }
    }

    /// Copy the map back after this frame and find the overlay curves off the main thread.
    private func readOverlay(_ map: LensMap, pane: Int, in cb: MTLCommandBuffer) {
        guard let buffer = engine.readback(map, in: cb) else { return }
        overlayKeys[pane] = map.key
        let generation = (overlayGeneration[pane] ?? 0) + 1
        overlayGeneration[pane] = generation
        let w = map.key.width, h = map.key.height
        cb.addCompletedHandler { [weak self] _ in
            let ptr = buffer.contents().bindMemory(to: Float.self, capacity: w * h * 4)
            let curves = LensCurves.extract(texels: UnsafeBufferPointer(start: ptr, count: w * h * 4), width: w, height: h)
            DispatchQueue.main.async {
                guard let self, self.overlayGeneration[pane] == generation else { return }
                self.model?.curves[pane] = curves
            }
        }
    }

    private func panes(for layouts: [PaneLayout], in size: CGSize) -> [PaneDraw] {
        layouts.compactMap { l in maps[l.index].map { PaneDraw(map: $0, rect: l.rect(in: size)) } }
    }

    private func encodeSnapshot(size: CGSize, layouts: [PaneLayout], cb: MTLCommandBuffer, source: SourceFrame) {
        guard let model else { return }
        let w = Int(size.width), h = Int(size.height)
        guard let buffer = engine.encodeOffscreen(width: w, height: h, panes: panes(for: layouts, in: size),
                                                  source: source, mirror: model.mirrorsSource, in: cb) else { return }
        let curves = model.showOverlay && model.prefs.overlayInExports ? model.curves : [:]
        let folder = model.prefs.exportFolder
        cb.addCompletedHandler { _ in
            DispatchQueue.global(qos: .userInitiated).async {
                guard var image = LensEngine.image(from: buffer, width: w, height: h) else { return }
                if !curves.isEmpty { image = OverlayDrawing.compose(image, layouts: layouts, curves: curves) }
                let result = Result { () -> URL in
                    let url = try Exporter.url(in: folder, ext: "png")
                    try Exporter.writePNG(image, to: url)
                    return url
                }
                DispatchQueue.main.async { model.finishedExport(result, kind: "Snapshot") }
            }
        }
    }

    private func encodeGIFFrame(_ gif: GIFCapture, index: Int, layouts: [PaneLayout], cb: MTLCommandBuffer, source: SourceFrame) {
        guard let model else { return }
        let size = CGSize(width: gif.width, height: gif.height)
        guard let buffer = engine.encodeOffscreen(width: gif.width, height: gif.height, panes: panes(for: layouts, in: size),
                                                  source: source, mirror: model.mirrorsSource, in: cb) else { return }
        model.gifProgress = gif.progress
        let curves = model.showOverlay && model.prefs.overlayInExports ? model.curves : [:]
        let folder = model.prefs.exportFolder
        cb.addCompletedHandler { _ in
            DispatchQueue.global(qos: .userInitiated).async {
                var image = LensEngine.image(from: buffer, width: gif.width, height: gif.height)
                if let i = image, !curves.isEmpty { image = OverlayDrawing.compose(i, layouts: layouts, curves: curves) }
                guard let frames = gif.store(image, at: index) else { return }
                let result = Result { () -> URL in
                    let url = try Exporter.url(in: folder, ext: "gif")
                    try Exporter.writeGIF(frames, fps: gif.fps, to: url)
                    return url
                }
                DispatchQueue.main.async { model.finishedExport(result, kind: "GIF") }
            }
        }
        if gif.requested == gif.frameCount { model.gifCapture = nil; model.gifProgress = nil; model.gifSaving = true }
    }
}

/// The MTKView inside SwiftUI.
struct MirrorView: NSViewRepresentable {
    let renderer: MirrorRenderer

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.engine.device)
        view.colorPixelFormat = renderer.engine.colorFormat
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = true
        view.delegate = renderer
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {}
}
