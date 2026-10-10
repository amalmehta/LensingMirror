import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color.black
            if let renderer = model.renderer {
                MirrorView(renderer: renderer)
            } else {
                ContentUnavailableView("Metal isn't available", systemImage: "exclamationmark.triangle",
                                       description: Text("Lensing Mirror needs a Metal-capable GPU."))
            }
            if model.showOverlay { OverlayLayer(layouts: model.paneLayouts, curves: model.curves) }
            PaneLabels(layouts: model.paneLayouts, compare: model.compare)
        }
        .overlay(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                if model.showOverlay { OverlayLegend() }
                ControlBar()
            }
            .padding(14)
        }
        .overlay(alignment: .top) { StatusBanner().padding(.top, 12) }
        .overlay(alignment: .topTrailing) {
            if model.prefs.showFrameRate {
                Text(String(format: "%.0f fps · GPU %.1f ms", model.framesPerSecond, model.gpuMilliseconds))
                    .font(.caption.monospacedDigit()).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule()).environment(\.colorScheme, .dark)
                    .padding(12)
            }
        }
        .overlay(alignment: .trailing) { FeedbackTab() }
        .frame(minWidth: 980, minHeight: 600)
        .onAppear { model.startSource() }
    }
}

/// "Schwarzschild · no spin" / "Kerr · spin 0.70" at the top-left of each pane.
private struct PaneLabels: View {
    let layouts: [PaneLayout]
    let compare: Bool

    var body: some View {
        GeometryReader { geo in
            ForEach(layouts, id: \.index) { layout in
                let rect = layout.rect(in: geo.size)
                HStack(spacing: 6) {
                    Circle().fill(layout.isSchwarzschild ? Palette.schwarzschild : Palette.kerr).frame(width: 9, height: 9)
                    Text(layout.title).font(.callout.weight(.semibold))
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
                .position(x: rect.minX + 14, y: rect.minY + 24)
                .offset(x: 90)
            }
            if compare {
                Rectangle().fill(.black).frame(width: 2).position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .frame(height: geo.size.height)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Camera state and export toasts.
private struct StatusBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            switch model.sourceStatus {
            case .denied:
                banner("Camera access is off, so you're seeing the test pattern.", action: "Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
            case .unavailable(let why):
                banner("\(why). Showing the test pattern.", action: nil) {}
            default:
                EmptyView()
            }
            if let toast = model.toast {
                banner(toast.message, action: toast.file == nil ? nil : "Show in Finder") {
                    if let f = toast.file { NSWorkspace.shared.activateFileViewerSelecting([f]) }
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
    }

    private func banner(_ text: String, action: String?, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(text).font(.callout)
            if let action { Button(action, action: perform).controlSize(.small) }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
