import Foundation

/// UserDefaults keys shared by Settings, the main window and services.
enum PreferenceKey {
    static let defaultDensity = "settings.defaultDensity"
    static let defaultSortKey = "settings.defaultSortKey"
    static let defaultSortDirection = "settings.defaultSortDirection"
    static let thumbnailQuality = "settings.thumbnailQuality"
    static let confirmationThreshold = "settings.confirmationThreshold"
    static let includeSubfolders = "settings.includeSubfolders"
    static let smartIndexing = "settings.smartIndexing"
    static let showMetadataOverlays = "settings.showMetadataOverlays"
    static let usesOriginalAspect = "settings.usesOriginalAspect"
    static let slideshowInterval = "settings.slideshowInterval"
    static let filmstripVisible = "settings.filmstripVisible"
    static let showInfoPanel = "settings.showInfoPanel"
    static let liveTextEnabled = "settings.liveTextEnabled"
    static let cacheLimitMB = "settings.cacheLimitMB"
    static let showDockIcon = "settings.showDockIcon"

    static func density(for path: String) -> String { "folder.density.\(path)" }
    static func sortKey(for path: String) -> String { "folder.sortKey.\(path)" }
    static func sortDirection(for path: String) -> String { "folder.sortDirection.\(path)" }
    static func grouping(for path: String) -> String { "folder.grouping.\(path)" }
}

enum PreferenceDefaults {
    static let density = 3
    static let sortKey = GallerySortKey.name.rawValue
    static let sortDirection = SortDirection.ascending.rawValue
    static let thumbnailQuality = ThumbnailQuality.medium.rawValue
    static let confirmationThreshold = 10
    static let includeSubfolders = false
    static let smartIndexing = false
    static let showMetadataOverlays = true
    static let usesOriginalAspect = false
    static let slideshowInterval = 4.0
    static let filmstripVisible = true
    static let showInfoPanel = false
    static let liveTextEnabled = false
    static let cacheLimitMB = 1024

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PreferenceKey.defaultDensity: density,
            PreferenceKey.defaultSortKey: sortKey,
            PreferenceKey.defaultSortDirection: sortDirection,
            PreferenceKey.thumbnailQuality: thumbnailQuality,
            PreferenceKey.confirmationThreshold: confirmationThreshold,
            PreferenceKey.includeSubfolders: includeSubfolders,
            PreferenceKey.smartIndexing: smartIndexing,
            PreferenceKey.showMetadataOverlays: showMetadataOverlays,
            PreferenceKey.usesOriginalAspect: usesOriginalAspect,
            PreferenceKey.slideshowInterval: slideshowInterval,
            PreferenceKey.filmstripVisible: filmstripVisible,
            PreferenceKey.showInfoPanel: showInfoPanel,
            PreferenceKey.liveTextEnabled: liveTextEnabled,
            PreferenceKey.cacheLimitMB: cacheLimitMB
        ])
    }
}
