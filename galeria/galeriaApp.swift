import SwiftUI

@main
struct GaleriaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = GalleryModel()
    @ObservedObject private var menuState = MenuState.shared

    var body: some Scene {
        Window("Galeria", id: "main") {
            RootView(appDelegate: appDelegate)
                .environment(model)
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 900, height: 1080)
        .windowToolbarStyle(.unified)
        .commands {
            GalleryCommands(model: model, state: menuState.snapshot)
        }

        Window("Keyboard Shortcuts", id: "shortcuts") {
            KeyboardShortcutsView()
                .environment(model)
        }
        .defaultSize(width: 560, height: 700)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
