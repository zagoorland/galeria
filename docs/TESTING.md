# Manual acceptance checklist

The stable automated suite is the Swift Testing suite in `galeriaTests`. This checklist covers the interactive behavior that requires a real WindowServer, Accessibility permissions, or another application.

## Folder session

- Open Galeria with no folder. Use **Open Folder…**, `⌘O`, and a folder dropped on the window.
- Quit and relaunch. The last folder reopens with its density, sort, and grouping.
- Move the reopened folder while the app is closed. Relaunch: a clear error offers **Choose Folder**.
- Toggle **Include Subfolders** in the View menu. Counts and the subfolder tree update.
- Add, rename, and remove files in Finder while Galeria is open. The grid updates without losing selection or jumping to the top.

## Grid and selection

- Adjust density with the toolbar slider and a trackpad pinch. Columns fill the available width.
- Toggle original aspect ratio. Rows are justified and section headers stick while scrolling.
- Click, Shift-click, Command-click, `⌘A`, `⇧⌘A`, click empty space, and drag a marquee over empty space.
- Toggle Select mode and verify modifier-free toggling with checkmark circles.
- Use arrow keys and verify the selected tile scrolls into view.

## File actions

- Select one and three images and move them to Trash. Only selections larger than the threshold (default: 11 or more items) should show a threshold confirmation by default.
- `⌘Z` restores all files through the recycle mapping. `⇧⌘Z` re-trashes where possible.
- Select 2–4 images and open Compare from the toolbar. Zoom and pan one pane; all panes track.
- Rate, label, flag, and tag images. Confirm `Pick`, `Rating 4`, etc. appear in Finder's Get Info tags area. Hide overlays in Settings.
- Copy files and copy as image; paste into Finder and a rich-text editor.
- Move and copy to a folder with an existing same-named file. Confirm no overwrite and a numeric suffix.
- Pin a folder, use quick-move destinations, and drop selected images onto a sidebar folder. Confirm move and undo.

## Preview

- Double-click and Return open Quick Preview; Space toggles; Escape closes.
- Navigate with all four arrow keys; neighbors preload without a visible stall.
- Pinch, scroll while zoomed, double-click, `+`, `−`, and `0`. Animated GIFs animate.
- At fit scale, swipe right/left with two fingers to move to the previous/next image and swipe down to close.
- EXIF orientation is upright in preview, filmstrip, info, compare, and export.
- Toggle filmstrip and Live Text. Select text in the image and copy it.
- Open Info (`⌘I`), inspect all metadata, and click a GPS pin/Open in Maps.
- Trash from preview and verify auto-advance. Undo the trash.
- Drag the image body to Finder.
- Start the slideshow; verify interval, Space pause, Escape and fullscreen restoration.

## Culling and duplicates

- Use the Cull toolbar button. `P`/`X` auto-advance and progress updates.
- Review Rejected shows the rejects. Move them to Trash and Undo once.
- Find Duplicates exact scan and similar scan (adjust threshold) complete with progress and are cancellable. Pick keepers and trash the rest.

## Batch rename and export

- Select images, choose **Batch Rename…**, exercise every token, counter start/padding, live preview, and a deliberate collision. Rename and undo.
- Export to JPEG, PNG, and HEIC with quality, max dimensions, and metadata stripping. Choose a destination and verify progress and unique names.

## Drag and drop (external)

1. Select two or more tiles in Galeria.
2. Drag one selected tile to a Finder window. Verify both files and a stacked count badge, and verify the originals remain in the source folder.
3. Test a cross-volume destination. External drags must always copy; use Galeria's Move command to relocate files.
4. Drag to the Desktop, a browser page with `<input type=file multiple>`, and a Mail message body.
5. After a copy, the source folder must be unchanged. After a Galeria Move command, verify the grid loses the files via folder watching.
6. Drag from Quick Preview to a Finder window.
7. Drop images from Finder into Galeria and verify they are copied to the current folder without overwriting.

## Accessibility

- With VoiceOver, each tile announces filename, dimensions, selected state, rating, and flag.
- Use the tile's custom actions for Quick Look, Move to Trash, and Reveal in Finder.
- Check every toolbar button has a spoken label and a tooltip.
- Switch between light and dark appearance with and without Reduce Transparency/Motion.

## Settings and Help

- `⌘,` opens Settings. Check General, Images, Storage, Preview, and Smart tabs and that **Clear Cache** empties the reported size.
- Enable Vision indexing, wait for progress to finish, and search a content label.
- Open Help → Keyboard Shortcuts (`⇧⌘/`) and verify the window opens.
- Quit and relaunch; window state and last folder persist.
