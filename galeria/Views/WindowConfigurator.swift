import AppKit
import SwiftUI

/// Applies the native window settings SwiftUI does not expose directly.
struct WindowConfigurator: NSViewRepresentable {
    let model: GalleryModel

    func makeNSView(context: Context) -> NSView {
        ConfiguratorView(model: model)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ConfiguratorView)?.apply()
    }

    private final class ConfiguratorView: NSView {
        weak var model: GalleryModel?

        init(model: GalleryModel) {
            self.model = model
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let window, window.identifier?.rawValue != "galeria.main" else { return }
            window.identifier = NSUserInterfaceItemIdentifier("galeria.main")
            window.title = "Galeria"
            window.minSize = NSSize(width: 760, height: 520)
            window.setFrameAutosaveName("GaleriaMainWindow")
            window.tabbingMode = .disallowed
            window.collectionBehavior.insert(.fullScreenPrimary)
            if let appearance = ProcessInfo.processInfo.environment["GALERIA_APPEARANCE"] {
                NSApp.appearance = appearance == "dark" ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
            }
            model?.galleryWindow = window
        }
    }
}
