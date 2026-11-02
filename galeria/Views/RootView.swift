import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(GalleryModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let appDelegate: AppDelegate

    var body: some View {
        @Bindable var model = model
        ZStack {
            NavigationSplitView(columnVisibility: $model.sidebarVisibility) {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
            } detail: {
                GalleryContentView()
            }
            .navigationSplitViewStyle(.balanced)

            if model.isComparePresented {
                CompareView()
                    .zIndex(10)
                    .transition(.opacity)
            } else if model.isSlideshowActive {
                SlideshowView()
                    .zIndex(20)
                    .transition(.opacity)
            } else if model.isCullMode {
                CullView()
                    .zIndex(12)
                    .transition(.opacity)
            } else if model.previewURL != nil {
                PreviewView()
                    .zIndex(10)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.previewURL)
        .animation(.easeInOut(duration: 0.18), value: model.isComparePresented)
        .animation(.easeInOut(duration: 0.18), value: model.isSlideshowActive)
        .animation(.easeInOut(duration: 0.18), value: model.isCullMode)
        .toolbar(model.previewURL == nil && !model.isComparePresented ? .visible : .hidden,
                 for: .windowToolbar)
        .background(WindowConfigurator(model: model))
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.handleDroppedURLs(urls) }
            return true
        } isTargeted: { targeted in
            model.isDropTargeted = targeted
        }
        .overlay {
            if model.isDropTargeted {
                DropHighlightView()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.isDropTargeted)
        .task {
            MenuState.shared.apply(MenuState.Snapshot(model: model))
            await model.start()
            model.installKeyboardMonitor()
            appDelegate.installOpenHandler { urls in
                Task { await model.handleOpenedURLs(urls) }
            }
        }
        .onAppear {
            MenuState.shared.apply(MenuState.Snapshot(model: model))
        }
        .onChange(of: MenuState.Snapshot(model: model)) { _, snapshot in
            MenuState.shared.apply(snapshot)
        }
        .onReceive(NotificationCenter.default.publisher(for: .galeriaShowShortcuts)) { _ in
            openWindow(id: "shortcuts")
        }
        .onDisappear {
            model.removeKeyboardMonitor()
        }
        .alert(item: $model.presentedError) { error in
            switch error.recovery {
            case .chooseFolder:
                return Alert(
                    title: Text(error.title),
                    message: Text(error.message),
                    primaryButton: .default(Text("Choose Folder")) { model.chooseAnotherFolder() },
                    secondaryButton: .cancel()
                )
            case .retry:
                return Alert(
                    title: Text(error.title),
                    message: Text(error.message),
                    primaryButton: .default(Text("Try Again")) { Task { await model.retryFolder() } },
                    secondaryButton: .cancel()
                )
            case .none:
                return Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("OK")))
            }
        }
    }
}

private struct DropHighlightView: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.accentColor.opacity(0.10))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [9, 6]))
                .padding(12)
            VStack(spacing: 10) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.tint)
                Text("Drop to Open Folder or Add Images")
                    .font(.headline)
                Text("Galeria keeps selection and scroll position.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        }
        .padding(8)
    }
}
