import SwiftUI

/// Sliders for mass, spin and distance, plus the action buttons.
struct ControlBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 18) {
                LabeledSlider(title: "Mass", value: $model.mass, range: AppModel.massRange, format: "%.2f",
                              help: "Mass of the black hole. Bigger means a bigger shadow and stronger bending.")
                LabeledSlider(title: "Spin", value: $model.spin, range: AppModel.spinRange, format: "%.2f",
                              help: "Kerr spin a/M. 0 is a non-spinning (Schwarzschild) hole; near 1 is spinning as fast as possible.")
                LabeledSlider(title: "Distance", value: $model.distance, range: AppModel.distanceRange, format: "%.1f",
                              help: "How far you (the camera) are from the black hole.")
                Divider().frame(height: 34)
                HStack(spacing: 6) {
                    Toggle(isOn: $model.compare) { Label("Compare", systemImage: "rectangle.split.2x1") }
                        .help("Side by side: no spin on the left, your spin on the right (⌘D)")
                    Toggle(isOn: $model.showOverlay) { Label("Overlay", systemImage: "circle.dashed") }
                        .help("Mark the Einstein ring and photon sphere (⌘L)")
                    Button(action: model.takeSnapshot) { Label("Snapshot", systemImage: "camera") }
                        .help("Save a PNG of the mirror (⌘T)")
                    gifButton
                    SettingsLink { Label("Settings", systemImage: "gearshape") }
                        .help("Camera, lens, and export settings (⌘,)")
                }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .controlSize(.large)
            }
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .environment(\.colorScheme, .dark)
    }

    private var caption: String {
        let d = String(format: "You're %.0f M from the hole", model.distanceInM)
        let clamp = model.isDistanceClamped ? " (the closest allowed)" : ""
        let s = String(format: "; the mirror image is %.0f M behind it. M is the hole's mass in length units (GM/c²).", model.planeInM)
        return d + clamp + s
    }

    @ViewBuilder private var gifButton: some View {
        if let p = model.gifProgress {
            Button(action: model.toggleGIF) {
                ZStack {
                    ProgressView(value: p).progressViewStyle(.circular).controlSize(.small)
                    Image(systemName: "stop.fill").font(.system(size: 7))
                }
            }
            .help("Recording GIF. Click to cancel.")
        } else {
            Button(action: model.toggleGIF) { Label("Record GIF", systemImage: "record.circle") }
                .disabled(model.gifSaving)
                .help(String(format: "Record a %.0f-second GIF (⌘R)", model.prefs.gifSeconds))
        }
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                Text(String(format: format, value)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range).controlSize(.small)
        }
        .frame(width: 150)
        .help(help)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(String(format: format, value))
    }
}
