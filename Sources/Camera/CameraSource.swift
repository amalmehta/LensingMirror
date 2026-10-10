import AVFoundation
import CoreVideo
import Metal

/// Webcam → Metal textures, with no copies (CVMetalTextureCache wraps the camera's buffers).
final class CameraSource: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Event {
        case running(name: String, fps: Double)
        case denied
        case unavailable(String)
    }

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "Lensing Mirror camera session")
    private let frameQueue = DispatchQueue(label: "Lensing Mirror camera frames")
    private var cache: CVMetalTextureCache?
    private let lock = NSLock()
    private var latest: SourceFrame?
    /// Called on the main queue.
    var onEvent: ((Event) -> Void)?

    init(device: MTLDevice) {
        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)
    }

    static func availableDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified).devices
    }

    /// The newest frame, or nil before the first one arrives.
    var currentFrame: SourceFrame? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    func start(deviceID: String, preferSixty: Bool) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure(deviceID: deviceID, preferSixty: preferSixty)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.configure(deviceID: deviceID, preferSixty: preferSixty) } else { self.report(.denied) }
            }
        default:
            report(.denied)
        }
    }

    func stop() {
        sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } }
        lock.lock(); latest = nil; lock.unlock()
    }

    private func report(_ e: Event) { DispatchQueue.main.async { self.onEvent?(e) } }

    private func configure(deviceID: String, preferSixty: Bool) {
        sessionQueue.async { [self] in
            let devices = Self.availableDevices()
            guard let device = devices.first(where: { $0.uniqueID == deviceID })
                    ?? AVCaptureDevice.default(for: .video) ?? devices.first else {
                report(.unavailable("No camera found")); return
            }
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else { throw CocoaError(.featureUnsupported) }
                session.addInput(input)
            } catch {
                session.commitConfiguration()
                report(.unavailable("Couldn't open \(device.localizedName)")); return
            }
            if session.outputs.isEmpty, session.canAddOutput(output) { session.addOutput(output) }
            var fps = 30.0
            if preferSixty, let format = Self.sixtyFPSFormat(device) {
                if (try? device.lockForConfiguration()) != nil {
                    device.activeFormat = format
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
                    device.unlockForConfiguration()
                    fps = 60
                }
            } else if session.canSetSessionPreset(.hd1280x720) {
                session.sessionPreset = .hd1280x720
            }
            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }
            report(.running(name: device.localizedName, fps: fps))
        }
    }

    /// The widest format up to 1920 px that can run at 60 fps, if the camera has one.
    private static func sixtyFPSFormat(_ device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        device.formats
            .filter { f in
                let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
                return d.width <= 1920 && f.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 59.9 }
            }
            .max { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width
                 < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer), let cache else { return }
        let w = CVPixelBufferGetWidth(pixels), h = CVPixelBufferGetHeight(pixels)
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixels, nil, .bgra8Unorm, w, h, 0, &cvTexture)
        guard let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { return }
        let frame = SourceFrame(texture: texture, keepAlive: cvTexture)
        lock.lock(); latest = frame; lock.unlock()
    }
}
