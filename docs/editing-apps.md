English | [简体中文](editing-apps.zh-CN.md)

# Use Tagivy videos in editing apps

Tagivy never moves or copies your videos. It tells an editing app which videos to use and where they are. There are two ways to hand videos over:

| Method | Works with | What comes across |
|---|---|---|
| **Export to Editing App** | Premiere Pro, DaVinci Resolve, Final Cut Pro, JianYing (剪映) | The video files plus your tag structure (bins or keywords), and a timeline for some apps |
| **Drag and drop** | Any app that accepts files, including iMovie and CapCut | The video files only |

## Supported editing apps

| App | Export menu item | What you get after importing |
|---|---|---|
| Final Cut Pro | Final Cut Pro (.fcpxml)… | An event with one keyword collection per tag |
| Adobe Premiere Pro | Premiere Pro (.xml)… | Bins nested by tag |
| DaVinci Resolve | DaVinci Resolve (.xml)… | Bins nested by tag, plus a timeline with every video |
| JianYing (剪映) | CapCut (.fcpxml)… | A timeline with every video (JianYing has no bins) |
| iMovie, CapCut and other apps | Drag and drop | The video files |

## Export

Control-click a tag, several selected tags, a smart filter, or selected videos, choose **Export to Editing App**, pick the app, and save the file.

- Your tag tree comes across: each tag becomes a bin (a keyword in Final Cut Pro), with its child tags nested inside. When you export a child tag, its parent tags come along as the outer bins, and the file is named after the full tag path, such as `People_Alex`.
- Every clip's tags are also written into its notes, so you can search for them in the editing app.
- Videos that are unavailable right now, for example on a disconnected drive, and videos whose length Tagivy hasn't read yet are skipped. Tagivy tells you how many when the export finishes.
- iCloud videos that aren't downloaded yet are exported as usual. The editing app downloads them when it needs them.

## Final Cut Pro

1. Open the library you want to use, choose **File › Import › XML…**, and select the exported .fcpxml file.
2. The videos appear in a new event, with keyword collections under it for your tags.

## Adobe Premiere Pro

1. Choose **File › Import…** (⌘I) and select the exported .xml file.
2. A bin appears in the Project panel with your tags nested inside.
3. If clips show as offline, Control-click them, choose **Link Media…**, and point to the folder that holds the videos.

## DaVinci Resolve

Resolve can import the file in two ways, depending on what you need.

**Clips only (bins)**

1. Choose **File › Import › Media from File…** and select the exported .xml file.
2. Bins nested by tag appear in the Media Pool.

**Clips and a timeline**

1. Choose **File › Import › Timeline…** (⇧⌘I) and select the exported .xml file.
2. In the Load XML window, keep the default settings, including **Mixed frame rate format: Final Cut Pro 7**, and click **Ok**.
3. The bins and a timeline appear in the Media Pool.

**If the Mac App Store version can't find the clips**

The Mac App Store version of Resolve can only read folders you have allowed, so the first import may say the clips "were not yet found".

1. Open **DaVinci Resolve › Settings › System › Media Storage**, click **Add**, choose the folder that holds your videos (a parent folder covers its subfolders), and save.
2. Import again. If Resolve still can't find the clips, click **Yes** in the dialog and choose the folder you added.

The version downloaded from Blackmagic's website doesn't have this limit.

## JianYing (剪映)

JianYing, the China edition of CapCut, imports timelines only and has no bins, so Tagivy writes a separate file with a timeline for it.

1. On the JianYing home screen, choose **更多 › 导入PR或FCP工程** (More › Import PR or FCP Project) and select the exported .fcpxml file.
2. JianYing creates a new project with all the videos placed end to end on the timeline.

The international edition of CapCut can't import projects from other apps, so use drag and drop with it.

## iMovie, CapCut and other apps

iMovie can't import XML or project files from other apps, so use drag and drop:

1. Select videos in Tagivy (use tags or a smart filter to narrow them down first).
2. Drag them onto an iMovie event or timeline.

This works with any other app that accepts files. Drag and drop brings the video files only, without the tag structure.
