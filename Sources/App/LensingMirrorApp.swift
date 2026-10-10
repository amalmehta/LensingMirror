import SwiftUI

@main
struct LensingMirrorApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Lensing Mirror", id: "mirror") {
            ContentView().environment(model)
        }
        .defaultSize(width: 1180, height: 760)
        .commands { MirrorCommands(model: model) }

        Settings {
            SettingsView().environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

private struct MirrorCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Mirror") {
            Button("Take Snapshot", action: model.takeSnapshot).keyboardShortcut("t")
            Button(model.gifProgress == nil ? "Record GIF" : "Cancel GIF", action: model.toggleGIF).keyboardShortcut("r")
            Divider()
            Toggle("Compare Side by Side", isOn: Binding(get: { model.compare }, set: { model.compare = $0 }))
                .keyboardShortcut("d")
            Toggle("Show Overlay", isOn: Binding(get: { model.showOverlay }, set: { model.showOverlay = $0 }))
                .keyboardShortcut("l")
        }
    }
}
