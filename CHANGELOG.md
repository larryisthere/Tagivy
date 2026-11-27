# Changelog

This file records user-visible changes across Tagivy and earlier FileFacet releases.

## [Unreleased]

## [1.0.18] - 2026-11-26

### Added

- Drag selected videos, a tag, or a smart filter from the library to Finder, video editors such as Premiere Pro, or other apps to copy or import the original files. A tag includes the videos of its subtags. Unavailable and offline videos are left out, and dragging into Finder copies the files instead of moving them. Videos that are still in iCloud are included, and the app that receives them downloads them. While a drag is outside Tagivy, the dragged image shows how many videos it exports and, if any, how many it leaves out.
- Export a tag, a smart filter, or selected videos to Premiere Pro, DaVinci Resolve, Final Cut Pro, or JianYing (剪映) with Export to Editing App in their shortcut menus. Premiere Pro and DaVinci Resolve share one XML item, and import the saved file as bins that follow the tag tree, with videos without tags in their own bin (in DaVinci Resolve, use Import > Media from File); Final Cut Pro imports the FCPXML file as an event with keywords and keyword collections; JianYing imports a timeline with the videos placed one after another. Each clip's tags also appear in its Log Note or notes, and the original videos are not changed. Videos still in iCloud are included; unavailable and offline videos, and videos whose length isn't known yet, are left out.
- Select one or more tags, or a smart filter, in the sidebar and press Delete or Command-Delete to delete them. Tags are deleted right away, and the notice that follows has an Undo button; deleting several tags at once is a single undo step. A smart filter still asks first.
- Notices that need no answer, such as a finished export, appear at the bottom of the window and show how long until they close. Pointing at a notice keeps it open.
- Tagivy checks for updates at launch and every hour. By default it downloads a new version in the background, then shows Relaunch to Install in the bottom-left corner of the window; if you don't relaunch, the update installs when you quit. Check for Updates in the Tagivy menu shows its progress in the same place. In Settings > Updates you can turn off automatic checks or background downloads, or choose to receive beta versions. Checking for updates is the only network access, and it goes through the updater rather than the app itself.
- If you run a beta, Receive beta versions in Settings > Updates is turned on for you, and stays on after an update to a release until you turn it off.
- Keyboard shortcuts for common commands, each listed in the menu bar. A new Video menu acts on the selected videos: Open (Command-O, or Command-Down Arrow in the grid), Quick Look (Command-Y), Show in Finder (Shift-Command-R), Copy Pathname (Option-Command-C, one path per line for several videos), Add Tags (Command-K, which opens the Inspector and puts the cursor in its tag field), Export to Editing App, and Remove from Library (Command-Delete). In the View menu, Command-3 and Command-4 show Untagged and Unavailable Videos; Zoom In (Command-+), Zoom Out (Command-−), and Actual Size (Command-0) change the thumbnail size; Control-Command-S and Option-Command-I show or hide the sidebar and Inspector; and the menu has Hide Toolbar and Enter Full Screen. In the File menu, Scan for New Videos is Command-R and Save as Smart Collection… is Command-S. The Window menu adds Zoom and Bring All to Front. Press Return on a selected tag or smart filter in the sidebar to rename it.

### Changed

- Tag changes in the Inspector take effect right away, without an Apply step.
- Inspector tags appear as capsules, in a List or Compact layout you can switch beside the search field.
- Switching videos no longer reloads the Inspector's tag list; the selection's tags slide to the top.
- Tag counts in the sidebar update right away and roll to their new value.
- Thumbnails that load later fade in instead of appearing abruptly.
- When resizing thumbnails changes how many fit in a row, they glide to their new positions instead of jumping.
- When you change filters or search, thumbnails that still match glide to their new positions, ones that no longer match fade out, and new matches fade in. Large changes switch at once, and with Reduce Motion on the grid crossfades instead.
- Changes in a filter's editor apply as you make them, so the editor no longer has Cancel, Done, or Remove buttons; press Return or Escape, or click outside it, to close it, and use the × on a filter to remove it. Untagged applies as soon as you choose it, without opening an editor.
- Date, duration, file size, and resolution filters use a slider that clicks into common values and otherwise slides freely, with a field beside it where you can type an exact value such as 90 s or 1.5 GB. Hold Option while dragging to slide past the common values.
- Duration, file size, and resolution filters take a minimum and a maximum, such as Duration 1–5 min or Resolution 1080p–4K. Drag either knob to the end of the slider, clear its field, type 0, or click the × beside it to leave that end open; if both ends are left open, the filter is removed when its editor closes. The file size slider starts at 1 MB. Filters saved earlier keep their minimum with no maximum. Resolution filters, grouping, and sorting treat portrait and widescreen videos like standard 16:9 ones: a portrait 1080 × 1920 video counts as 1080p, and a widescreen 3840 × 1608 video as 4K. Date filters keep a single value, labeled Within last.
- The update button in the bottom-left corner reads Install Update, Downloading Update, or Relaunch to Install without a version number, so it fits a narrow sidebar. Point at it to see which version it installs; VoiceOver reads the version too.
- Once an update is ready, Check for Updates… in the Tagivy menu becomes Relaunch to Install Update, so you can install it from the menu too.
- Settings uses the standard Mac layout: a toolbar with Import, Privacy, and Updates panes, a window that fits each pane, and help text under each option. Settings reopens on the pane you viewed last, and About Tagivy opens the standard About window. Betas show their beta number, such as 1.0.18 Beta 6 (Build 24), in Settings > Updates and in the About window.
- The View menu no longer shows Show Tab Bar, since Tagivy windows don't use tabs.
- In the grid's shortcut menu, Open, Show in Finder, and Copy Pathname (formerly Copy Full Path) act on all selected videos, the same as in the Video menu.

### Fixed

- Thumbnails that were already on screen no longer flash blank when a filter change reloads the grid.
- Libraries carried over from earlier versions no longer keep folders that can never be opened again. When every video in such a folder is also found through another folder, or the folder has no videos, Tagivy removes the folder at launch, so scanning no longer counts it as a folder it could not scan; the videos and their tags stay. To scan a removed folder again, add it again. Videos found only through such a folder stay listed as needing access, and are not retried in the background.
- When a different file replaces a video at the same location, the earlier video and its tags move to Unavailable instead of appearing available without a file.
- When the library cannot be loaded, the system log records only the error type and code, without file paths.
- Premiere Pro imports the XML file from Export to Editing App instead of refusing it.
- In Premiere Pro, exported clips arrive in a bin named after the exported tag or the saved file, with subtags as bins inside it, instead of loose in the project.
- Exporting a subtag to an editing app keeps the tags above it: its bin, or its keyword collection in Final Cut Pro, sits inside folders named after its parent tags. The export is named after the tag path, such as 旅行_海边.
- Save in the search bar is now disabled until you add a search, filter, or sort beyond the current tag or view, matching Clear.
- Command-A selects all videos in the grid, and Cut, Copy, Paste, and Select All work in text fields.
- Undo after creating, renaming, updating, or deleting a smart filter reverts that change, instead of an earlier, unrelated change such as an import.

## [1.0.17] - 2026-11-23

### Fixed

- Libraries that contain folders whose access record was never saved load again at startup instead of failing as a whole.
- Search, thumbnail size, and scan in the toolbar stay usable when the library cannot be loaded, and the library recovers from the error once it loads.

## [1.0.16] - 2026-11-23

### Fixed

- The Inspector keeps both tabs aligned with their header, and scrolling leaves room around the first and last rows.
- The library toolbar stays usable when optional library information cannot be loaded.
- Import and operation messages occupy space only while visible. Returning from Recently Added to All Videos no longer leaves a blur over the first thumbnails.

## [1.0.15] - 2026-11-23

### Changed

- Settings opens in a separate window and keeps its sidebar visible. Use Command-W to close the active window.
- The View menu includes controls for the library sidebar, Inspector, and thumbnail size.

### Fixed

- Undo while typing stays in the text field instead of undoing changes to the library.
- Empty search and filter results no longer suggest importing videos.
- Inspector help wraps in narrow panes, the library title aligns with the grid, and sidebar selection has more room around its icon.

## [1.0.14] - 2026-11-21

### Fixed

- Restoring access to a video at its original path no longer reads the video contents. Originals that only exist in iCloud can be associated without downloading them.
- Restore access from an enclosing folder and continue checking other records when a file location does not respond.

## [1.0.13] - 2026-11-21

### Changed

- The macOS app is now called Tagivy.
- Tagivy uses a new macOS app identity and starts with a separate local library. Existing FileFacet tags, preferences, thumbnails, and folder permissions are not imported automatically. Keep FileFacet if you still need your previous library.

## [1.0.12] - 2026-11-21

### Fixed

- Retried verification of protected videos after FileFacet regained authorized access, while preserving file identity checks.
- Kept the thumbnail badge and Inspector in sync when original files are unavailable, awaiting access verification, or not downloaded.
- Skipped known cloud placeholders during source recovery without requesting downloads.

## [1.0.11] - 2026-11-20

### Changed

- Replaced thumbnail status text badges with compact system icons, distinguishing iCloud originals that are not downloaded from unavailable videos and offline drives.
- Kept existing covers visible for iCloud placeholders and skipped those files during thumbnail generation without requesting downloads.

## [1.0.10] - 2026-11-20

### Fixed

- Kept background thumbnail work from being discarded by scans when the video and its source have not changed.
- Resumed thumbnail generation automatically when a temporarily unavailable video location becomes accessible again.

## [1.0.9] - 2026-09-21

### Added

- Added Restore Access to reconnect unavailable videos after confirming their original folders, with content verification, progress, and cancellation.

### Changed

- Kept All Videos and Recently Added first with Command-1 and Command-2. Untagged and Unavailable Videos appear only when nonempty and have no numeric shortcuts.
- Kept folders authorized for recovery separate from new-video scan scope.

### Fixed

- Verified original content before automatically reconnecting lost file associations through existing folder access.
- Prevented outdated background media results from replacing newer metadata or thumbnails.
- Prioritized visible videos when rebuilding missing thumbnails, reused existing media information, and reduced repeated cache scans.
- Loaded thumbnails in the background and updated individual cards to improve responsiveness and clear hover highlights promptly.
- Fixed relinking readable original videos rejected by AVFoundation's playability flag while retaining content and media checks.

## [1.0.8] - 2026-08-30

### Added

- Added on-demand scans for new videos in previously selected folders, with temporary Quick Look previews, selectable results, and optional folder access recovery for individually imported videos.

### Changed

- Completed scan sessions now close their temporary sidebar category and reveal every video added during the session in Recently Added; sessions containing an existing record reveal the handled videos in All Videos.
- Aligned tag-draft metadata, filter fields, and related action buttons with the native macOS text hierarchy.

### Fixed

- Fixed the Quick Look panel remaining visible with an empty selection after video playback ended and the user pressed Escape.
- Fixed scan results remaining onscreen when the user selected the already-active library category, compressed folder-import choices, and inconsistent singular scan feedback.
- Fixed long Inspector tag lists briefly compressing their row spacing while calculating the scrollable content size.

## [1.0.7] - 2026-08-07

### Added

- Added video-grid grouping by added, created, or modified date, duration, file size, and resolution, with independent group ordering, counts, collapsible sticky headers, and a direct clear control.
- Recently Added now temporarily groups videos by newest added date and restores the previous grouping preference when leaving the category.

### Fixed

- Sidebar names now use the available space up to their right-aligned counts, while counts remain fully visible in both selected and unselected rows.

## [1.0.6] - 2026-08-07

### Added

- Added a unified Unavailable Videos category for temporarily offline and inaccessible videos, with `Command-1` through `Command-4` shortcuts for the four preset library categories.
- Inaccessible videos can now be relinked to an original file or removed from FileFacet while retaining their tags, cached thumbnail, and media information until the user decides.

### Changed

- Completed imports now select and reveal every video handled by the batch: new-only batches open Recently Added, while batches containing existing records open All Videos.
- Recently Added now uses a fixed newest-first system ordering without changing user sorting in other categories; manually changing categories also starts at the top with no video selected.
- Finished notifications now include a close control, and removal undo expires when the browsing context changes, a new import begins, or the notification is dismissed.
- Videos confirmed outside their known location or moved to the Trash now leave active library results and remain available for recovery; relinking only proceeds automatically when the complete content fingerprint matches.

## [1.0.5] - 2026-07-31

### Added

- Added a visible rule bar for combining filename, tag, untagged, date, duration, file-size, and resolution filters with “match all” or “match any” relationships.
- Added sorting by filename, added, created, or modified date, duration, file size, and resolution.
- Added saved Smart Collections with live result counts, rule preview, revert, update, save-as, inline rename, and deletion.
- Added `Command-F` for filename search and `Shift-Command-F` for adding a filter condition.
- The Inspector now groups container, video-codec, audio-codec, profile, rate, depth, color, and rotation source information while keeping cached details available for offline videos.

### Changed

- Search, filters, and sorting now remain within the selected system category or tag scope, and filter editors apply their draft once after confirmation.
- Thumbnail generation now falls back to Quick Look when AVFoundation cannot extract a frame; files unsupported by both macOS media paths continue to use the generic video icon.

### Fixed

- Pressing Escape now cancels inline renaming for tags and Smart Collections, while Return or focus loss saves a valid name consistently.

## [1.0.4] - 2026-07-31

### Added

- Folder imports can now create hierarchical FileFacet tags from the directory structure, with an optional root tag for each selected folder.
- Added a shared folder-import preference for the File menu, `Shift-Command-I`, and Finder drops, including “Ask Every Time” and an option to remember the chosen method.
- Videos on disconnected external drives now remain visible, searchable, and taggable with their cached thumbnails and metadata. FileFacet marks them as offline, provides a dedicated Offline collection, and restores file access automatically when an authorized drive reconnects.

### Changed

- Finder aliases, symbolic links, and macOS packages are skipped consistently when importing folders.

## [1.0.3] - 2026-07-30

### Added

- Added complete English and Simplified Chinese localization across menus, the library, import flows, tag management, settings, App Lock, errors, tooltips, and accessibility labels.
- FileFacet now follows the language configured in macOS, including the per-app language setting, and falls back to English for unsupported languages.

### Fixed

- Corrected library video-count subtitles and English singular/plural feedback for overlapping imports, removing videos, and restoring videos.

## [1.0.2] - 2026-07-18

### Changed

- “Import Videos and Folders…” accepts multiple videos, multiple folders, or a mixture in one selection, using the same import scope and processing rules as drag and drop.
- Sidebar tags can be sorted manually, by name, or by unique video count in descending order. Parent counts include all descendants, tag hierarchy remains editable while automatic sorting is active, and switching back to manual sorting restores the saved order.

## [1.0.1] - 2026-07-17

### Changed

- Published the source under the MIT License and added public build instructions, privacy boundaries, and a security-reporting entry point.
- Added GitHub Actions build checks and the GitHub Release publishing workflow.

### Fixed

- Fixed the sidebar tag group failing to collapse and expand again.

## [1.0.0] - 2026-07-16

### Initial Release

- Import videos from multiple folders, or drag multiple videos, multiple folders, or a mixture into the content area. The unified library recognizes files that were already imported.
- Import Finder tags once when a video first enters the library, then manage top-level and hierarchical tags independently in FileFacet.
- Create, rename, move, merge, and batch-select tags, assign them by dragging, apply edits later, and undo the last change.
- Browse a native three-column layout with a video grid, search, built-in categories, tag filters, details, and a remembered thumbnail size.
- Preview with Quick Look, open videos in the default player, reveal them in Finder, and copy file paths or names.
- Remove one or more videos from the library with the context menu or `Command-Delete`, keep the original files, and undo the removal.
- Keep removal undo available across imports. If the same original video was reimported, undo merges the records and restores its tags. Expired undo cleanup removes unreferenced thumbnails and file authorizations, while failed removals preserve pending tag edits.
- Protect the library with an optional authentication setting, privacy cover, idle locking, and macOS system authentication.
- Open Settings with the app menu or `Command-,` in a dedicated main-window workspace. The app-menu About command opens the About section and shows the current version and build.
- Maintain imported video locations and deletion state silently; newly discovered videos always require manual import.

### Fixed

- Fixed the inline field disappearing immediately after creating a tag from the sidebar.
- Fixed dragging multiple selected tags moving only one tag.
- Fixed an old search query remaining active after import and hiding videos after selecting another tag.
- Unified import progress, cancellation, and results below the content title so completed results no longer occupy the window title.
- Added stage and batch progress for multi-file drops, while continuing with remaining files after one file fails.
- Used the system copy or prohibited cursor while videos are dragged over the content area, keeping the grid fully visible.
- Fixed temporary sandbox URLs from Finder drops being mistaken for failures to establish persistent access.
- Merged overlapping parent folders, child folders, and contained files, with separate feedback for empty folders, processing failures, and unreadable items.
