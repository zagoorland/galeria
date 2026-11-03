# Performance notes

Galeria aims to keep interaction work on the main thread close to layout and rendering only.

## Measured stress run

Environment: Apple silicon Mac, macOS 26.6, Xcode 27.1, Debug build with checks enabled, 10,000 images in one folder. The stress files were hard links to a 1800×1000 PNG, which makes directory work representative but thumbnail source data unusually uniform.

| Metric | Result |
| --- | --- |
| First tile visible, including app launch and warm disk thumbnail cache | ≈ 1.1 s |
| First tile visible when timing starts after process launch | ≈ 1.06 s |
| Full scan complete and all 10,000 items published | ≈ 4.2 s |
| Resident memory after load | ≈ 235 MB |
| Disk thumbnail cache | bounded by the cache limit in Settings (default 1 GB) |
| Full-size images retained by the grid | 0 |

Reproduce:

```bash
# Make a 10k test folder from any sample image
mkdir -p /tmp/galeria-10k
for i in $(seq -w 0 9999); do
  ln /path/to/sample.png "/tmp/galeria-10k/img-$i.png" 2>/dev/null || true
done

GALERIA_SAMPLE_FOLDER=/tmp/galeria-10k \
  .build/DerivedData/Build/Products/Debug/galeria.app/Contents/MacOS/galeria
```

Then inspect with Activity Monitor or `ps -o rss` while scrolling.

## What the workload looks like

- **Scanning:** `ImageScanner` is an actor. It enumerates files, reads only ImageIO header/property dictionaries, and never decodes full bitmaps. It publishes an initial batch of 12 parsed images, so the first screen appears before the entire folder has been processed. Cancellation is checked per file.
- **Thumbnails:** `ThumbnailService` is an actor. It uses `CGImageSourceCreateThumbnailAtIndex` with transform, caches `NSImage` objects in an `NSCache` with a cost limit, and writes JPEG thumbnails to a disk cache keyed by path + modified date + pixel bucket. When the grid density changes, a smaller request is served by downscaling a larger memory or disk variant instead of regenerating from the original. One cancellable preheat worker handles `NSCollectionViewPrefetching`, while visible cells load at user-initiated priority; offscreen loads are canceled on cell reuse.
- **Preview:** `PreviewImageService` downsamples to at most 4096 px, keeps a small in-memory cache, and preloads only ±2 neighbors. The grid never references these objects.
- **File/metadata work:** sorting and filtering are in-memory, all image operations (hash, Vision, export, rotate) are in actors, and trash/file transfer are async services.
- **Streaming update policy:** after the initial 12-item batch, the grid receives one final update when scanning completes. This avoids hundreds of diffable snapshot applications while still satisfying the fast-first-screen goal.

## Scrolling

The collection view reuses a fixed number of tile views; a tile's thumbnail task is cancelled on reuse, and only a downsample for the current pixel bucket/binding is displayed. The 10,000-image run above could be scrolled without loading full-resolution images on the main thread. Frame-rate capture via Instruments was not available in this automation session; a visual scroll check on interactive hardware is listed in `docs/TESTING.md`.

### Fast-scroll stress (2,000 images, 10 columns)

Tested with the actual 2,000-image sample collection (1280×853 JPEGs) in a 10-column grid.

- After a folder opens, a background worker warms the 256px thumbnail cache. On this machine it completed all 2,000 thumbnails in about **2 seconds** at 12-way concurrency. Once warmed, dragging the scrollbar from the top to 80% painted every target tile immediately, with no placeholder frames.
- If a jump lands in a genuinely cold region before warming has reached it, the target still resolves in roughly 250–350 ms. Removing the tile fade-in and looking up already-warm thumbnails synchronously on the main thread makes the warmed path feel instant.

Changes that target this case:

1. The visible tile keeps its previous thumbnail while a new pixel-size variant loads; it no longer clears to a placeholder on a density change.
2. A smaller pixel-size request is fulfilled by downscaling a larger memory/disk thumbnail when one exists, instead of decoding the original image again.
3. One cancellable prefetch worker replaces a separate detached task for every prefetched index path. Visible cells run at user-initiated priority, so they no longer compete with hundreds of invisible decodes during a fast scroll.
4. A low-priority folder warm-up populates the disk and memory caches after the first screen is shown, and cells check the memory cache synchronously before starting an asynchronous load.

## Memory

- Thumbnail `NSCache`: 384 MB memory cost limit; 2,000 item count limit.
- Preview `NSCache`: 256 MB cost limit.
- Preview decode: 4096 px maximum long edge.
- Thumbnail disk cache: user-configurable limit, trimmed oldest-first.
- All tasks and caches are budgeted and discardable; they do not grow with folder size.

## Practical guidance

For folders above roughly 20,000 images, first-screen latency is dominated by directory enumeration and sorting names before the first batch. This could be further improved by starting enumeration without a global filename sort and applying the final sort at completion. The current behavior favors stable order during the first batch.
