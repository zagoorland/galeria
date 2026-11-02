import Foundation

extension GalleryModel {
    func imageCacheSize() async -> Int64 {
        let thumbnails = await thumbnailService.cacheSize()
        let index = await visionIndexService.cacheSize()
        return thumbnails + index
    }

    func clearImageCaches() async {
        await thumbnailService.clearCache()
        await previewImageService.clearCache()
        await visionIndexService.clearCache()
        sortFilter.filter.smartLabels = [:]
        if smartIndexingEnabled {
            scheduleSmartIndexing(force: true)
        }
    }

    func enforceImageCacheLimit() async {
        let megabytes = UserDefaults.standard.object(forKey: PreferenceKey.cacheLimitMB) as? Int
            ?? PreferenceDefaults.cacheLimitMB
        await thumbnailService.trimCache(maxBytes: Int64(megabytes) * 1024 * 1024)
    }
}
