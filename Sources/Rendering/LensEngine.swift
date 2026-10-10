import CoreGraphics
import Metal

/// The current image behind the hole: a camera frame or the test pattern.
struct SourceFrame: @unchecked Sendable {
    let texture: MTLTexture
    let keepAlive: AnyObject?          // the CVMetalTexture the camera frame lives in
    var aspect: Float { Float(texture.width) / Float(texture.height) }
}

/// What a lens map was built for. A new key means a new map.
struct MapKey: Equatable {
    var setup: LensSetup
    var width: Int
    var height: Int
    var aspect: Double { Double(width) / Double(height) }
}

/// A lens map on the GPU (RGBA32Float, one texel per traced ray).
final class LensMap {
    let texture: MTLTexture
    let key: MapKey
    init(texture: MTLTexture, key: MapKey) { self.texture = texture; self.key = key }
}

/// One pane of the picture: which map to use and where it goes, in target pixels.
struct PaneDraw {
    let map: LensMap
    let rect: CGRect
}

enum LensEngineError: Error { case noLibrary, noFunction(String) }

/// The Metal side, with no UI: builds lens maps and composites the camera through them.
final class LensEngine {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let colorFormat: MTLPixelFormat = .bgra8Unorm
    private let mapPipeline: MTLComputePipelineState
    private let compositePipeline: MTLRenderPipelineState

    init(device: MTLDevice) throws {
        self.device = device
        // The shader ships as source and is compiled here, so building the app needs no Metal toolchain.
        guard let queue = device.makeCommandQueue(),
              let url = Bundle(for: LensEngine.self).url(forResource: "LensShaders", withExtension: "msl"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { throw LensEngineError.noLibrary }
        let options = MTLCompileOptions()
        options.fastMathEnabled = false   // keep the ray maths IEEE, like the CPU twin
        let library = try device.makeLibrary(source: source, options: options)
        self.queue = queue
        func fn(_ name: String) throws -> MTLFunction {
            guard let f = library.makeFunction(name: name) else { throw LensEngineError.noFunction(name) }
            return f
        }
        mapPipeline = try device.makeComputePipelineState(function: fn("buildLensMap"))
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = try fn("fullscreenVertex")
        desc.fragmentFunction = try fn("compositeFragment")
        desc.colorAttachments[0].pixelFormat = colorFormat
        compositePipeline = try device.makeRenderPipelineState(descriptor: desc)
    }

    /// Encode a whole map build in one go.
    func makeMap(_ key: MapKey, reusing reuse: LensMap?, in cb: MTLCommandBuffer) -> LensMap? {
        guard let map = allocateMap(key, reusing: reuse) else { return nil }
        encodeRows(map, from: 0, count: key.height, in: cb)
        return map
    }

    /// A map texture for `key`. Reuses `reuse`'s texture when the size matches (Metal orders
    /// the writes after any earlier reads on the same queue).
    func allocateMap(_ key: MapKey, reusing reuse: LensMap?) -> LensMap? {
        var texture = reuse?.texture
        if texture?.width != key.width || texture?.height != key.height {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: key.width,
                                                             height: key.height, mipmapped: false)
            d.usage = [.shaderRead, .shaderWrite]
            d.storageMode = .private
            texture = device.makeTexture(descriptor: d)
        }
        return texture.map { LensMap(texture: $0, key: key) }
    }

    /// Trace rows [row, row + count) of a map.
    func encodeRows(_ map: LensMap, from row: Int, count: Int, in cb: MTLCommandBuffer) {
        guard count > 0, let enc = cb.makeComputeCommandEncoder() else { return }
        let key = map.key
        var params = MapParams(key.setup, aspect: key.aspect, width: key.width, height: key.height)
        params.rowOffset = Int32(row)
        enc.setComputePipelineState(mapPipeline)
        enc.setTexture(map.texture, index: 0)
        enc.setBytes(&params, length: MemoryLayout<MapParams>.stride, index: 0)
        enc.dispatchThreadgroups(MTLSize(width: (key.width + 7) / 8, height: (count + 7) / 8, depth: 1),
                                 threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        enc.endEncoding()
    }

    /// Copy a map into CPU-visible memory (for the overlay and the tests).
    func readback(_ map: LensMap, in cb: MTLCommandBuffer) -> MTLBuffer? {
        let w = map.key.width, h = map.key.height, row = w * 16
        guard let buffer = device.makeBuffer(length: row * h, options: .storageModeShared),
              let blit = cb.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: map.texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                  sourceSize: MTLSize(width: w, height: h, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: row, destinationBytesPerImage: row * h)
        blit.endEncoding()
        return buffer
    }

    /// Draw every pane into an open render pass.
    func encodeComposite(_ enc: MTLRenderCommandEncoder, panes: [PaneDraw], source: SourceFrame, mirror: Bool) {
        enc.setRenderPipelineState(compositePipeline)
        enc.setFragmentTexture(source.texture, index: 1)
        for pane in panes {
            let r = pane.rect
            enc.setViewport(MTLViewport(originX: r.minX, originY: r.minY, width: r.width, height: r.height,
                                        znear: 0, zfar: 1))
            var c = CompositeParams(origin: SIMD2(Float(r.minX), Float(r.minY)),
                                    size: SIMD2(Float(r.width), Float(r.height)),
                                    mapSize: SIMD2(Float(pane.map.key.width), Float(pane.map.key.height)),
                                    camAspect: source.aspect, paneAspect: Float(r.width / r.height),
                                    mirror: mirror ? 1 : 0)
            enc.setFragmentTexture(pane.map.texture, index: 0)
            enc.setFragmentBytes(&c, length: MemoryLayout<CompositeParams>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
    }

    /// Composite into an offscreen texture and copy it to a CPU buffer (snapshots, GIF frames).
    func encodeOffscreen(width: Int, height: Int, panes: [PaneDraw], source: SourceFrame, mirror: Bool,
                         in cb: MTLCommandBuffer) -> MTLBuffer? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: colorFormat, width: width,
                                                         height: height, mipmapped: false)
        d.usage = [.renderTarget]
        d.storageMode = .private
        guard let target = device.makeTexture(descriptor: d) else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encodeComposite(enc, panes: panes, source: source, mirror: mirror)
        enc.endEncoding()
        let row = width * 4
        guard let buffer = device.makeBuffer(length: row * height, options: .storageModeShared),
              let blit = cb.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: row, destinationBytesPerImage: row * height)
        blit.endEncoding()
        return buffer
    }

    /// BGRA8 buffer → CGImage (copies the bytes, so the buffer can go).
    static func image(from buffer: MTLBuffer, width: Int, height: Int) -> CGImage? {
        let row = width * 4
        let data = Data(bytes: buffer.contents(), count: row * height) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        let info = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                                | CGImageAlphaInfo.noneSkipFirst.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: row,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
