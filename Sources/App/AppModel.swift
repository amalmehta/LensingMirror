import AppKit
import Observation
import QuartzCore

/// What the app is showing and doing. The renderer reads it every frame.
@MainActor @Observable
final class AppModel {
    static let massRange = 0.05...1.0
    static let spinRange = 0.0...0.998
    static let distanceRange = 3.0...40.0
    /// The observer never gets closer than this many M (well outside the photon orbit).
    static let closestApproach = 6.0

    enum SourceStatus: Equatable {
        case starting
        case camera(String)
        case testPattern
        case denied
        case unavailable(String)
    }

    struct Toast: Equatable { let message: String; let file: URL? }

    // Lens (in scene units; the mirror sits `prefs.mirrorDistance` behind the hole)
    var mass = 0.25 { didSet { lensChanged() } }
    var spin = 0.7 { didSet { lensChanged() } }
    var distance = 12.0 { didSet { lensChanged() } }
    var compare = false { didSet { lensChanged() } }
    var showOverlay = true

    var curves: [Int: LensCurves] = [:]
    var framesPerSecond = 0.0
    @ObservationIgnored var gpuMilliseconds = 0.0
    var sourceStatus = SourceStatus.starting
    var toast: Toast?
    var gifProgress: Double?
    var gifSaving = false

    let prefs: Preferences
    @ObservationIgnored let renderer: MirrorRenderer?
    @ObservationIgnored var lastLensChange: CFTimeInterval = 0
    @ObservationIgnored var gifCapture: GIFCapture?
    @ObservationIgnored private var camera: CameraSource?
    @ObservationIgnored private var pattern: SourceFrame?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    init(prefs: Preferences? = nil) {
        self.prefs = prefs ?? Preferences()
        if let device = MTLCreateSystemDefaultDevice(), let engine = try? LensEngine(device: device) {
            renderer = MirrorRenderer(engine: engine)
            pattern = TestPattern.frame(device: device)
            camera = CameraSource(device: device)
        } else {
            renderer = nil
        }
        renderer?.model = self
        camera?.onEvent = { [weak self] event in self?.cameraEvent(event) }
        self.prefs.onSourceChange = { [weak self] in self?.startSource() }
    }

    // MARK: Lens

    /// Observer distance in units of M.
    var distanceInM: Double { max(distance / mass, Self.closestApproach) }
    var isDistanceClamped: Bool { distance / mass < Self.closestApproach }
    /// Mirror distance behind the hole in units of M.
    var planeInM: Double { max(prefs.mirrorDistance / mass, 4) }

    func setup(spin: Double) -> LensSetup {
        LensSetup(spin: spin, distance: distanceInM, plane: planeInM,
                  tanHalfFov: tan(prefs.fieldOfView * .pi / 360), stepK: prefs.accuracy.stepK)
    }

    var paneLayouts: [PaneLayout] { PaneLayout.layouts(compare: compare, spin: spin) }

    private func lensChanged() { lastLensChange = CACurrentMediaTime() }

    // MARK: Source

    func startSource() {
        guard let camera else { return }
        camera.stop()
        if prefs.useTestPattern || Self.isRunningTests {
            sourceStatus = .testPattern
            return
        }
        sourceStatus = .starting
        camera.start(deviceID: prefs.cameraID, preferSixty: prefs.preferSixtyFPS)
    }

    private func cameraEvent(_ event: CameraSource.Event) {
        guard !prefs.useTestPattern else { return }
        switch event {
        case .running(let name, _): sourceStatus = .camera(name)
        case .denied: sourceStatus = .denied
        case .unavailable(let why): sourceStatus = .unavailable(why)
        }
    }

    /// The camera's newest frame, or the test pattern when there's no camera.
    func currentSource() -> SourceFrame? {
        if case .testPattern = sourceStatus { return pattern }
        return camera?.currentFrame ?? pattern
    }

    // MARK: Export

    /// Flip left-right only for a camera feed; the test pattern reads the right way round.
    var mirrorsSource: Bool {
        if case .testPattern = sourceStatus { return false }
        return prefs.mirrorImage && camera?.currentFrame != nil
    }

    func takeSnapshot() { renderer?.snapshotRequested = true }

    func toggleGIF() {
        if gifCapture != nil { gifCapture = nil; gifProgress = nil; return }   // cancel
        guard !gifSaving else { return }
        let viewAspect = (NSApp.keyWindow?.contentView?.bounds.size).map { $0.width / max($0.height, 1) } ?? 16 / 10
        let w = prefs.gifWidth & ~1
        gifCapture = GIFCapture(seconds: prefs.gifSeconds, fps: prefs.gifFPS, width: w,
                                height: max(2, Int(Double(w) / viewAspect) & ~1))
        gifProgress = 0
    }

    func finishedExport(_ result: Result<URL, Error>, kind: String) {
        if kind == "GIF" { gifSaving = false }
        switch result {
        case .success(let url): show(Toast(message: "\(kind) saved", file: url))
        case .failure(let error): show(Toast(message: "\(kind) not saved: \(error.localizedDescription)", file: nil))
        }
    }

    func show(_ t: Toast) {
        toast = t
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { self?.toast = nil }
        }
    }
}
