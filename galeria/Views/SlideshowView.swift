import AppKit
import SwiftUI

struct SlideshowView: View {
    @Environment(GalleryModel.self) private var model
    @State private var payload: PreviewImagePayload?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let item = model.previewCurrentItem {
                if let payload {
                    Image(nsImage: payload.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(item.url)
                        .transition(.opacity)
                } else if isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }

                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Text(item.name)
                            .lineLimit(1)
                        Text("\((model.previewIndex ?? 0) + 1) of \(model.previewItems.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Spacer()
                        Button {
                            model.toggleSlideshowPlaying()
                        } label: {
                            Image(systemName: model.isSlideshowPlaying ? "pause.fill" : "play.fill")
                                .frame(width: 28, height: 24)
                        }
                        .buttonStyle(.borderless)
                        .help(model.isSlideshowPlaying ? "Pause (Space)" : "Play (Space)")
                        Button {
                            model.stopSlideshow()
                        } label: {
                            Image(systemName: "xmark")
                                .frame(width: 28, height: 24)
                        }
                        .buttonStyle(.borderless)
                        .help("Exit Slideshow (Esc)")
                    }
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                    .background(Color.black.opacity(0.55))
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .task(id: slideshowTaskID) {
            await runTimerIfNeeded()
        }
        .task(id: "\(model.previewURL?.path ?? "")|\(model.previewCurrentItem?.modifiedAt.timeIntervalSince1970 ?? 0)") {
            payload = nil
            isLoading = true
            if let item = model.previewCurrentItem {
                payload = await model.previewImageService.image(for: item)
            }
            isLoading = false
        }
        .onExitCommand {
            model.stopSlideshow()
        }
        .accessibilityIdentifier("slideshow.overlay")
    }

    private var slideshowTaskID: String {
        "\(model.isSlideshowPlaying)|\(model.isSlideshowActive)|\(model.slideshowInterval)|\(model.previewURL?.path ?? "")"
    }

    private func runTimerIfNeeded() async {
        guard model.isSlideshowActive, model.isSlideshowPlaying else { return }
        let interval = max(model.slideshowInterval, 1)
        do {
            try await Task.sleep(for: .milliseconds(Int(interval * 1000)))
        } catch {
            return
        }
        guard !Task.isCancelled, model.isSlideshowActive, model.isSlideshowPlaying else { return }
        model.navigatePreview(by: 1, wrap: true)
    }
}
