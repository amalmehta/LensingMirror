import Foundation
import Observation

/// Every preference, in one place (the Settings window, ⌘,). Saved to UserDefaults.
@MainActor @Observable
final class Preferences {
    enum LensResolution: String, CaseIterable, Identifiable {
        case low, standard, high
        var id: String { rawValue }
        var title: String { ["low": "Low (fastest)", "standard": "Standard", "high": "High (Retina)"][rawValue]! }
        /// Traced rays per point of window size, along each side.
        var scale: Double { ["low": 0.5, "standard": 1.0, "high": 2.0][rawValue]! }
    }

    enum Accuracy: String, CaseIterable, Identifiable {
        case fast, balanced, precise
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var stepK: Double { ["fast": 0.08, "balanced": 0.05, "precise": 0.025][rawValue]! }
    }

    static let defaultExportFolder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Lensing Mirror").path

    @ObservationIgnored private let defaults: UserDefaults
    /// Called when a camera setting changes, so the source restarts.
    @ObservationIgnored var onSourceChange: (() -> Void)?

    // Camera
    var cameraID: String { didSet { save("cameraID", cameraID); onSourceChange?() } }
    var useTestPattern: Bool { didSet { save("useTestPattern", useTestPattern); onSourceChange?() } }
    var preferSixtyFPS: Bool { didSet { save("preferSixtyFPS", preferSixtyFPS); onSourceChange?() } }
    var mirrorImage: Bool { didSet { save("mirrorImage", mirrorImage) } }
    // Lens
    var mirrorDistance: Double { didSet { save("mirrorDistance", mirrorDistance) } }
    var fieldOfView: Double { didSet { save("fieldOfView", fieldOfView) } }
    var lensResolution: LensResolution { didSet { save("lensResolution", lensResolution.rawValue) } }
    var accuracy: Accuracy { didSet { save("accuracy", accuracy.rawValue) } }
    var showFrameRate: Bool { didSet { save("showFrameRate", showFrameRate) } }
    // Export
    var exportFolder: String { didSet { save("exportFolder", exportFolder) } }
    var overlayInExports: Bool { didSet { save("overlayInExports", overlayInExports) } }
    var gifSeconds: Double { didSet { save("gifSeconds", gifSeconds) } }
    var gifFPS: Int { didSet { save("gifFPS", gifFPS) } }
    var gifWidth: Int { didSet { save("gifWidth", gifWidth) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func value<T>(_ key: String, _ fallback: T) -> T { defaults.object(forKey: key) as? T ?? fallback }
        cameraID = value("cameraID", "")
        useTestPattern = value("useTestPattern", false)
        preferSixtyFPS = value("preferSixtyFPS", true)
        mirrorImage = value("mirrorImage", true)
        mirrorDistance = value("mirrorDistance", 10.0)
        fieldOfView = value("fieldOfView", 40.0)
        lensResolution = LensResolution(rawValue: value("lensResolution", "")) ?? .standard
        accuracy = Accuracy(rawValue: value("accuracy", "")) ?? .balanced
        showFrameRate = value("showFrameRate", false)
        exportFolder = value("exportFolder", Self.defaultExportFolder)
        overlayInExports = value("overlayInExports", true)
        gifSeconds = value("gifSeconds", 3.0)
        gifFPS = value("gifFPS", 15)
        gifWidth = value("gifWidth", 640)
    }

    private func save(_ key: String, _ v: Any) { defaults.set(v, forKey: key) }

    func resetToDefaults() {
        let fresh = Preferences(defaults: UserDefaults(suiteName: "LensingMirror.defaults.\(UUID())")!)
        cameraID = fresh.cameraID; useTestPattern = fresh.useTestPattern; preferSixtyFPS = fresh.preferSixtyFPS
        mirrorImage = fresh.mirrorImage; mirrorDistance = fresh.mirrorDistance; fieldOfView = fresh.fieldOfView
        lensResolution = fresh.lensResolution; accuracy = fresh.accuracy; showFrameRate = fresh.showFrameRate
        exportFolder = fresh.exportFolder; overlayInExports = fresh.overlayInExports
        gifSeconds = fresh.gifSeconds; gifFPS = fresh.gifFPS; gifWidth = fresh.gifWidth
    }
}
