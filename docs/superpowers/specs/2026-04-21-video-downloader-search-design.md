# Video Downloader — Search Tab

**Date:** 2026-04-21
**Status:** Approved

## Goal

Add an internal YouTube search to Video Downloader v1 so the user can type a song or title (e.g. "olympians fuck buttons") and download it without leaving the app.

## User experience

- New **Search** tab in `MainView`, first in the segmented picker (becomes the default landing tab).
- Search field at the top. On submit (return or 400 ms debounce), yt-dlp runs `ytsearch20:<query>` and returns up to 20 results.
- Each result row shows thumbnail, title, channel · duration · view count.
- Each row has two actions:
  - **Download MP3** (primary button) — one-click. Adds a `QueueItem` with `.audioMP3`, auto-starts downloads. Default path.
  - **▾ dropdown menu:**
    - **Download as…** → opens existing `FormatPickerSheet` pre-filled with the video URL (MP3/WAV/1080/720/480/Best/Custom).
    - **Add to Queue (paused)** → adds a `.queued` item without auto-starting. User goes to Queue tab and hits Download All when ready.

## Architecture

New files under `VideoDownloader/Search/`:

### `SearchResult.swift`
```
struct SearchResult: Identifiable, Sendable {
    let id: String              // yt-dlp "id" (video id)
    let title: String
    let channel: String?
    let durationSeconds: Double?
    let thumbnailURL: URL?
    let viewCount: Int?
    var videoURL: String { "https://www.youtube.com/watch?v=\(id)" }
}
```

### `YTDLPSearch.swift`
Static helpers, mirrors `YTDLPRunner` style:
- `search(query:) async throws -> [SearchResult]` — runs `yt-dlp "ytsearch20:<query>" --flat-playlist --dump-json --no-warnings`, captures stdout, parses line by line with `JSONDecoder`, skips malformed lines, returns results.
- `parse(_ stdout: String) -> [SearchResult]` — pure parser, unit-testable, no process.

### `SearchModel.swift`
```
@Observable
final class SearchModel {
    var query: String = ""
    var results: [SearchResult] = []
    var isSearching: Bool = false
    var error: String?
    func search() async        // runs current query
    func cancel()              // terminates in-flight process
}
```
Holds the running `Process` so cancel works. `search()` is idempotent: cancels any prior run.

### `SearchView.swift`
- `TextField` + search/cancel button.
- States: empty (hint), loading (ProgressView), error (red banner), results (List of rows), zero results ("No results for '…'").
- `@Environment(QueueModel.self)` to hand results off.

### `SearchResultRow.swift`
- Thumbnail (reuses `ThumbnailView`), title, metadata line, action buttons.
- Button handlers build `QueueItem(url:, title:, site: .youtube, format:, durationSeconds:, thumbnailURL:)` and either:
  - append + auto-start downloads (MP3 primary, Format-picker)
  - append + leave paused (Add to Queue)

### `MainView` changes
- Add `.search = "Search"` first in `Tab`, default to `.search`.

## Data flow

1. User types → `SearchModel.query` updates → `.task(id: query)` debounces 400 ms → calls `search()`.
2. `search()` sets `isSearching = true`, spawns yt-dlp subprocess.
3. Stdout captured, `YTDLPSearch.parse` converts JSON lines to `[SearchResult]`.
4. Results published on main actor, `isSearching = false`.
5. User clicks action → `QueueModel.add(QueueItem(...))` → auto-start or leave paused.
6. Download pipeline (existing) runs unchanged.

Because the `QueueItem` is constructed with the real title/channel/duration/thumbnail, queue and library show populated metadata immediately — no placeholder URL-as-title.

## Error handling

- yt-dlp non-zero exit → red banner with first ~200 chars of stderr.
- Zero parseable results → "No results for '<query>'".
- Empty query → no-op (search button disabled).
- In-flight search cancelled when a new search starts or tab switches.

## Testing

`VideoDownloaderTests/SearchTests.swift`:
- `parse` happy-path fixture (3 JSON lines) → 3 results with correct fields.
- Malformed JSON line skipped, valid lines still returned.
- Missing optional fields (no `channel`, no `duration`) → nil on `SearchResult`.
- `videoURL` constructs correctly from id.

No process/network tests.

## Out of scope

- Channel search, playlist search, filters (upload date, duration, 4K).
- Search history / saved searches.
- Multi-select + bulk download.
- Providers other than YouTube (yt-dlp's `ytsearch:` is YouTube-specific; other sites use their own URL paste flow).

## Versioning

Ships as `/Applications/Video Downloader v2.app` alongside existing v1.
