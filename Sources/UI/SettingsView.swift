import AVFoundation
import SwiftUI

/// Every preference in one window (⌘,).
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            CameraSettings().tabItem { Label("Camera", systemImage: "web.camera") }
            LensSettings().tabItem { Label("Lens", systemImage: "circle.circle") }
            ExportSettings().tabItem { Label("Export", systemImage: "square.and.arrow.up") }
        }
        .frame(width: 500)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Reset to Defaults") { model.prefs.resetToDefaults() }
            }
            .padding([.horizontal, .bottom], 16)
        }
    }
}

private struct CameraSettings: View {
    @Environment(AppModel.self) private var model
    @State private var devices: [AVCaptureDevice] = []

    var body: some View {
        @Bindable var prefs = model.prefs
        Form {
            Picker("Camera", selection: $prefs.cameraID) {
                Text("Default camera").tag("")
                ForEach(devices, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
            }
            Toggle("Use the test pattern instead of the camera", isOn: $prefs.useTestPattern)
            Toggle("Flip the camera left and right, like a mirror", isOn: $prefs.mirrorImage)
            Toggle("Ask the camera for 60 fps when it can", isOn: $prefs.preferSixtyFPS)
        }
        .formStyle(.grouped)
        .onAppear { devices = CameraSource.availableDevices() }
    }
}

private struct LensSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.prefs
        Form {
            Section {
                LabeledContent("Mirror image behind the hole") {
                    Slider(value: $prefs.mirrorDistance, in: 3...30) { Text("") } minimumValueLabel: { Text("3") } maximumValueLabel: { Text("30") }
                        .frame(width: 200)
                    Text(String(format: "%.1f", prefs.mirrorDistance)).monospacedDigit().frame(width: 34, alignment: .trailing)
                }
                LabeledContent("Field of view (vertical)") {
                    Slider(value: $prefs.fieldOfView, in: 20...80, step: 1) { Text("") } minimumValueLabel: { Text("20°") } maximumValueLabel: { Text("80°") }
                        .frame(width: 200)
                    Text(String(format: "%.0f°", prefs.fieldOfView)).monospacedDigit().frame(width: 34, alignment: .trailing)
                }
            } footer: {
                Text("The camera image is a flat screen this far behind the black hole, in the same units as Distance. Further back means a wider Einstein ring.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Ray resolution", selection: $prefs.lensResolution) {
                    ForEach(Preferences.LensResolution.allCases) { Text($0.title).tag($0) }
                }
                Picker("Ray accuracy", selection: $prefs.accuracy) {
                    ForEach(Preferences.Accuracy.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show frame rate", isOn: $prefs.showFrameRate)
            } footer: {
                Text("Rays are traced again only when the lens changes, so these mostly affect how quickly the picture sharpens after you move a slider.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ExportSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.prefs
        Form {
            Section("Snapshots and GIFs") {
                LabeledContent("Save to") {
                    Text((prefs.exportFolder as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle)
                    Button("Choose…") { chooseFolder() }
                    Button("Show") {
                        let url = URL(fileURLWithPath: prefs.exportFolder)
                        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(url)
                    }
                }
                Toggle("Include the overlay when it's showing", isOn: $prefs.overlayInExports)
            }
            Section("GIF") {
                Stepper(value: $prefs.gifSeconds, in: 1...8, step: 1) {
                    LabeledContent("Length", value: String(format: "%.0f seconds", prefs.gifSeconds))
                }
                Picker("Frame rate", selection: $prefs.gifFPS) {
                    ForEach([10, 15, 20, 30], id: \.self) { Text("\($0) fps").tag($0) }
                }
                Picker("Width", selection: $prefs.gifWidth) {
                    ForEach([480, 640, 800, 1080], id: \.self) { Text("\($0) px").tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url { model.prefs.exportFolder = url.path }
    }
}
