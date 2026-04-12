# Video Downloader v1 — Design Spec

**Date:** 2026-04-12
**Project location:** `/Volumes/1tb /claude code projects /Projects/video-downloader/`
**Build output:** `/Applications/Video Downloader v1.app`
**Downloads folder:** `/Volumes/1tb /claude code projects /youtube-downloads/`

## Purpose

A standalone macOS app for downloading YouTube and Vimeo videos with quality options, audio-only extraction, a folder-based library for downloaded media, and a one-click hand-off to the existing Transcription Engine app for SRT/VTT captions.

Replaces ad-hoc `yt-dlp` CLI use with a visual queue, playlist handling, quality selection, and integrated transcription pipeline.

## Architecture

### Platform
- **macOS SwiftUI app**, single window with two tabs: **Queue** and **Library**
- Swift 6, macOS 14+
- `Process` subprocess calls to bundled `yt-dlp` and `ffmpeg` binaries

### Bundled binaries
- `yt-dlp` and `ffmpeg` are bundled inside the `.app` at `Resources/bin/`
- On first launch, copied to `~/Library/Application Support/VideoDownloader/bin/` (writable location required for yt-dlp self-update)
- On every launch: `yt-dlp -U` runs silently in background (non-blocking; UI remains responsive)
- yt-dlp's YouTube extractor breaks frequently — auto-update is the reason for bundling over Homebrew dependency

### File layout
```
/Volumes/1tb /claude code projects /youtube-downloads/
  ├── Video Title.mp4
  ├── Video Title.mp4.meta.json
  ├── Video Title.jpg              ← thumbnail
  ├── Another Video.webm
  ├── Another Video.webm.meta.json
  └── Another Video.jpg
```

### Sidecar JSON format
```json
{
  "schemaVersion": 1,
  "title": "Living with Synchronicity",
  "url": "https://www.youtube.com/watch?v=-GPVHHStUfg",
  "site": "youtube",
  "uploader": "...",
  "duration": 3612,
  "format": "bestvideo+bestaudio",
  "formatLabel": "Best",
  "fileSize": 141557760,
  "fileName": "Living with Synchronicity.webm",
  "thumbnailFile": "Living with Synchronicity.jpg",
  "dateAdded": "2026-04-12T15:30:00Z",
  "description": "...",
  "mediaFilePath": null,
  "importedFromPath": null
}
```

`importedFromPath` is populated only for imported files.

## Queue tab

### Input
- URL paste box + "Add to Queue" button
- If URL is:
  - **Single video** (YouTube watch URL, Vimeo video URL) → one queue row
  - **YouTube playlist** (`/playlist?list=...` or watch URL with `&list=`) → fetches playlist metadata via `yt-dlp --flat-playlist --print-json`, expands to N queue rows
  - **Vimeo showcase** → same flat-playlist treatment
- Supports pasting multiple lines if user enters several URLs at once (each line resolved independently)

### Queue row
Each row shows: thumbnail, title, duration, source site icon, format dropdown, remove button (✕).

Format dropdown options:
- **Best** — `bestvideo+bestaudio/best` (default)
- **1080p** — `bestvideo[height<=1080]+bestaudio/best[height<=1080]`
- **720p** — `bestvideo[height<=720]+bestaudio/best[height<=720]`
- **480p** — `bestvideo[height<=480]+bestaudio/best[height<=480]`
- **Audio — MP3 (320 kbps)** — `bestaudio` + ffmpeg MP3 CBR 320
- **Audio — WAV (16-bit/44.1kHz)** — `bestaudio` + ffmpeg WAV PCM s16le
- **Custom…** — opens format-picker sheet (see below)

### Custom format sheet
- Runs `yt-dlp -F <url>` and parses the format table
- Shows a list with columns: format ID, resolution, codec, bitrate, container, filesize
- User picks one row, hit Apply → queue row's format is set to that specific format ID
- Can be reopened to change selection

### Queue controls
- **Download All** — runs the queue sequentially (one download at a time to avoid rate-limiting)
- **Cancel** on an in-flight row → sends SIGTERM to yt-dlp subprocess, removes row
- Rows can be removed before download starts (to trim a 12-video playlist down to 7)
- On completion: file + thumbnail + sidecar JSON written to downloads folder, row is removed from Queue and appears in Library

### Progress
Each downloading row shows a progress bar parsed from yt-dlp stdout (`[download] 45.2% of 98.84MiB at 4.90MiB/s ETA 01:45`), plus current speed and ETA.

## Library tab

### View
- Toggle between grid (thumbnails, 3-4 columns) and list (rows with metadata columns)
- Sort: Date added (default, newest first), Title, Duration, File size
- Search box filters by title or URL (substring match)

### Library item
Displays: thumbnail, title, duration, source site icon (YouTube/Vimeo/Import), date added, format label, file size.

### Row/item actions
- **▶ Preview** — QuickLook (`QLPreviewPanel`) to play inline without leaving the app
- **📝 Send to Transcription Engine** — launches `/Applications/Transcription Engine v5.app` with the file URL as an open-file argument (see hand-off section)
- **📁 Show in Finder** — `NSWorkspace.selectFile`
- **🗑 Delete** — confirmation prompt; trashes video, sidecar JSON, and thumbnail to macOS Trash (not `rm`; user can recover)

### Library population
- On app launch: scans downloads folder for `*.meta.json` files, builds library list
- On queue completion: new item appears without rescan (in-memory add)
- On Import: new sidecar written, appears in library
- No database — folder scan is the source of truth, so reorganizing files in Finder doesn't desync

## Import feature

### Entry points
- **Import… menu item** (File → Import…) — opens NSOpenPanel, multi-select for video/audio files
- **Drag-and-drop** onto the Library tab

### Import dialog
Shows after file selection (or drop):
- List of files being imported
- Checkbox: **"Copy into library folder"** (default OFF — keep files in place)
  - **Checked** → copies file into `/Volumes/1tb /claude code projects /youtube-downloads/`, writes sidecar + thumbnail there, original untouched
  - **Unchecked** → leaves file in place; sidecar JSON + thumbnail still written to the library folder (`/Volumes/1tb /claude code projects /youtube-downloads/`) with an absolute `mediaFilePath` pointing at the external file
- For each imported file: extracts duration and generates a thumbnail via ffmpeg (`-ss 00:00:05 -vframes 1`)
- `url` field in sidecar is `null`, `site` is `"import"`, `importedFromPath` is the original absolute path

**Why sidecar always lives in library folder:** keeps folder-scan model intact — the library doesn't need a separate index of external references, it just scans one directory.

### Orphan handling
If a referenced-in-place file is moved/deleted outside the app: library item shows a warning badge and offers "Locate file…" or "Remove from library".

## Transcription Engine hand-off

### Mechanism
- "Send to Transcription Engine" button calls `NSWorkspace.shared.open(fileURLs:withApplicationAt:configuration:)` targeting `/Applications/Transcription Engine v5.app` with the media file URL
- macOS dispatches this to TE's `application(_:open:)` NSApplicationDelegate method

### Required Transcription Engine update
TE must handle the open-file event. If it doesn't already:
- Add `application(_:open urls: [URL])` to `TranscriptionEngineApp` delegate
- On open: load the first URL into the current transcription view, populate the file path, enable Transcribe button
- Register supported file types in `Info.plist` `CFBundleDocumentTypes`: `.mp4`, `.webm`, `.mkv`, `.mov`, `.mp3`, `.wav`, `.m4a`, `.aac`

A small patch to TE is included as part of this project's scope. After the patch, TE is rebuilt as **Transcription Engine v6** in `/Applications/`.

### Fallback
If TE is not found at expected path, show alert: "Transcription Engine not found at /Applications/Transcription Engine v*.app. Install or update Transcription Engine to continue."

## Auto-update flow

On app launch, in a background task:
1. Check if `~/Library/Application Support/VideoDownloader/bin/yt-dlp` exists; if not, copy from bundle
2. Run `yt-dlp -U` with 30-second timeout
3. Log result to Console (not shown in UI unless error)

Failure modes:
- No network → silent skip (existing binary still works)
- Update fails → log, continue with existing binary

## Project structure

```
/Volumes/1tb /claude code projects /Projects/video-downloader/
  ├── VideoDownloader.xcodeproj
  ├── VideoDownloader/
  │   ├── App/
  │   │   └── VideoDownloaderApp.swift
  │   ├── Queue/
  │   │   ├── QueueView.swift
  │   │   ├── QueueModel.swift
  │   │   ├── QueueRow.swift
  │   │   └── FormatPickerSheet.swift
  │   ├── Library/
  │   │   ├── LibraryView.swift
  │   │   ├── LibraryModel.swift
  │   │   ├── LibraryItem.swift
  │   │   └── ImportSheet.swift
  │   ├── Backend/
  │   │   ├── YTDLPRunner.swift     ← subprocess wrapper + progress parser
  │   │   ├── FFmpegRunner.swift    ← audio extraction, thumbnail generation
  │   │   ├── PlaylistResolver.swift ← --flat-playlist expansion
  │   │   ├── FormatProbe.swift     ← yt-dlp -F parser
  │   │   └── Updater.swift         ← yt-dlp -U on launch
  │   ├── Model/
  │   │   ├── MediaItem.swift       ← shared model for queue + library
  │   │   └── SidecarJSON.swift     ← read/write .meta.json
  │   ├── Transcription/
  │   │   └── TranscriptionEngineLauncher.swift
  │   └── Resources/
  │       ├── bin/
  │       │   ├── yt-dlp            ← bundled binary
  │       │   └── ffmpeg            ← bundled binary
  │       └── Assets.xcassets
  ├── docs/
  │   └── superpowers/
  │       └── specs/
  │           └── 2026-04-12-video-downloader-design.md
  └── README.md
```

## Error handling

- **yt-dlp subprocess failure:** parse stderr, show error in queue row with "Retry" button
- **Disk full:** check free space on 1tb drive before each download; if <2GB free, warn user before starting
- **1tb drive not mounted:** on launch, verify `/Volumes/1tb /claude code projects /` exists; if not, show blocking alert "Please connect the 1tb drive to continue"
- **TE missing:** alert with path hint
- **Playlist fetch failure:** show alert, no queue rows added
- **Corrupt sidecar JSON:** skip the file during library scan, log warning

## Testing strategy

Integration smoke tests (not unit-test-heavy; this is a subprocess-wrapper app where mocking yt-dlp provides little value):
- Download single YouTube video at 720p → verify file, sidecar, thumbnail exist
- Download YouTube playlist (small, ≤3 videos) → verify queue expansion and all completions
- Download Vimeo video at Best → verify format
- Extract MP3 from YouTube video → verify audio-only file + correct bitrate
- Import existing file (both copy and reference modes) → verify sidecar
- Send file to Transcription Engine → verify TE launches and loads the file
- Delete library item → verify all 3 files trashed

## Out of scope (for v1)

- Built-in video player with scrubbing (QuickLook covers preview needs)
- Tags, collections, smart folders
- Resume interrupted downloads across app restarts (yt-dlp handles mid-download resume; we don't persist queue state across launches)
- Concurrent downloads (sequential only)
- Re-download at different quality from library
- Download history / re-download detection
- Metadata editing

These can be added in v2 based on real usage.

## Decisions summary

| Decision | Choice |
|---|---|
| Library scope | Minimal (folder-scan + sidecar JSON) |
| Quality UI | Presets + Custom format picker |
| Transcription hand-off | Launch TE with file argument |
| Binaries | Bundled + auto-update on launch |
| Download entry | Single URL + playlist expansion + per-item remove |
| Audio formats | MP3 320 + WAV 16-bit/44.1kHz |
| Library storage | Folder scan + sidecar JSON |
| Import | Per-import choice (copy vs reference) |
