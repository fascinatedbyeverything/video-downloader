# Spotify Playlist Capture — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Spotify playlist URL → per-track WAV + MP3 320 capture as a first-class fourth URL type alongside YouTube/Vimeo, accessible via a new "Spotify" tab.

**Architecture:** Real-time capture pipeline parallel to the existing yt-dlp pipeline. Drives Spotify.app via AppleScript, captures Spotify's process audio via CoreAudio Process Tap (macOS 14.2+), segments by `com.spotify.client.PlaybackStateChanged` distributed notifications, encodes to WAV (PCM passthrough) + MP3 320 (system ffmpeg) with ID3 tags. Public playlists scraped for upfront metadata; private playlists discover-as-played.

**Tech Stack:** Swift 6, SwiftUI, AppleScript via NSAppleScript, CoreAudio Process Tap, NSDistributedNotificationCenter, AVAudioFile (WAV), ffmpeg subprocess (MP3 + ID3).

**Spec:** `docs/superpowers/specs/2026-05-04-spotify-capture-design.md`

---

## File Structure

**New files (UI):**
- `VideoDownloader/Spotify/SpotifyTabModel.swift` — `@Observable` state machine
- `VideoDownloader/Spotify/SpotifyTabView.swift` — tab root view
- `VideoDownloader/Spotify/SpotifyPreviewView.swift` — playlist preview + Start Capture button
- `VideoDownloader/Spotify/SpotifyCaptureView.swift` — live capture progress UI

**New files (Backend):**
- `VideoDownloader/Backend/Spotify/SpotifyURL.swift` — URL → URI parsing
- `VideoDownloader/Backend/Spotify/SpotifyMetadataScraper.swift` — public playlist HTML scrape
- `VideoDownloader/Backend/Spotify/SpotifyAppController.swift` — AppleScript wrapper
- `VideoDownloader/Backend/Spotify/SpotifyPlaybackObserver.swift` — NSDistributedNotificationCenter subscription
- `VideoDownloader/Backend/Spotify/SpotifyAudioCaptureRunner.swift` — CoreAudio Process Tap
- `VideoDownloader/Backend/Spotify/SpotifyTrackSegmenter.swift` — wires capture + events
- `VideoDownloader/Backend/Spotify/SpotifyEncoder.swift` — WAV + MP3 + ID3 writer
- `VideoDownloader/Backend/Spotify/SpotifyTrack.swift` — track metadata model

**Modified files:**
- `project.yml` — deployment target 14.0 → 14.2; add automation entitlement
- `VideoDownloader/Model/SiteSource.swift` — add `.spotify`
- `VideoDownloader/Backend/URLClassifier.swift` — recognize spotify URLs
- `VideoDownloader/App/MainView.swift` — add 4th tab

**New tests:**
- `VideoDownloaderTests/SpotifyURLTests.swift`
- `VideoDownloaderTests/SpotifyMetadataScraperTests.swift` (with HTML fixtures)
- `VideoDownloaderTests/SpotifyTrackSegmenterTests.swift`
- `VideoDownloaderTests/Fixtures/spotify_playlist_public.html` (captured fixture)

---

## Task 1: Bump deployment target and add automation entitlement

**Files:**
- Modify: `project.yml`
- Create: `VideoDownloader/VideoDownloader.entitlements`

- [ ] **Step 1: Edit project.yml — bump macOS deployment target to 14.2**

In `project.yml`, change:
```yaml
options:
  deploymentTarget:
    macOS: "14.0"
```
to:
```yaml
options:
  deploymentTarget:
    macOS: "14.2"
```

And update `MACOSX_DEPLOYMENT_TARGET` in `settings.base`:
```yaml
MACOSX_DEPLOYMENT_TARGET: "14.2"
```

- [ ] **Step 2: Create entitlements file with automation + audio capture**

Create `VideoDownloader/VideoDownloader.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
    <key>com.apple.security.scripting-targets</key>
    <dict>
        <key>com.spotify.client</key>
        <array>
            <string>com.spotify.client.playback</string>
        </array>
    </dict>
</dict>
</plist>
```

- [ ] **Step 3: Reference entitlements in project.yml**

In `project.yml` under `targets.VideoDownloader.settings.base`, add:
```yaml
CODE_SIGN_ENTITLEMENTS: VideoDownloader/VideoDownloader.entitlements
```

Also add `INFOPLIST_KEY_NSAppleEventsUsageDescription`:
```yaml
INFOPLIST_KEY_NSAppleEventsUsageDescription: "Video Downloader controls the Spotify app to play and capture playlists you choose."
```

- [ ] **Step 4: Regenerate Xcode project and verify build**

```bash
cd "/Volumes/fbe ebosuite live 18tb/Projects/video-downloader"
xcodegen
xcodebuild -project VideoDownloader.xcodeproj -scheme VideoDownloader -configuration Debug \
  -derivedDataPath "/Volumes/1tb /claude code projects /DerivedData/VideoDownloader" \
  build
```
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add project.yml VideoDownloader/VideoDownloader.entitlements
git commit -m "chore: bump deployment to 14.2, add automation entitlement for spotify

Required for CoreAudio Process Tap API (14.2+) and AppleScript control
of com.spotify.client."
```

---

## Task 2: Extend SiteSource and URLClassifier (TDD)

**Files:**
- Modify: `VideoDownloader/Model/SiteSource.swift`
- Modify: `VideoDownloader/Backend/URLClassifier.swift`
- Create: `VideoDownloaderTests/URLClassifierSpotifyTests.swift`

- [ ] **Step 1: Write failing test for Spotify URL classification**

Create `VideoDownloaderTests/URLClassifierSpotifyTests.swift`:
```swift
import XCTest
@testable import VideoDownloader

final class URLClassifierSpotifyTests: XCTestCase {
    func test_classify_spotifyPlaylistHTTPS() {
        let url = "https://open.spotify.com/playlist/0sooekw4rFNXqCeOOVGtqY"
        XCTAssertEqual(URLClassifier.classify(url), .spotifyPlaylist)
    }

    func test_classify_spotifyPlaylistWithQuery() {
        let url = "https://open.spotify.com/playlist/0sooekw4rFNXqCeOOVGtqY?si=0fd0e99f38ca4702"
        XCTAssertEqual(URLClassifier.classify(url), .spotifyPlaylist)
    }

    func test_classify_spotifyURIPlaylist() {
        let url = "spotify:playlist:0sooekw4rFNXqCeOOVGtqY"
        XCTAssertEqual(URLClassifier.classify(url), .spotifyPlaylist)
    }

    func test_classify_spotifyTrackNotPlaylist() {
        let url = "https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh"
        XCTAssertEqual(URLClassifier.classify(url), .spotifyTrack)
    }

    func test_siteSource_isSpotifyForPlaylistAndTrack() {
        XCTAssertEqual(URLClassification.spotifyPlaylist.siteSource, .spotify)
        XCTAssertEqual(URLClassification.spotifyTrack.siteSource, .spotify)
    }
}
```

- [ ] **Step 2: Run test — verify it fails**

```bash
xcodebuild -project VideoDownloader.xcodeproj -scheme VideoDownloader \
  -derivedDataPath "/Volumes/1tb /claude code projects /DerivedData/VideoDownloader" \
  test -only-testing:VideoDownloaderTests/URLClassifierSpotifyTests
```
Expected: build/compile failure (`.spotifyPlaylist` / `.spotify` not defined).

- [ ] **Step 3: Add `.spotify` to SiteSource**

Read current `VideoDownloader/Model/SiteSource.swift` and add `.spotify` case alongside `.youtube`, `.vimeo`, `.other`:
```swift
case spotify
```
Update any switch statements to handle `.spotify` (e.g. display name → "Spotify").

- [ ] **Step 4: Extend URLClassifier**

In `VideoDownloader/Backend/URLClassifier.swift`:

Add cases to `URLClassification` enum:
```swift
case spotifyPlaylist
case spotifyTrack
```

Update `siteSource` switch:
```swift
case .spotifyPlaylist, .spotifyTrack: return .spotify
```

Update `isPlaylist`:
```swift
case .youtubePlaylist, .vimeoShowcase, .spotifyPlaylist: return true
```

Add classification logic in `classify(_:)` after the Vimeo block:
```swift
if lowercasedHost.contains("open.spotify.com") || lowercasedHost.contains("spotify.com") {
    if path.contains("/playlist/") { return .spotifyPlaylist }
    if path.contains("/track/") { return .spotifyTrack }
    return .unknown
}
// spotify: URI scheme
if scheme.lowercased() == "spotify" {
    let raw = trimmed.lowercased()
    if raw.contains(":playlist:") { return .spotifyPlaylist }
    if raw.contains(":track:") { return .spotifyTrack }
    return .unknown
}
```

Note: `URLComponents` does not parse `spotify:` cleanly; the existing classifier uses `URL(string:)`. For `spotify:playlist:...`, `URL.scheme` is `"spotify"` but `URL.host` is empty. Adjust the early `host` guard so `spotify:` URIs aren't rejected as `.invalid`. Replace:
```swift
guard let url = URL(string: trimmed),
      let scheme = url.scheme, !scheme.isEmpty,
      let host = url.host, !host.isEmpty else {
    return .invalid
}
```
with:
```swift
guard let url = URL(string: trimmed),
      let scheme = url.scheme, !scheme.isEmpty else {
    return .invalid
}
let host = url.host ?? ""
if host.isEmpty && scheme.lowercased() != "spotify" {
    return .invalid
}
```

- [ ] **Step 5: Run tests — verify pass**

```bash
xcodebuild -project VideoDownloader.xcodeproj -scheme VideoDownloader \
  -derivedDataPath "/Volumes/1tb /claude code projects /DerivedData/VideoDownloader" \
  test -only-testing:VideoDownloaderTests/URLClassifierSpotifyTests
```
Expected: 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add VideoDownloader/Model/SiteSource.swift VideoDownloader/Backend/URLClassifier.swift VideoDownloaderTests/URLClassifierSpotifyTests.swift
git commit -m "feat: classify spotify playlist/track URLs"
```

---

## Task 3: SpotifyURL helper (URI normalization)

**Files:**
- Create: `VideoDownloader/Backend/Spotify/SpotifyURL.swift`
- Create: `VideoDownloaderTests/SpotifyURLTests.swift`

- [ ] **Step 1: Write failing test**

Create `VideoDownloaderTests/SpotifyURLTests.swift`:
```swift
import XCTest
@testable import VideoDownloader

final class SpotifyURLTests: XCTestCase {
    func test_playlistURI_fromHTTPS() {
        let r = SpotifyURL.parse("https://open.spotify.com/playlist/0sooekw4rFNXqCeOOVGtqY?si=abc")
        XCTAssertEqual(r?.uri, "spotify:playlist:0sooekw4rFNXqCeOOVGtqY")
        XCTAssertEqual(r?.kind, .playlist)
        XCTAssertEqual(r?.id, "0sooekw4rFNXqCeOOVGtqY")
    }

    func test_playlistURI_fromSpotifyScheme() {
        let r = SpotifyURL.parse("spotify:playlist:0sooekw4rFNXqCeOOVGtqY")
        XCTAssertEqual(r?.uri, "spotify:playlist:0sooekw4rFNXqCeOOVGtqY")
    }

    func test_trackURI_fromHTTPS() {
        let r = SpotifyURL.parse("https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh")
        XCTAssertEqual(r?.uri, "spotify:track:4iV5W9uYEdYUVa79Axb7Rh")
        XCTAssertEqual(r?.kind, .track)
    }

    func test_publicWebURL_forPlaylist() {
        let r = SpotifyURL.parse("spotify:playlist:0sooekw4rFNXqCeOOVGtqY")
        XCTAssertEqual(r?.publicWebURL, "https://open.spotify.com/playlist/0sooekw4rFNXqCeOOVGtqY")
    }

    func test_garbageReturnsNil() {
        XCTAssertNil(SpotifyURL.parse("https://example.com/foo"))
        XCTAssertNil(SpotifyURL.parse(""))
    }
}
```

- [ ] **Step 2: Run test — verify fail**

```bash
xcodebuild -project VideoDownloader.xcodeproj -scheme VideoDownloader \
  -derivedDataPath "/Volumes/1tb /claude code projects /DerivedData/VideoDownloader" \
  test -only-testing:VideoDownloaderTests/SpotifyURLTests
```
Expected: compile failure (`SpotifyURL` undefined).

- [ ] **Step 3: Implement SpotifyURL**

Create `VideoDownloader/Backend/Spotify/SpotifyURL.swift`:
```swift
import Foundation

struct SpotifyURL: Equatable {
    enum Kind: String { case playlist, track, album, artist }

    let kind: Kind
    let id: String

    var uri: String { "spotify:\(kind.rawValue):\(id)" }
    var publicWebURL: String { "https://open.spotify.com/\(kind.rawValue)/\(id)" }

    static func parse(_ input: String) -> SpotifyURL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // spotify:KIND:ID
        if trimmed.lowercased().hasPrefix("spotify:") {
            let parts = trimmed.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3,
                  let kind = Kind(rawValue: String(parts[1]).lowercased()) else { return nil }
            let id = String(parts[2])
            guard isValidID(id) else { return nil }
            return SpotifyURL(kind: kind, id: id)
        }

        // https://open.spotify.com/KIND/ID(?si=...)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased(),
              host.contains("spotify.com") else { return nil }

        let comps = url.path.split(separator: "/").map(String.init)
        guard comps.count >= 2,
              let kind = Kind(rawValue: comps[0].lowercased()) else { return nil }
        let id = comps[1]
        guard isValidID(id) else { return nil }
        return SpotifyURL(kind: kind, id: id)
    }

    private static func isValidID(_ id: String) -> Bool {
        // Spotify IDs are base62 strings, typically 22 chars
        guard id.count >= 16, id.count <= 32 else { return false }
        return id.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
```

- [ ] **Step 4: Run tests — verify pass**

```bash
xcodebuild -project VideoDownloader.xcodeproj -scheme VideoDownloader \
  -derivedDataPath "/Volumes/1tb /claude code projects /DerivedData/VideoDownloader" \
  test -only-testing:VideoDownloaderTests/SpotifyURLTests
```
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add VideoDownloader/Backend/Spotify/SpotifyURL.swift VideoDownloaderTests/SpotifyURLTests.swift
git commit -m "feat: SpotifyURL parser for HTTPS and spotify: URI forms"
```

---

## Task 4: SpotifyTrack model + SpotifyMetadataScraper (TDD with HTML fixture)

**Files:**
- Create: `VideoDownloader/Backend/Spotify/SpotifyTrack.swift`
- Create: `VideoDownloader/Backend/Spotify/SpotifyMetadataScraper.swift`
- Create: `VideoDownloaderTests/SpotifyMetadataScraperTests.swift`
- Create: `VideoDownloaderTests/Fixtures/spotify_playlist_public.html` (captured manually)

- [ ] **Step 1: Define SpotifyTrack and SpotifyPlaylistMetadata**

Create `VideoDownloader/Backend/Spotify/SpotifyTrack.swift`:
```swift
import Foundation

struct SpotifyTrack: Equatable, Identifiable {
    let id: String                 // Spotify track ID
    let uri: String                // spotify:track:<id>
    let title: String
    let artists: [String]          // e.g. ["Brian Eno", "David Byrne"]
    let album: String
    let durationMs: Int
    let trackNumber: Int?
    let artworkURL: URL?
}

struct SpotifyPlaylistMetadata: Equatable {
    let id: String
    let uri: String                // spotify:playlist:<id>
    let name: String
    let description: String
    let coverURL: URL?
    let tracks: [SpotifyTrack]

    var totalDurationMs: Int { tracks.reduce(0) { $0 + $1.durationMs } }
    var trackCount: Int { tracks.count }
}
```

- [ ] **Step 2: Capture an HTML fixture**

Manually fetch the playlist page and save it. Run from terminal (one-time):
```bash
mkdir -p "/Volumes/fbe ebosuite live 18tb/Projects/video-downloader/VideoDownloaderTests/Fixtures"
curl -L -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15" \
  "https://open.spotify.com/playlist/0sooekw4rFNXqCeOOVGtqY" \
  -o "/Volumes/fbe ebosuite live 18tb/Projects/video-downloader/VideoDownloaderTests/Fixtures/spotify_playlist_public.html"
```
Verify the file is non-trivial (>50KB) and contains `"@type":"MusicPlaylist"` or `Spotify.Entity` JSON.

- [ ] **Step 3: Add fixture as a test resource**

In `project.yml` under `VideoDownloaderTests` target, add:
```yaml
sources:
  - path: VideoDownloaderTests
  - path: VideoDownloaderTests/Fixtures
    buildPhase: resources
    type: folder
```
Run `xcodegen` to regenerate.

- [ ] **Step 4: Write failing scraper test**

Create `VideoDownloaderTests/SpotifyMetadataScraperTests.swift`:
```swift
import XCTest
@testable import VideoDownloader

final class SpotifyMetadataScraperTests: XCTestCase {
    private func loadFixture() throws -> String {
        let url = Bundle(for: type(of: self)).url(forResource: "spotify_playlist_public",
                                                   withExtension: "html")!
        return try String(contentsOf: url)
    }

    func test_parse_returnsPlaylistMetadata() throws {
        let html = try loadFixture()
        let result = try SpotifyMetadataScraper.parse(html: html, playlistID: "0sooekw4rFNXqCeOOVGtqY")
        XCTAssertEqual(result.id, "0sooekw4rFNXqCeOOVGtqY")
        XCTAssertEqual(result.uri, "spotify:playlist:0sooekw4rFNXqCeOOVGtqY")
        XCTAssertFalse(result.name.isEmpty)
        XCTAssertGreaterThan(result.trackCount, 0)
    }

    func test_parse_eachTrackHasRequiredFields() throws {
        let html = try loadFixture()
        let result = try SpotifyMetadataScraper.parse(html: html, playlistID: "0sooekw4rFNXqCeOOVGtqY")
        for track in result.tracks {
            XCTAssertFalse(track.id.isEmpty, "track ID empty")
            XCTAssertFalse(track.title.isEmpty, "track title empty")
            XCTAssertFalse(track.artists.isEmpty, "track artists empty")
            XCTAssertGreaterThan(track.durationMs, 0, "track duration zero")
        }
    }

    func test_parse_emptyHTMLThrows() {
        XCTAssertThrowsError(try SpotifyMetadataScraper.parse(html: "", playlistID: "x"))
    }
}
```

- [ ] **Step 5: Run test — verify fail**

```bash
xcodebuild -project VideoDownloader.xcodeproj -scheme VideoDownloader \
  -derivedDataPath "/Volumes/1tb /claude code projects /DerivedData/VideoDownloader" \
  test -only-testing:VideoDownloaderTests/SpotifyMetadataScraperTests
```
Expected: compile failure.

- [ ] **Step 6: Implement SpotifyMetadataScraper**

Spotify's playlist page embeds a JSON-LD `<script type="application/ld+json">` block with the basic playlist info, AND a more complete `Spotify.Entity = {...};` JSON in an inline script. Strategy: try JSON-LD first (simple, stable for public playlists); if missing or incomplete, parse `Spotify.Entity`.

Create `VideoDownloader/Backend/Spotify/SpotifyMetadataScraper.swift`:
```swift
import Foundation

enum SpotifyMetadataScraperError: Error {
    case empty
    case noStructuredData
    case malformedJSON(String)
}

enum SpotifyMetadataScraper {
    /// Fetches and parses a public Spotify playlist page.
    static func fetch(playlistID: String) async throws -> SpotifyPlaylistMetadata {
        guard let url = URL(string: "https://open.spotify.com/playlist/\(playlistID)") else {
            throw SpotifyMetadataScraperError.empty
        }
        var req = URLRequest(url: url)
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let html = String(data: data, encoding: .utf8) else {
            throw SpotifyMetadataScraperError.empty
        }
        return try parse(html: html, playlistID: playlistID)
    }

    /// Parse playlist metadata from raw HTML. Pure function for testability.
    static func parse(html: String, playlistID: String) throws -> SpotifyPlaylistMetadata {
        guard !html.isEmpty else { throw SpotifyMetadataScraperError.empty }

        // Try JSON-LD block first
        if let jsonld = extractJSONLD(html: html) {
            if let parsed = try? parseJSONLD(jsonld, playlistID: playlistID) {
                return parsed
            }
        }
        // Fallback: parse inline window.__INITIAL_STATE__ or Spotify.Entity
        if let initial = extractInitialState(html: html) {
            if let parsed = try? parseInitialState(initial, playlistID: playlistID) {
                return parsed
            }
        }
        throw SpotifyMetadataScraperError.noStructuredData
    }

    private static func extractJSONLD(html: String) -> Data? {
        // Find <script type="application/ld+json">…</script>
        let pattern = #"<script type="application/ld\+json">(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let m = regex.firstMatch(in: html, options: [], range: range),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r]).data(using: .utf8)
    }

    private static func parseJSONLD(_ data: Data, playlistID: String) throws -> SpotifyPlaylistMetadata {
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let name = obj["name"] as? String ?? ""
        let description = obj["description"] as? String ?? ""
        let coverURL: URL? = (obj["image"] as? String).flatMap(URL.init(string:))

        let trackArr = obj["track"] as? [[String: Any]] ?? []
        let tracks: [SpotifyTrack] = trackArr.enumerated().compactMap { idx, item in
            guard let trackName = item["name"] as? String,
                  let trackURL = item["url"] as? String,
                  let id = trackIDFromURL(trackURL),
                  let durationISO = item["duration"] as? String else { return nil }
            let artistsArr = item["byArtist"] as? [[String: Any]] ?? []
            let artists = artistsArr.compactMap { $0["name"] as? String }
            let albumName = (item["inAlbum"] as? [String: Any])?["name"] as? String ?? ""
            let durationMs = parseISO8601Duration(durationISO)
            return SpotifyTrack(
                id: id,
                uri: "spotify:track:\(id)",
                title: trackName,
                artists: artists,
                album: albumName,
                durationMs: durationMs,
                trackNumber: idx + 1,
                artworkURL: nil
            )
        }
        guard !tracks.isEmpty else {
            throw SpotifyMetadataScraperError.noStructuredData
        }
        return SpotifyPlaylistMetadata(
            id: playlistID,
            uri: "spotify:playlist:\(playlistID)",
            name: name,
            description: description,
            coverURL: coverURL,
            tracks: tracks
        )
    }

    private static func trackIDFromURL(_ urlString: String) -> String? {
        guard let u = URL(string: urlString) else { return nil }
        let comps = u.path.split(separator: "/").map(String.init)
        guard comps.count >= 2, comps[0] == "track" else { return nil }
        return comps[1]
    }

    /// Parses ISO 8601 durations like "PT3M42S" → 222000 ms.
    private static func parseISO8601Duration(_ s: String) -> Int {
        var total = 0
        var current = ""
        for ch in s {
            if ch.isNumber { current.append(ch); continue }
            guard let n = Int(current) else { current = ""; continue }
            switch ch {
            case "H": total += n * 3_600_000
            case "M": total += n * 60_000
            case "S": total += n * 1_000
            default: break
            }
            current = ""
        }
        return total
    }

    private static func extractInitialState(html: String) -> Data? {
        // Spotify embeds a __NEXT_DATA__ JSON in modern pages.
        let pattern = #"<script id="__NEXT_DATA__"[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let m = regex.firstMatch(in: html, options: [], range: range),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r]).data(using: .utf8)
    }

    private static func parseInitialState(_ data: Data, playlistID: String) throws -> SpotifyPlaylistMetadata {
        // __NEXT_DATA__ varies; navigate to props.pageProps.entity.tracks.items
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let props = root["props"] as? [String: Any] ?? [:]
        let pageProps = props["pageProps"] as? [String: Any] ?? [:]
        let entity = pageProps["entity"] as? [String: Any] ?? [:]
        let name = entity["name"] as? String ?? ""
        let description = entity["description"] as? String ?? ""
        let images = entity["images"] as? [[String: Any]] ?? []
        let coverURL: URL? = (images.first?["url"] as? String).flatMap(URL.init(string:))

        let tracksContainer = entity["tracks"] as? [String: Any] ?? [:]
        let items = tracksContainer["items"] as? [[String: Any]] ?? []
        let tracks: [SpotifyTrack] = items.enumerated().compactMap { idx, item in
            let track = (item["track"] as? [String: Any]) ?? item
            guard let id = track["id"] as? String,
                  let title = track["name"] as? String else { return nil }
            let durationMs = track["duration_ms"] as? Int ?? 0
            let artistsArr = track["artists"] as? [[String: Any]] ?? []
            let artists = artistsArr.compactMap { $0["name"] as? String }
            let albumDict = track["album"] as? [String: Any] ?? [:]
            let albumName = albumDict["name"] as? String ?? ""
            let albumImages = albumDict["images"] as? [[String: Any]] ?? []
            let artworkURL = (albumImages.first?["url"] as? String).flatMap(URL.init(string:))
            return SpotifyTrack(
                id: id,
                uri: "spotify:track:\(id)",
                title: title,
                artists: artists,
                album: albumName,
                durationMs: durationMs,
                trackNumber: idx + 1,
                artworkURL: artworkURL
            )
        }
        guard !tracks.isEmpty else {
            throw SpotifyMetadataScraperError.noStructuredData
        }
        return SpotifyPlaylistMetadata(
            id: playlistID,
            uri: "spotify:playlist:\(playlistID)",
            name: name,
            description: description,
            coverURL: coverURL,
            tracks: tracks
        )
    }
}
```

- [ ] **Step 7: Run tests — verify pass**

```bash
xcodebuild -project VideoDownloader.xcodeproj -scheme VideoDownloader \
  -derivedDataPath "/Volumes/1tb /claude code projects /DerivedData/VideoDownloader" \
  test -only-testing:VideoDownloaderTests/SpotifyMetadataScraperTests
```
Expected: 3 tests pass. If parsing fails because Spotify's HTML structure differs from what's coded, inspect the captured fixture and adjust the JSON path traversal in `parseInitialState`.

- [ ] **Step 8: Commit**

```bash
git add VideoDownloader/Backend/Spotify/SpotifyTrack.swift VideoDownloader/Backend/Spotify/SpotifyMetadataScraper.swift VideoDownloaderTests/SpotifyMetadataScraperTests.swift VideoDownloaderTests/Fixtures/spotify_playlist_public.html project.yml
git commit -m "feat: SpotifyMetadataScraper parses public playlist HTML"
```

---

## Task 5: SpotifyAppController (AppleScript wrapper)

**Files:**
- Create: `VideoDownloader/Backend/Spotify/SpotifyAppController.swift`

- [ ] **Step 1: Implement SpotifyAppController**

Create `VideoDownloader/Backend/Spotify/SpotifyAppController.swift`:
```swift
import Foundation
import AppKit

enum SpotifyAppControllerError: Error {
    case spotifyNotInstalled
    case appleScriptError(String)
}

enum SpotifyPlayerState: String {
    case playing, paused, stopped, unknown

    init(_ raw: String) {
        switch raw {
        case "playing": self = .playing
        case "paused": self = .paused
        case "stopped": self = .stopped
        default: self = .unknown
        }
    }
}

struct SpotifyCurrentTrackInfo {
    let id: String
    let name: String
    let artist: String
    let album: String
    let durationMs: Int
    let positionMs: Int
}

final class SpotifyAppController {
    static func isInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil
    }

    /// Launch Spotify if not running. No-op if already running.
    static func ensureRunning() async throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else {
            throw SpotifyAppControllerError.spotifyNotInstalled
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = false
            cfg.hides = true
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: cfg)
            try await Task.sleep(nanoseconds: 1_500_000_000) // settle
        }
    }

    static func play(uri: String) throws {
        let script = #"tell application "Spotify" to play track "\#(uri)""#
        try runAppleScript(script)
    }

    static func pause() throws {
        try runAppleScript(#"tell application "Spotify" to pause"#)
    }

    static func resume() throws {
        try runAppleScript(#"tell application "Spotify" to play"#)
    }

    static func currentTrack() throws -> SpotifyCurrentTrackInfo? {
        let script = """
        tell application "Spotify"
            if player state is stopped then return ""
            set tID to id of current track
            set tName to name of current track
            set tArtist to artist of current track
            set tAlbum to album of current track
            set tDur to duration of current track
            set tPos to player position
            return tID & "\u{2}" & tName & "\u{2}" & tArtist & "\u{2}" & tAlbum & "\u{2}" & tDur & "\u{2}" & tPos
        end tell
        """
        let raw = try runAppleScript(script)
        guard !raw.isEmpty else { return nil }
        let parts = raw.components(separatedBy: "\u{2}")
        guard parts.count == 6 else { return nil }
        let id = parts[0].replacingOccurrences(of: "spotify:track:", with: "")
        return SpotifyCurrentTrackInfo(
            id: id,
            name: parts[1],
            artist: parts[2],
            album: parts[3],
            durationMs: Int(parts[4]) ?? 0,            // duration is in ms in Spotify AppleScript
            positionMs: Int(Double(parts[5]) ?? 0) * 1000  // player position is in seconds
        )
    }

    static func playerState() throws -> SpotifyPlayerState {
        let raw = try runAppleScript(#"tell application "Spotify" to player state as string"#)
        return SpotifyPlayerState(raw)
    }

    @discardableResult
    private static func runAppleScript(_ source: String) throws -> String {
        var errInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw SpotifyAppControllerError.appleScriptError("compile failed")
        }
        let result = script.executeAndReturnError(&errInfo)
        if let errInfo = errInfo {
            throw SpotifyAppControllerError.appleScriptError("\(errInfo)")
        }
        return result.stringValue ?? ""
    }
}
```

- [ ] **Step 2: Manual smoke test**

Build and open the app, then in a temporary debug View or via a unit test runner, call:
```swift
try await SpotifyAppController.ensureRunning()
try SpotifyAppController.play(uri: "spotify:track:4iV5W9uYEdYUVa79Axb7Rh")
try await Task.sleep(nanoseconds: 2_000_000_000)
print(try SpotifyAppController.currentTrack() as Any)
try SpotifyAppController.pause()
```
Expected: macOS prompts once for Apple Events permission for `com.spotify.client`. After granting, Spotify plays the track and current-track query returns valid info.

- [ ] **Step 3: Commit**

```bash
git add VideoDownloader/Backend/Spotify/SpotifyAppController.swift
git commit -m "feat: SpotifyAppController — AppleScript wrapper for play/pause/state"
```

---

## Task 6: SpotifyPlaybackObserver (distributed notifications)

**Files:**
- Create: `VideoDownloader/Backend/Spotify/SpotifyPlaybackObserver.swift`

- [ ] **Step 1: Implement observer**

Create `VideoDownloader/Backend/Spotify/SpotifyPlaybackObserver.swift`:
```swift
import Foundation

struct SpotifyNotificationPayload: Equatable {
    let trackID: String         // strips "spotify:track:" prefix
    let name: String
    let artist: String
    let album: String
    let durationMs: Int
    let playerState: SpotifyPlayerState
    let timestamp: Date
}

final class SpotifyPlaybackObserver {
    private var token: NSObjectProtocol?
    private let onEvent: @Sendable (SpotifyNotificationPayload) -> Void

    init(onEvent: @Sendable @escaping (SpotifyNotificationPayload) -> Void) {
        self.onEvent = onEvent
    }

    func start() {
        token = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let info = note.userInfo as? [String: Any],
                  let self else { return }
            let trackIDRaw = info["Track ID"] as? String ?? ""
            let trackID = trackIDRaw.replacingOccurrences(of: "spotify:track:", with: "")
            let payload = SpotifyNotificationPayload(
                trackID: trackID,
                name: info["Name"] as? String ?? "",
                artist: info["Artist"] as? String ?? "",
                album: info["Album"] as? String ?? "",
                durationMs: (info["Duration"] as? Int) ?? 0,
                playerState: SpotifyPlayerState(info["Player State"] as? String ?? ""),
                timestamp: Date()
            )
            self.onEvent(payload)
        }
    }

    func stop() {
        if let t = token {
            DistributedNotificationCenter.default().removeObserver(t)
            token = nil
        }
    }

    deinit { stop() }
}
```

- [ ] **Step 2: Manual smoke test**

Inside a test scratchpad, set up an observer and play a track via `SpotifyAppController`:
```swift
let obs = SpotifyPlaybackObserver { payload in
    print("evt: \(payload)")
}
obs.start()
try SpotifyAppController.play(uri: "spotify:track:4iV5W9uYEdYUVa79Axb7Rh")
// wait — should see at least one event print with the track info
RunLoop.main.run(until: Date().addingTimeInterval(8))
obs.stop()
```
Expected: at least one event prints when Spotify plays. If none arrive, Spotify Mac app's notifications may be disabled (verify with `Console.app` filter `com.spotify.client`).

- [ ] **Step 3: Commit**

```bash
git add VideoDownloader/Backend/Spotify/SpotifyPlaybackObserver.swift
git commit -m "feat: SpotifyPlaybackObserver — distributed notification listener"
```

---

## Task 7: SpotifyAudioCaptureRunner (CoreAudio Process Tap)

**Files:**
- Create: `VideoDownloader/Backend/Spotify/SpotifyAudioCaptureRunner.swift`

This is the trickiest task. CoreAudio Process Tap (`AudioHardwareCreateProcessTap`, macOS 14.2+) captures audio for a specific PID. Apple's reference: WWDC23 session "What's new in CoreAudio". The high-level shape: create a `CATapDescription`, create the tap, create an aggregate device that contains the tap, install an IOProc to read PCM, write to a ring buffer.

- [ ] **Step 1: Implement capture runner**

Create `VideoDownloader/Backend/Spotify/SpotifyAudioCaptureRunner.swift`:
```swift
import Foundation
import CoreAudio
import AudioToolbox
import AppKit

enum SpotifyAudioCaptureError: Error {
    case spotifyNotRunning
    case tapCreateFailed(OSStatus)
    case aggregateCreateFailed(OSStatus)
    case ioProcInstallFailed(OSStatus)
    case deviceStartFailed(OSStatus)
}

/// PCM frame delivered by the capture runner.
/// Format: 32-bit float interleaved stereo, 44.1 kHz (matches Spotify decoded output).
struct SpotifyPCMChunk {
    let samples: [Float]    // interleaved L,R,L,R,...
    let sampleRate: Double  // typically 44100
    let channelCount: Int   // typically 2
    let timestamp: Date
}

final class SpotifyAudioCaptureRunner {
    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioDeviceID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private let onChunk: (SpotifyPCMChunk) -> Void
    private let lock = NSLock()
    private var running = false

    init(onChunk: @escaping (SpotifyPCMChunk) -> Void) {
        self.onChunk = onChunk
    }

    func start() throws {
        guard !running else { return }
        let pid = try locateSpotifyPID()

        // 1) Create a process tap targeting Spotify's PID (output stream).
        let desc = CATapDescription(stereoMixdownOfProcesses: [pid])
        desc.muteBehavior = .unmuted
        var tap: AudioObjectID = 0
        let st1 = AudioHardwareCreateProcessTap(desc, &tap)
        guard st1 == noErr else { throw SpotifyAudioCaptureError.tapCreateFailed(st1) }
        self.tapID = tap

        // 2) Create an aggregate device containing the tap.
        let aggUID = "com.fascinatedbyeverything.VideoDownloader.SpotifyTapAggregate-\(UUID().uuidString)"
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Spotify Tap Aggregate",
            kAudioAggregateDeviceUIDKey as String: aggUID,
            kAudioAggregateDeviceMainSubDeviceKey as String: "",
            kAudioAggregateDeviceIsPrivateKey as String: 1,
            kAudioAggregateDeviceIsStackedKey as String: 0,
            kAudioAggregateDeviceTapListKey as String: [
                [kAudioSubTapUIDKey as String: tapUID(of: tap)]
            ],
            kAudioAggregateDeviceSubDeviceListKey as String: []
        ]
        var agg: AudioDeviceID = 0
        let st2 = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &agg)
        guard st2 == noErr else { throw SpotifyAudioCaptureError.aggregateCreateFailed(st2) }
        self.aggregateID = agg

        // 3) Install IOProc.
        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()
        var procID: AudioDeviceIOProcID?
        let st3 = AudioDeviceCreateIOProcIDWithBlock(&procID, agg, nil) { [weak self] _, inInputData, _, _, _ in
            guard let self else { return }
            self.handleIO(inInputData)
        }
        guard st3 == noErr, let pid = procID else { throw SpotifyAudioCaptureError.ioProcInstallFailed(st3) }
        self.ioProcID = pid

        // 4) Start.
        let st4 = AudioDeviceStart(agg, pid)
        guard st4 == noErr else { throw SpotifyAudioCaptureError.deviceStartFailed(st4) }
        running = true
        _ = unmanagedSelf // keep linter happy
    }

    func stop() {
        guard running else { return }
        if let pid = ioProcID {
            AudioDeviceStop(aggregateID, pid)
            AudioDeviceDestroyIOProcID(aggregateID, pid)
            ioProcID = nil
        }
        if aggregateID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = 0
        }
        if tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }
        running = false
    }

    deinit { stop() }

    private func handleIO(_ inputDataPtr: UnsafePointer<AudioBufferList>) {
        let abl = inputDataPtr.pointee
        guard abl.mNumberBuffers > 0 else { return }
        let buf = abl.mBuffers
        guard let raw = buf.mData else { return }
        let frameCount = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
        let ptr = raw.bindMemory(to: Float.self, capacity: frameCount)
        let array = Array(UnsafeBufferPointer(start: ptr, count: frameCount))
        let chunk = SpotifyPCMChunk(
            samples: array,
            sampleRate: 44100,
            channelCount: Int(buf.mNumberChannels),
            timestamp: Date()
        )
        onChunk(chunk)
    }

    private func locateSpotifyPID() throws -> pid_t {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first else {
            throw SpotifyAudioCaptureError.spotifyNotRunning
        }
        return app.processIdentifier
    }

    private func tapUID(of tap: AudioObjectID) -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        AudioObjectGetPropertyData(tap, &addr, 0, nil, &size, &uid)
        return uid as String
    }
}
```

> ⚠ **Note:** `CATapDescription`, `AudioHardwareCreateProcessTap`, `kAudioTapPropertyUID`, and `kAudioAggregateDeviceTapListKey` are CoreAudio Process Tap APIs introduced in macOS 14.2. If the linker reports any of these as undeclared, run `xcrun --show-sdk-path` to verify SDK version is ≥ 14.2 and check `<CoreAudio/AudioHardwareTapping.h>`. The exact initializer name (`stereoMixdownOfProcesses:`) matches Apple's published API; if it's slightly different, consult `CATapDescription.h` in the SDK and adjust.

- [ ] **Step 2: Smoke-test capture**

Manual scratchpad test:
```swift
try await SpotifyAppController.ensureRunning()
try SpotifyAppController.play(uri: "spotify:track:4iV5W9uYEdYUVa79Axb7Rh")
let cap = SpotifyAudioCaptureRunner { chunk in
    let rms = sqrt(chunk.samples.reduce(0) { $0 + $1 * $1 } / Float(chunk.samples.count))
    print("chunk: \(chunk.samples.count) frames rms=\(rms)")
}
try cap.start()
try await Task.sleep(nanoseconds: 4_000_000_000)
cap.stop()
```
Expected: chunks print steadily with non-zero RMS values while Spotify is playing. If RMS stays at 0, the tap is not seeing Spotify audio — verify Spotify is playing audibly through speakers/headphones and that the tap targets the right PID.

- [ ] **Step 3: Commit**

```bash
git add VideoDownloader/Backend/Spotify/SpotifyAudioCaptureRunner.swift
git commit -m "feat: SpotifyAudioCaptureRunner — CoreAudio Process Tap for Spotify.app"
```

---

## Task 8: SpotifyTrackSegmenter (TDD)

**Files:**
- Create: `VideoDownloader/Backend/Spotify/SpotifyTrackSegmenter.swift`
- Create: `VideoDownloaderTests/SpotifyTrackSegmenterTests.swift`

- [ ] **Step 1: Write failing test**

Create `VideoDownloaderTests/SpotifyTrackSegmenterTests.swift`:
```swift
import XCTest
@testable import VideoDownloader

final class SpotifyTrackSegmenterTests: XCTestCase {
    func test_segmenter_emitsSegmentOnTrackChange() {
        var emitted: [(SpotifySegmentResult)] = []
        let seg = SpotifyTrackSegmenter { result in emitted.append(result) }

        // Track A starts
        seg.onPlaybackEvent(makeEvent(id: "A", state: .playing))
        seg.feed(samples: Array(repeating: Float(0.5), count: 4096), at: Date())

        // Track changes to B → emits A
        seg.onPlaybackEvent(makeEvent(id: "B", state: .playing))
        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted[0].trackID, "A")
        XCTAssertEqual(emitted[0].samples.count, 4096)

        seg.feed(samples: Array(repeating: Float(0.25), count: 2048), at: Date())

        // Stop event → emits B
        seg.onPlaybackEvent(makeEvent(id: "B", state: .stopped))
        XCTAssertEqual(emitted.count, 2)
        XCTAssertEqual(emitted[1].trackID, "B")
        XCTAssertEqual(emitted[1].samples.count, 2048)
    }

    func test_segmenter_dropsAudioBeforeFirstEvent() {
        var emitted: [SpotifySegmentResult] = []
        let seg = SpotifyTrackSegmenter { result in emitted.append(result) }

        seg.feed(samples: Array(repeating: Float(0.1), count: 1024), at: Date())
        seg.onPlaybackEvent(makeEvent(id: "A", state: .playing))
        seg.feed(samples: Array(repeating: Float(0.5), count: 1024), at: Date())
        seg.onPlaybackEvent(makeEvent(id: "B", state: .playing))

        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted[0].samples.count, 1024) // pre-event 1024 dropped
    }

    private func makeEvent(id: String, state: SpotifyPlayerState) -> SpotifyNotificationPayload {
        SpotifyNotificationPayload(
            trackID: id, name: "n", artist: "a", album: "b",
            durationMs: 180_000, playerState: state, timestamp: Date()
        )
    }
}
```

- [ ] **Step 2: Run test — verify fail**

```bash
xcodebuild ... test -only-testing:VideoDownloaderTests/SpotifyTrackSegmenterTests
```
Expected: compile failure (`SpotifyTrackSegmenter` undefined).

- [ ] **Step 3: Implement segmenter**

Create `VideoDownloader/Backend/Spotify/SpotifyTrackSegmenter.swift`:
```swift
import Foundation

struct SpotifySegmentResult {
    let trackID: String
    let trackName: String
    let artist: String
    let album: String
    let samples: [Float]
    let sampleRate: Double
    let channelCount: Int
}

final class SpotifyTrackSegmenter {
    private struct ActiveTrack {
        var payload: SpotifyNotificationPayload
        var samples: [Float] = []
        var sampleRate: Double = 44100
        var channelCount: Int = 2
    }
    private var current: ActiveTrack?
    private let onSegment: (SpotifySegmentResult) -> Void
    private let lock = NSLock()

    init(onSegment: @escaping (SpotifySegmentResult) -> Void) {
        self.onSegment = onSegment
    }

    func onPlaybackEvent(_ event: SpotifyNotificationPayload) {
        lock.lock(); defer { lock.unlock() }

        // Stop event closes the current segment.
        if event.playerState == .stopped {
            emitCurrent()
            current = nil
            return
        }

        // Track-change: emit prior, start new.
        if let cur = current, cur.payload.trackID != event.trackID {
            emitCurrent()
        }
        if current?.payload.trackID != event.trackID {
            current = ActiveTrack(payload: event)
        } else {
            current?.payload = event
        }
    }

    func feed(samples: [Float], at _: Date, sampleRate: Double = 44100, channelCount: Int = 2) {
        lock.lock(); defer { lock.unlock() }
        guard current != nil else { return }
        current?.samples.append(contentsOf: samples)
        current?.sampleRate = sampleRate
        current?.channelCount = channelCount
    }

    func flush() {
        lock.lock(); defer { lock.unlock() }
        emitCurrent()
        current = nil
    }

    private func emitCurrent() {
        guard let cur = current, !cur.samples.isEmpty else { return }
        let r = SpotifySegmentResult(
            trackID: cur.payload.trackID,
            trackName: cur.payload.name,
            artist: cur.payload.artist,
            album: cur.payload.album,
            samples: cur.samples,
            sampleRate: cur.sampleRate,
            channelCount: cur.channelCount
        )
        onSegment(r)
    }
}
```

- [ ] **Step 4: Run tests — verify pass**

```bash
xcodebuild ... test -only-testing:VideoDownloaderTests/SpotifyTrackSegmenterTests
```
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add VideoDownloader/Backend/Spotify/SpotifyTrackSegmenter.swift VideoDownloaderTests/SpotifyTrackSegmenterTests.swift
git commit -m "feat: SpotifyTrackSegmenter — splits PCM stream by track-change events"
```

---

## Task 9: SpotifyEncoder (WAV + MP3 + ID3)

**Files:**
- Create: `VideoDownloader/Backend/Spotify/SpotifyEncoder.swift`

- [ ] **Step 1: Implement WAV writer + MP3 transcode + ID3 tagging**

Uses `AVAudioFile` for WAV (lossless passthrough of decoded PCM) and the system Homebrew ffmpeg (already located via `BinaryLocator.ffmpegURL`) for MP3 320 + ID3.

Create `VideoDownloader/Backend/Spotify/SpotifyEncoder.swift`:
```swift
import Foundation
import AVFoundation

enum SpotifyEncoderError: Error {
    case wavWriteFailed(String)
    case ffmpegFailed(Int32, String)
}

struct SpotifyEncodeRequest {
    let segment: SpotifySegmentResult
    let trackNumber: Int
    let outputFolder: URL
    let coverArtURL: URL?      // optional, embedded as ID3 APIC
}

enum SpotifyEncoder {
    /// Writes WAV and MP3 320 to outputFolder. Filenames: "<NN> - <Artist> - <Title>.{wav,mp3}".
    static func encode(_ req: SpotifyEncodeRequest) async throws -> (wav: URL, mp3: URL) {
        let baseName = filename(req: req)
        let wavURL = req.outputFolder.appendingPathComponent("\(baseName).wav")
        let mp3URL = req.outputFolder.appendingPathComponent("\(baseName).mp3")

        try writeWAV(samples: req.segment.samples,
                     sampleRate: req.segment.sampleRate,
                     channelCount: req.segment.channelCount,
                     to: wavURL)

        try await runFFmpegToMP3(
            wavURL: wavURL,
            mp3URL: mp3URL,
            title: req.segment.trackName,
            artist: req.segment.artist,
            album: req.segment.album,
            trackNumber: req.trackNumber,
            coverArtURL: req.coverArtURL
        )

        return (wav: wavURL, mp3: mp3URL)
    }

    private static func filename(req: SpotifyEncodeRequest) -> String {
        let nn = String(format: "%02d", req.trackNumber)
        let artist = sanitize(req.segment.artist)
        let title = sanitize(req.segment.trackName)
        return "\(nn) - \(artist) - \(title)"
    }

    private static func sanitize(_ s: String) -> String {
        let bad: Set<Character> = ["/", ":", "\\", "*", "?", "\"", "<", ">", "|"]
        return String(s.map { bad.contains($0) ? "-" : $0 })
    }

    private static func writeWAV(samples: [Float], sampleRate: Double, channelCount: Int, to url: URL) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: true
        ) else {
            throw SpotifyEncoderError.wavWriteFailed("invalid format")
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: true)

        let frameCount = AVAudioFrameCount(samples.count / channelCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw SpotifyEncoderError.wavWriteFailed("buffer alloc")
        }
        buffer.frameLength = frameCount
        let dst = buffer.floatChannelData!
        // interleaved → just memcpy into dst[0]
        samples.withUnsafeBufferPointer { src in
            memcpy(dst[0], src.baseAddress, samples.count * MemoryLayout<Float>.size)
        }
        try file.write(from: buffer)
    }

    private static func runFFmpegToMP3(
        wavURL: URL, mp3URL: URL,
        title: String, artist: String, album: String,
        trackNumber: Int, coverArtURL: URL?
    ) async throws {
        var args: [String] = [
            "-y",
            "-i", wavURL.path
        ]
        if let cover = coverArtURL {
            // Download cover to a temp file first (ffmpeg needs a local input for APIC)
            let coverTmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("cover_\(UUID().uuidString).jpg")
            if let data = try? Data(contentsOf: cover) {
                try? data.write(to: coverTmp)
                args += ["-i", coverTmp.path,
                         "-map", "0:a", "-map", "1:0",
                         "-c:v", "copy",
                         "-id3v2_version", "3",
                         "-metadata:s:v", "title=Album cover",
                         "-metadata:s:v", "comment=Cover (front)"]
            }
        }
        args += [
            "-codec:a", "libmp3lame",
            "-b:a", "320k",
            "-metadata", "title=\(title)",
            "-metadata", "artist=\(artist)",
            "-metadata", "album=\(album)",
            "-metadata", "track=\(trackNumber)",
            mp3URL.path
        ]

        let p = Process()
        p.executableURL = BinaryLocator.ffmpegURL
        p.arguments = args
        let errPipe = Pipe()
        p.standardError = errPipe
        try p.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            p.terminationHandler = { _ in cont.resume() }
        }
        if p.terminationStatus != 0 {
            let errText = String(data: (try? errPipe.fileHandleForReading.readToEnd()) ?? Data(), encoding: .utf8) ?? ""
            throw SpotifyEncoderError.ffmpegFailed(p.terminationStatus, errText)
        }
    }
}
```

- [ ] **Step 2: Manual smoke test**

Run a snippet that creates a 1-second test signal, encodes:
```swift
let samples = (0..<88200).map { i in sin(Float(i) * 0.05) * 0.5 } // 1s mono-ish, 2ch interleave
let seg = SpotifySegmentResult(
    trackID: "test", trackName: "Test", artist: "Test", album: "Test",
    samples: samples, sampleRate: 44100, channelCount: 2)
let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("spotenc-\(UUID())")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let req = SpotifyEncodeRequest(segment: seg, trackNumber: 1, outputFolder: folder, coverArtURL: nil)
let (wav, mp3) = try await SpotifyEncoder.encode(req)
print(wav, mp3)
```
Expected: both files exist, mp3 has ID3 tags (`afinfo` or `mediainfo` to verify).

- [ ] **Step 3: Commit**

```bash
git add VideoDownloader/Backend/Spotify/SpotifyEncoder.swift
git commit -m "feat: SpotifyEncoder — WAV writer + MP3 320 via ffmpeg with ID3 tags"
```

---

## Task 10: SpotifyTabModel (orchestrator)

**Files:**
- Create: `VideoDownloader/Spotify/SpotifyTabModel.swift`

- [ ] **Step 1: Implement model**

Create `VideoDownloader/Spotify/SpotifyTabModel.swift`:
```swift
import Foundation
import Observation

@Observable
final class SpotifyTabModel {
    enum Phase {
        case idle
        case loadingPreview
        case preview(SpotifyPlaylistMetadata)
        case capturing(active: ActiveCapture)
        case finished(folder: URL, capturedTrackCount: Int)
        case error(String)
    }

    struct ActiveCapture {
        var metadata: SpotifyPlaylistMetadata
        var currentTrackIndex: Int
        var completedTrackIDs: Set<String>
        var outputFolder: URL
    }

    var pastedURL: String = ""
    private(set) var phase: Phase = .idle

    private var observer: SpotifyPlaybackObserver?
    private var capture: SpotifyAudioCaptureRunner?
    private var segmenter: SpotifyTrackSegmenter?

    func loadPreview() async {
        let raw = pastedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = SpotifyURL.parse(raw), parsed.kind == .playlist else {
            phase = .error("Not a Spotify playlist URL")
            return
        }
        phase = .loadingPreview
        do {
            let meta = try await SpotifyMetadataScraper.fetch(playlistID: parsed.id)
            phase = .preview(meta)
        } catch {
            phase = .error("Could not load playlist preview: \(error.localizedDescription)")
        }
    }

    func startCapture(outputFolder: URL) async {
        guard case let .preview(meta) = phase else { return }
        guard SpotifyAppController.isInstalled() else {
            phase = .error("Spotify is not installed")
            return
        }
        do {
            try await SpotifyAppController.ensureRunning()
            let playlistFolder = outputFolder.appendingPathComponent(sanitize(meta.name))
            try FileManager.default.createDirectory(at: playlistFolder, withIntermediateDirectories: true)

            var active = ActiveCapture(metadata: meta, currentTrackIndex: 0,
                                       completedTrackIDs: [], outputFolder: playlistFolder)
            phase = .capturing(active: active)

            let segmenter = SpotifyTrackSegmenter { [weak self] result in
                self?.handleSegment(result, active: &active)
            }
            self.segmenter = segmenter

            let observer = SpotifyPlaybackObserver { [weak self] event in
                self?.segmenter?.onPlaybackEvent(event)
                self?.advanceTrackIndex(for: event, active: &active)
            }
            self.observer = observer
            observer.start()

            let capture = SpotifyAudioCaptureRunner { [weak self] chunk in
                self?.segmenter?.feed(samples: chunk.samples, at: chunk.timestamp,
                                      sampleRate: chunk.sampleRate, channelCount: chunk.channelCount)
            }
            self.capture = capture
            try capture.start()

            try SpotifyAppController.play(uri: meta.uri)
        } catch {
            phase = .error("Capture failed: \(error.localizedDescription)")
            stopCapture()
        }
    }

    func stopCapture() {
        capture?.stop()
        observer?.stop()
        segmenter?.flush()
        capture = nil
        observer = nil
        segmenter = nil
    }

    private func handleSegment(_ result: SpotifySegmentResult, active: inout ActiveCapture) {
        Task.detached { [weak self] in
            guard let self else { return }
            // Find track number from metadata
            let meta = active.metadata
            let trackNumber = meta.tracks.firstIndex(where: { $0.id == result.trackID }).map { $0 + 1 } ?? 0
            let req = SpotifyEncodeRequest(
                segment: result,
                trackNumber: trackNumber,
                outputFolder: active.outputFolder,
                coverArtURL: meta.tracks.first(where: { $0.id == result.trackID })?.artworkURL ?? meta.coverURL
            )
            do {
                _ = try await SpotifyEncoder.encode(req)
                await MainActor.run {
                    active.completedTrackIDs.insert(result.trackID)
                    self.phase = .capturing(active: active)
                }
            } catch {
                await MainActor.run {
                    self.phase = .error("Encode failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func advanceTrackIndex(for event: SpotifyNotificationPayload, active: inout ActiveCapture) {
        if let idx = active.metadata.tracks.firstIndex(where: { $0.id == event.trackID }) {
            active.currentTrackIndex = idx
            phase = .capturing(active: active)
        }
        // End-of-playlist detection: state stopped after final track
        if event.playerState == .stopped,
           active.completedTrackIDs.count == active.metadata.tracks.count {
            phase = .finished(folder: active.outputFolder, capturedTrackCount: active.completedTrackIDs.count)
            stopCapture()
        }
    }

    private func sanitize(_ s: String) -> String {
        let bad: Set<Character> = ["/", ":", "\\", "*", "?", "\"", "<", ">", "|"]
        return String(s.map { bad.contains($0) ? "-" : $0 })
    }
}
```

- [ ] **Step 2: Verify compiles**

```bash
xcodebuild -project VideoDownloader.xcodeproj -scheme VideoDownloader build
```

- [ ] **Step 3: Commit**

```bash
git add VideoDownloader/Spotify/SpotifyTabModel.swift
git commit -m "feat: SpotifyTabModel — orchestrates preview, capture, segmenting, encoding"
```

---

## Task 11: SpotifyTabView + SpotifyPreviewView + SpotifyCaptureView

**Files:**
- Create: `VideoDownloader/Spotify/SpotifyTabView.swift`
- Create: `VideoDownloader/Spotify/SpotifyPreviewView.swift`
- Create: `VideoDownloader/Spotify/SpotifyCaptureView.swift`

- [ ] **Step 1: Tab root view**

Create `VideoDownloader/Spotify/SpotifyTabView.swift`:
```swift
import SwiftUI

struct SpotifyTabView: View {
    @State private var model = SpotifyTabModel()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Paste Spotify playlist URL…", text: $model.pastedURL)
                    .textFieldStyle(.roundedBorder)
                Button("Load") {
                    Task { await model.loadPreview() }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(model.pastedURL.isEmpty)
            }

            Divider()

            switch model.phase {
            case .idle:
                ContentUnavailableView("Paste a Spotify playlist link",
                                       systemImage: "music.note.list")
            case .loadingPreview:
                ProgressView("Loading preview…")
            case .preview(let meta):
                SpotifyPreviewView(metadata: meta) { folder in
                    Task { await model.startCapture(outputFolder: folder) }
                }
            case .capturing(let active):
                SpotifyCaptureView(active: active, onStop: { model.stopCapture() })
            case .finished(let folder, let count):
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("Captured \(count) tracks")
                    Button("Open in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    Button("Capture another") { model.phase = .idle }
                }
            case .error(let msg):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text(msg).multilineTextAlignment(.center)
                    Button("Reset") { model.phase = .idle }
                }
            }
            Spacer()
        }
        .padding(16)
    }
}
```

- [ ] **Step 2: Preview view**

Create `VideoDownloader/Spotify/SpotifyPreviewView.swift`:
```swift
import SwiftUI

struct SpotifyPreviewView: View {
    let metadata: SpotifyPlaylistMetadata
    let onStart: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let cover = metadata.coverURL {
                    AsyncImage(url: cover) { image in
                        image.resizable().scaledToFit()
                    } placeholder: { Color.secondary.opacity(0.2) }
                    .frame(width: 96, height: 96)
                    .cornerRadius(6)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata.name).font(.title2).bold()
                    Text("\(metadata.trackCount) tracks · \(formatMinutes(metadata.totalDurationMs))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Capture takes the same time as playback (real-time).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Start Capture…") {
                    pickFolder { url in onStart(url) }
                }
                .buttonStyle(.borderedProminent)
            }

            List(metadata.tracks) { t in
                HStack {
                    Text(String(format: "%02d", t.trackNumber ?? 0)).frame(width: 28, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(t.title)
                        Text(t.artists.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(formatMinutes(t.durationMs)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 200)
        }
    }

    private func formatMinutes(_ ms: Int) -> String {
        let total = ms / 1000
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    private func pickFolder(_ done: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Capture Here"
        if panel.runModal() == .OK, let url = panel.url {
            done(url)
        }
    }
}
```

- [ ] **Step 3: Capture view**

Create `VideoDownloader/Spotify/SpotifyCaptureView.swift`:
```swift
import SwiftUI

struct SpotifyCaptureView: View {
    let active: SpotifyTabModel.ActiveCapture
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView(value: Double(active.completedTrackIDs.count),
                             total: Double(active.metadata.trackCount))
                    .progressViewStyle(.linear)
                Text("\(active.completedTrackIDs.count) / \(active.metadata.trackCount)")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Stop") { onStop() }
            }

            if let nowPlaying = currentTrack {
                HStack {
                    Image(systemName: "waveform")
                    VStack(alignment: .leading) {
                        Text(nowPlaying.title).bold()
                        Text(nowPlaying.artists.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            List {
                ForEach(active.metadata.tracks) { t in
                    HStack {
                        Image(systemName: active.completedTrackIDs.contains(t.id)
                              ? "checkmark.circle.fill"
                              : (t.id == currentTrack?.id ? "circle.dotted" : "circle"))
                            .foregroundStyle(active.completedTrackIDs.contains(t.id) ? .green : .secondary)
                        Text(String(format: "%02d", t.trackNumber ?? 0)).frame(width: 28, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Text(t.title)
                        Spacer()
                        Text(t.artists.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var currentTrack: SpotifyTrack? {
        guard active.currentTrackIndex < active.metadata.tracks.count else { return nil }
        return active.metadata.tracks[active.currentTrackIndex]
    }
}
```

- [ ] **Step 4: Verify build**

```bash
xcodegen
xcodebuild -project VideoDownloader.xcodeproj -scheme VideoDownloader build
```
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add VideoDownloader/Spotify/
git commit -m "feat: Spotify tab UI — preview, capture progress, results"
```

---

## Task 12: Wire 4th tab into MainView

**Files:**
- Modify: `VideoDownloader/App/MainView.swift`

- [ ] **Step 1: Add `.spotify` case**

Edit `MainView.swift`. Add a fourth case to the `Tab` enum:
```swift
case spotify = "Spotify"
```

Add the corresponding view in the switch:
```swift
case .spotify: SpotifyTabView()
```

- [ ] **Step 2: Build and run**

```bash
xcodebuild -project VideoDownloader.xcodeproj -scheme VideoDownloader build
open "/Volumes/1tb /claude code projects /DerivedData/VideoDownloader/Build/Products/Debug/VideoDownloader.app"
```
Expected: app launches with 4 tabs. Selecting "Spotify" shows the empty state with the URL input.

- [ ] **Step 3: Commit**

```bash
git add VideoDownloader/App/MainView.swift
git commit -m "feat: add Spotify tab to MainView"
```

---

## Task 13: End-to-end manual integration test

**Files:** none (manual verification only)

- [ ] **Step 1: Build Release artifact**

```bash
xcodebuild -project VideoDownloader.xcodeproj -scheme VideoDownloader -configuration Release \
  -derivedDataPath "/Volumes/1tb /claude code projects /DerivedData/VideoDownloader" \
  build
cp -R "/Volumes/1tb /claude code projects /DerivedData/VideoDownloader/Build/Products/Release/VideoDownloader.app" \
      "/Applications/Video Downloader v3.app"
```

- [ ] **Step 2: First-run permission grants**

Open `/Applications/Video Downloader v3.app`. Click the Spotify tab. Paste a SHORT public playlist URL (3 tracks max for first test). Click Load → preview should appear. Click Start Capture → choose output folder.

- macOS will prompt for: Apple Events permission for `com.spotify.client` — grant.
- macOS will prompt for: System audio recording permission (CoreAudio Process Tap) — grant.

- [ ] **Step 3: Verify capture**

Watch the capture view. Expected:
- Spotify launches (if not running) and starts playing the playlist
- Each track appears as "complete" after Spotify advances
- WAV + MP3 files appear in the chosen folder, named `01 - Artist - Title.wav` etc.
- ID3 tags on the MP3 are correct (verify with `afinfo` or by opening in Music.app)
- After the last track, the UI shows "Captured N tracks" with an "Open in Finder" button

- [ ] **Step 4: Document any deviations**

If a step fails, capture the error from the UI and the most recent debug log (`/tmp/vd-last-download.log` for yt-dlp; we will likely add a parallel `/tmp/vd-last-spotify.log` for Spotify capture issues if needed).

- [ ] **Step 5: Commit if there were any small fixes**

```bash
git add -A
git commit -m "fix: end-to-end Spotify capture polish"
```

---

## Out-of-scope reminders (do not implement now)

- Spotify Web API integration — defer to future spec
- Search within Spotify catalog — defer
- Multi-playlist queue — defer
- Episodes / podcasts — defer
- Resume capture from partial state — defer (manual re-run for now)
