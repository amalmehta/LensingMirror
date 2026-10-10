import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes snapshots (PNG) and short loops (GIF) to the export folder.
enum Exporter {
    /// "Lensing Mirror 2026-10-09 at 20.31.05.png", like a macOS screenshot.
    static func fileName(_ ext: String, date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Lensing Mirror \(f.string(from: date)).\(ext)"
    }

    static func url(in folder: String, ext: String) throws -> URL {
        let dir = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName(ext))
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// A looping GIF at `fps` frames per second.
    static func writeGIF(_ frames: [CGImage], fps: Int, to url: URL) throws {
        guard !frames.isEmpty,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(fps),
                                                          kCGImagePropertyGIFUnclampedDelayTime: 1.0 / Double(fps)]] as CFDictionary
        for frame in frames { CGImageDestinationAddImage(dest, frame, frameProps) }
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }
}

/// Collects GIF frames as the renderer produces them. Frames may finish out of order.
final class GIFCapture: @unchecked Sendable {
    let frameCount: Int
    let fps: Int
    let width: Int
    let height: Int
    private(set) var requested = 0
    private var frames: [CGImage?]
    private var received = 0
    private let lock = NSLock()
    private var nextDue: CFTimeInterval = 0

    init(seconds: Double, fps: Int, width: Int, height: Int) {
        self.fps = fps
        self.frameCount = max(2, Int((seconds * Double(fps)).rounded()))
        self.width = width; self.height = height
        frames = Array(repeating: nil, count: frameCount)
    }

    /// True (and books the frame) when the next frame should be grabbed at time `now`.
    func claimFrame(at now: CFTimeInterval) -> Int? {
        guard requested < frameCount, now >= nextDue else { return nil }
        nextDue = (nextDue == 0 ? now : nextDue) + 1 / Double(fps)
        if nextDue < now { nextDue = now + 1 / Double(fps) }   // fell behind: don't burst
        defer { requested += 1 }
        return requested
    }

    /// Stores a frame. Returns all frames once the last one is in.
    func store(_ image: CGImage?, at index: Int) -> [CGImage]? {
        lock.lock(); defer { lock.unlock() }
        frames[index] = image
        received += 1
        return received == frameCount ? frames.compactMap { $0 } : nil
    }

    var progress: Double { Double(requested) / Double(frameCount) }
}
