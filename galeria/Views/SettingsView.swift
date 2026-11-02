import Foundation
import SwiftUI

struct SettingsView: View {
    @Environment(GalleryModel.self) private var model
    @AppStorage(PreferenceKey.defaultDensity) private var defaultDensity = PreferenceDefaults.density
    @AppStorage(PreferenceKey.defaultSortKey) private var defaultSortKey = PreferenceDefaults.sortKey
    @AppStorage(PreferenceKey.defaultSortDirection) private var defaultSortDirection = PreferenceDefaults.sortDirection
    @AppStorage(PreferenceKey.thumbnailQuality) private var thumbnailQuality = PreferenceDefaults.thumbnailQuality
    @AppStorage(PreferenceKey.confirmationThreshold) private var confirmationThreshold = PreferenceDefaults.confirmationThreshold
    @AppStorage(PreferenceKey.includeSubfolders) private var includeSubfolders = PreferenceDefaults.includeSubfolders
    @AppStorage(PreferenceKey.showMetadataOverlays) private var showMetadataOverlays = PreferenceDefaults.showMetadataOverlays
    @AppStorage(PreferenceKey.cacheLimitMB) private var cacheLimitMB = PreferenceDefaults.cacheLimitMB
    @State private var cacheSize: Int64 = 0

    var body: some View {
        TabView {
            Form {
                Section("Grid") {
                    Picker("Default Columns", selection: $defaultDensity) {
                        ForEach(1...10, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    Toggle("Show Ratings, Labels and Flags", isOn: $showMetadataOverlays)
                }
                Section("Browsing") {
                    Toggle("Include Subfolders by Default", isOn: $includeSubfolders)
                    Picker("Default Sort", selection: $defaultSortKey) {
                        ForEach(GallerySortKey.allCases) { key in
                            Text(key.displayName).tag(key.rawValue)
                        }
                    }
                    Picker("Default Order", selection: $defaultSortDirection) {
                        Text("Ascending").tag(SortDirection.ascending.rawValue)
                        Text("Descending").tag(SortDirection.descending.rawValue)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Thumbnails") {
                    Picker("Quality", selection: $thumbnailQuality) {
                        ForEach(ThumbnailQuality.allCases) { quality in
                            Text(quality.displayName).tag(quality.rawValue)
                        }
                    }
                    Text("Higher quality uses more memory and cache space.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Safety") {
                    Stepper("Confirm Trash Above \(confirmationThreshold) Images",
                            value: $confirmationThreshold, in: 1...200)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Images", systemImage: "photo") }

            Form {
                Section("Cache") {
                    Picker("Cache Limit", selection: $cacheLimitMB) {
                        Text("256 MB").tag(256)
                        Text("512 MB").tag(512)
                        Text("1 GB").tag(1024)
                        Text("2 GB").tag(2048)
                    }
                    HStack {
                        Text("Thumbnail and Content Index")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Button("Clear Cache") {
                        Task {
                            await model.clearImageCaches()
                            await refreshCacheSize()
                        }
                    }
                    Text("Cached thumbnails and Vision labels are regenerated as needed. Original images are never changed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Storage", systemImage: "internaldrive") }

            Form {
                Section("Preview") {
                    Toggle("Show Filmstrip in Quick Preview", isOn: Binding(
                        get: { model.previewShowFilmstrip },
                        set: { model.previewShowFilmstrip = $0 }
                    ))
                    Toggle("Enable Live Text by Default", isOn: Binding(
                        get: { model.previewLiveTextEnabled },
                        set: { model.previewLiveTextEnabled = $0 }
                    ))
                    HStack {
                        Text("Slideshow Interval")
                        Slider(value: Binding(
                            get: { model.slideshowInterval },
                            set: { model.slideshowInterval = $0 }
                        ), in: 1...15, step: 1)
                        .frame(width: 160)
                        Text("\(Int(model.slideshowInterval)) s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Preview", systemImage: "eye") }

            Form {
                Section("Content Search") {
                    Toggle("Index Images with Vision", isOn: Binding(
                        get: { model.smartIndexingEnabled },
                        set: { model.smartIndexingEnabled = $0 }
                    ))
                    Text("Classifies images on this Mac so you can search for “dog” or “beach.” Indexing is opt-in and never leaves your Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.isIndexing {
                        HStack {
                            ProgressView(value: model.smartIndexProgress)
                            Text("\(Int(model.smartIndexProgress * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Privacy") {
                    Text("Vision runs entirely on this Mac. Galeria never uploads images or labels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Smart", systemImage: "sparkles") }
        }
        .frame(width: 520)
        .padding(.top, 8)
        .onChange(of: thumbnailQuality) { _, newValue in
            if let quality = ThumbnailQuality(rawValue: newValue) {
                model.thumbnailQuality = quality
            }
        }
        .onChange(of: showMetadataOverlays) { _, newValue in
            model.showMetadataOverlays = newValue
        }
        .onChange(of: cacheLimitMB) { _, _ in
            Task {
                await model.enforceImageCacheLimit()
                await refreshCacheSize()
            }
        }
        .task {
            await refreshCacheSize()
        }
    }

    @MainActor
    private func refreshCacheSize() async {
        cacheSize = await model.imageCacheSize()
    }
}
