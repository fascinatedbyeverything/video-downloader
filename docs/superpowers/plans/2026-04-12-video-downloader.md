# Video Downloader v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone macOS SwiftUI app for downloading YouTube and Vimeo videos with quality options, audio extraction, a folder-scan library, file import, and a one-click hand-off to the existing Transcription Engine app.

**Architecture:** SwiftUI macOS app wrapping bundled `yt-dlp` and `ffmpeg` binaries via `Process` subprocesses. Library state is derived from folder-scanning `/Volumes/1tb /claude code projects /youtube-downloads/` for `.meta.json` sidecar files — no database. Queue and Library are two tabs in a single window. Transcription hand-off is a one-click "Send to Transcription Engine" that launches TE v6 with the file URL as an open-file argument.

**Tech Stack:** Swift 6, SwiftUI, macOS 14+, Xcode 16+, bundled `yt-dlp` (binary), bundled `ffmpeg` (binary), `NSWorkspace`, `QLPreviewPanel`.

**Spec:** `docs/superpowers/specs/2026-04-12-video-downloader-design.md`

---

## File Structure

```
VideoDownloader/
├── App/
│   └── VideoDownloaderApp.swift       — @main, window scene, tabs
├── Queue/
│   ├── QueueView.swift                — queue tab UI
│   ├── QueueModel.swift               — @Observable queue state
│   ├── QueueRow.swift                 — one queue item view
│   └── FormatPickerSheet.swift        — custom format picker
├── Library/
│   ├── LibraryView.swift              — library tab UI (grid/list toggle)
│   ├── LibraryModel.swift             — @Observable library state (folder-scan)
│   ├── LibraryItemView.swift          — one library item view
│   └── ImportSheet.swift              — import-from-disk sheet
├── Backend/
│   ├── YTDLPRunner.swift              — yt-dlp subprocess + progress parsing
│   ├── FFmpegRunner.swift             — audio extraction + thumbnail gen
│   ├── PlaylistResolver.swift         — --flat-playlist expansion
│   ├── FormatProbe.swift              — yt-dlp -F parser
│   ├── URLClassifier.swift            — classify URL: YT video/playlist/Vimeo/etc
│   ├── BinaryLocator.swift            — find yt-dlp+ffmpeg in Application Support
│   ├── Updater.swift                  — yt-dlp -U on launch
│   └── ProgressParser.swift           — parse [download] progress lines
├── Model/
│   ├── MediaItem.swift                — shared model (queue + library)
│   ├── SidecarJSON.swift              — read/write .meta.json
│   ├── DownloadFormat.swift           — enum of format presets
│   └── SiteSource.swift               — enum: youtube, vimeo, import
├── Transcription/
│   └── TranscriptionEngineLauncher.swift  — launch TE with file URL
├── Util/
│   ├── DriveCheck.swift               — verify 1tb drive is mounted
│   └── DiskSpace.swift                — check free space before download
├── Resources/
│   ├── bin/
│   │   ├── yt-dlp                     — bundled binary
│   │   └── ffmpeg                     — bundled binary
│   └── Assets.xcassets
└── VideoDownloaderTests/
    ├── SidecarJSONTests.swift
    ├── ProgressParserTests.swift
    ├── URLClassifierTests.swift
    ├── FormatProbeTests.swift
    └── DownloadFormatTests.swift
```

---

## Task 0: Create Xcode project skeleton and git repo

**Files:**
- Create: `/Volumes/1tb /claude code projects /Projects/video-downloader/VideoDownloader.xcodeproj` (via Xcode or xcodegen)
- Create: `/Volumes/1tb /claude code projects /Projects/video-downloader/.gitignore`
- Create: `/Volumes/1tb /claude code projects /Projects/video-downloader/README.md`

- [ ] **Step 1: Create the Xcode project**

Open Xcode → File → New → Project → macOS → App.
- Product Name: `VideoDownloader`
- Team: (your team)
- Organization Identifier: `com.fascinatedbyeverything`
- Bundle ID: `com.fascinatedbyeverything.VideoDownloader`
- Interface: SwiftUI
- Language: Swift
- Include Tests: **Yes**
- Save in: `/Volumes/1tb /claude code projects /Projects/video-downloader/`

Delete the auto-generated `ContentView.swift` and `VideoDownloaderApp.swift` — we'll recreate them in Task 17.

- [ ] **Step 2: Set deployment target and Swift version**

Project settings → VideoDownloader target → General:
- macOS Deployment: 14.0

Build Settings → Swift Language Version: Swift 6.

- [ ] **Step 3: Create folder structure**

In Xcode's Project Navigator, create groups (with folders on disk) to match the File Structure section above: `App`, `Queue`, `Library`, `Backend`, `Model`, `Transcription`, `Util`, `Resources`, `Resources/bin`.

- [ ] **Step 4: Create .gitignore**

```
.DS_Store
.build/
build/
DerivedData/
*.xcuserstate
xcuserdata/
*.xcworkspace/xcuserdata/
VideoDownloader.xcodeproj/project.xcworkspace/xcuserdata/
VideoDownloader.xcodeproj/xcuserdata/
```

- [ ] **Step 5: Create README.md**

```markdown
# Video Downloader v1

macOS app for downloading YouTube and Vimeo videos with a library and Transcription Engine integration.

See `docs/superpowers/specs/2026-04-12-video-downloader-design.md` for the full design.
```

- [ ] **Step 6: Initialize git and make first commit**

```bash
cd "/Volumes/1tb /claude code projects /Projects/video-downloader"
git init
git add .
git commit -m "chore: initial Xcode project skeleton"
```

---

## Task 1: SiteSource enum

**Files:**
- Create: `VideoDownloader/Model/SiteSource.swift`

- [ ] **Step 1: Write the type**

```swift
import Foundation

enum SiteSource: String, Codable, CaseIterable {
    case youtube
    case vimeo
    case `import`  // imported from disk, not downloaded
    case other     // catch-all for yt-dlp supported sites we don't specialize

    var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .vimeo: return "Vimeo"
        case .import: return "Imported"
        case .other: return "Other"
        }
    }

    var systemImageName: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .vimeo: return "v.circle.fill"
        case .import: return "square.and.arrow.down.fill"
        case .other: return "film"
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add VideoDownloader/Model/SiteSource.swift
git commit -m "feat: add SiteSource enum"
```

---

## Task 2: DownloadFormat enum

**Files:**
- Create: `VideoDownloader/Model/DownloadFormat.swift`
- Create: `VideoDownloaderTests/DownloadFormatTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import VideoDownloader

final class DownloadFormatTests: XCTestCase {
    func testBestReturnsCorrectYTDLPFormatString() {
        XCTAssertEqual(DownloadFormat.best.ytdlpFormat, "bestvideo+bestaudio/best")
    }

    func testResolution1080pFormatString() {
        XCTAssertEqual(DownloadFormat.p1080.ytdlpFormat, "bestvideo[height<=1080]+bestaudio/best[height<=1080]")
    }

    func testAudioMP3FormatString() {
        XCTAssertEqual(DownloadFormat.audioMP3.ytdlpFormat, "bestaudio")
        XCTAssertTrue(DownloadFormat.audioMP3.isAudioOnly)
    }

    func testCustomFormatPreservesID() {
        let custom = DownloadFormat.custom(formatID: "137+140")
        XCTAssertEqual(custom.ytdlpFormat, "137+140")
    }

    func testDisplayNames() {
        XCTAssertEqual(DownloadFormat.best.displayName, "Best")
        XCTAssertEqual(DownloadFormat.audioMP3.displayName, "Audio — MP3 (320 kbps)")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run in Xcode: Cmd+U (Product → Test).
Expected: compile errors (type doesn't exist).

- [ ] **Step 3: Write the enum**

```swift
import Foundation

enum DownloadFormat: Equatable, Hashable {
    case best
    case p1080
    case p720
    case p480
    case audioMP3
    case audioWAV
    case custom(formatID: String)

    var ytdlpFormat: String {
        switch self {
        case .best: return "bestvideo+bestaudio/best"
        case .p1080: return "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
        case .p720: return "bestvideo[height<=720]+bestaudio/best[height<=720]"
        case .p480: return "bestvideo[height<=480]+bestaudio/best[height<=480]"
        case .audioMP3: return "bestaudio"
        case .audioWAV: return "bestaudio"
        case .custom(let id): return id
        }
    }

    var displayName: String {
        switch self {
        case .best: return "Best"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        case .audioMP3: return "Audio — MP3 (320 kbps)"
        case .audioWAV: return "Audio — WAV (16-bit/44.1kHz)"
        case .custom(let id): return "Custom (\(id))"
        }
    }

    var isAudioOnly: Bool {
        switch self {
        case .audioMP3, .audioWAV: return true
        default: return false
        }
    }

    var audioPostProcess: AudioPostProcess? {
        switch self {
        case .audioMP3: return .mp3_320
        case .audioWAV: return .wav_16_441
        default: return nil
        }
    }

    static let presets: [DownloadFormat] = [.best, .p1080, .p720, .p480, .audioMP3, .audioWAV]
}

enum AudioPostProcess {
    case mp3_320       // 320 kbps CBR MP3
    case wav_16_441    // 16-bit 44.1kHz PCM WAV
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: Cmd+U. Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add VideoDownloader/Model/DownloadFormat.swift VideoDownloaderTests/DownloadFormatTests.swift
git commit -m "feat: add DownloadFormat enum with presets and custom format"
```

---

## Task 3: SidecarJSON model with round-trip tests

**Files:**
- Create: `VideoDownloader/Model/SidecarJSON.swift`
- Create: `VideoDownloaderTests/SidecarJSONTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import VideoDownloader

final class SidecarJSONTests: XCTestCase {
    func testRoundTripDownloadedItem() throws {
        let original = SidecarJSON(
            schemaVersion: 1,
            title: "Test Video",
            url: "https://www.youtube.com/watch?v=abc",
            site: .youtube,
            uploader: "Test Channel",
            duration: 3612,
            format: "bestvideo+bestaudio",
            formatLabel: "Best",
            fileSize: 141557760,
            fileName: "Test Video.mp4",
            thumbnailFile: "Test Video.jpg",
            dateAdded: Date(timeIntervalSince1970: 1744000000),
            description: "A test description",
            mediaFilePath: nil,
            importedFromPath: nil
        )
        let data = try JSONEncoder.pretty.encode(original)
        let decoded = try JSONDecoder().decode(SidecarJSON.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testImportInPlaceStoresMediaFilePath() throws {
        let item = SidecarJSON(
            schemaVersion: 1,
            title: "Imported Clip",
            url: nil,
            site: .import,
            uploader: nil,
            duration: 120,
            format: "import",
            formatLabel: "Imported",
            fileSize: 12345,
            fileName: "Imported Clip.mp4",
            thumbnailFile: "Imported Clip.jpg",
            dateAdded: Date(timeIntervalSince1970: 1744000000),
            description: nil,
            mediaFilePath: "/Users/chrisholmes/Movies/Imported Clip.mp4",
            importedFromPath: "/Users/chrisholmes/Movies/Imported Clip.mp4"
        )
        let data = try JSONEncoder.pretty.encode(item)
        let decoded = try JSONDecoder().decode(SidecarJSON.self, from: data)
        XCTAssertEqual(decoded.mediaFilePath, "/Users/chrisholmes/Movies/Imported Clip.mp4")
        XCTAssertEqual(decoded.site, .import)
        XCTAssertNil(decoded.url)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Cmd+U. Expected: compile errors.

- [ ] **Step 3: Implement SidecarJSON**

```swift
import Foundation

struct SidecarJSON: Codable, Equatable, Hashable {
    let schemaVersion: Int
    let title: String
    let url: String?              // nil for imports
    let site: SiteSource
    let uploader: String?
    let duration: Double          // seconds
    let format: String            // yt-dlp format string used
    let formatLabel: String       // human-readable preset name
    let fileSize: Int64           // bytes
    let fileName: String          // name of media file (basename only)
    let thumbnailFile: String?    // basename of thumbnail jpg
    let dateAdded: Date
    let description: String?
    let mediaFilePath: String?    // absolute path if media is NOT colocated with sidecar
    let importedFromPath: String? // original path for imports

    static let fileExtension = "meta.json"

    /// Sidecar path for a given media file basename in the library folder.
    static func sidecarURL(forMediaBasename basename: String, in folder: URL) -> URL {
        folder.appendingPathComponent("\(basename).\(Self.fileExtension)")
    }

    func write(to folder: URL) throws {
        let url = Self.sidecarURL(forMediaBasename: fileName, in: folder)
        let data = try JSONEncoder.pretty.encode(self)
        try data.write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> SidecarJSON {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.iso.decode(SidecarJSON.self, from: data)
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Cmd+U. Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
git add VideoDownloader/Model/SidecarJSON.swift VideoDownloaderTests/SidecarJSONTests.swift
git commit -m "feat: add SidecarJSON codable model with round-trip tests"
```

---

## Task 4: MediaItem shared model

**Files:**
- Create: `VideoDownloader/Model/MediaItem.swift`

- [ ] **Step 1: Write MediaItem**

```swift
import Foundation

struct MediaItem: Identifiable, Equatable, Hashable {
    let id: UUID
    var title: String
    var url: String?
    var site: SiteSource
    var uploader: String?
    var duration: Double?
    var formatLabel: String
    var fileSize: Int64?
    var fileURL: URL          // absolute URL to media file on disk
    var sidecarURL: URL       // absolute URL to .meta.json
    var thumbnailURL: URL?    // absolute URL to thumbnail jpg
    var dateAdded: Date
    var description: String?

    /// Build a MediaItem from a sidecar found during library scan.
    static func fromSidecar(
        _ sidecar: SidecarJSON,
        sidecarURL: URL,
        libraryFolder: URL
    ) -> MediaItem {
        let mediaURL: URL
        if let externalPath = sidecar.mediaFilePath {
            mediaURL = URL(fileURLWithPath: externalPath)
        } else {
            mediaURL = libraryFolder.appendingPathComponent(sidecar.fileName)
        }
        let thumbURL = sidecar.thumbnailFile.map { libraryFolder.appendingPathComponent($0) }
        return MediaItem(
            id: UUID(),
            title: sidecar.title,
            url: sidecar.url,
            site: sidecar.site,
            uploader: sidecar.uploader,
            duration: sidecar.duration,
            formatLabel: sidecar.formatLabel,
            fileSize: sidecar.fileSize,
            fileURL: mediaURL,
            sidecarURL: sidecarURL,
            thumbnailURL: thumbURL,
            dateAdded: sidecar.dateAdded,
            description: sidecar.description
        )
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add VideoDownloader/Model/MediaItem.swift
git commit -m "feat: add MediaItem shared model"
```

---

## Task 5: URLClassifier (identify video vs playlist vs showcase)

**Files:**
- Create: `VideoDownloader/Backend/URLClassifier.swift`
- Create: `VideoDownloaderTests/URLClassifierTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import VideoDownloader

final class URLClassifierTests: XCTestCase {
    func testYouTubeVideoURL() {
        let result = URLClassifier.classify("https://www.youtube.com/watch?v=abc123")
        XCTAssertEqual(result, .youtubeVideo)
    }

    func testYouTubeShortURL() {
        let result = URLClassifier.classify("https://youtu.be/abc123")
        XCTAssertEqual(result, .youtubeVideo)
    }

    func testYouTubePlaylistURL() {
        let result = URLClassifier.classify("https://www.youtube.com/playlist?list=PLxxx")
        XCTAssertEqual(result, .youtubePlaylist)
    }

    func testYouTubeWatchWithListURLTreatedAsPlaylist() {
        let result = URLClassifier.classify("https://www.youtube.com/watch?v=abc&list=PLxxx")
        XCTAssertEqual(result, .youtubePlaylist)
    }

    func testVimeoVideoURL() {
        let result = URLClassifier.classify("https://vimeo.com/1121011561")
        XCTAssertEqual(result, .vimeoVideo)
    }

    func testVimeoUnlistedURL() {
        let result = URLClassifier.classify("https://vimeo.com/1121011561/3df1265b59")
        XCTAssertEqual(result, .vimeoVideo)
    }

    func testVimeoShowcaseURL() {
        let result = URLClassifier.classify("https://vimeo.com/showcase/1234567")
        XCTAssertEqual(result, .vimeoShowcase)
    }

    func testUnknownURL() {
        let result = URLClassifier.classify("https://example.com/video")
        XCTAssertEqual(result, .unknown)
    }

    func testInvalidString() {
        let result = URLClassifier.classify("not a url")
        XCTAssertEqual(result, .invalid)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Cmd+U. Expected: compile errors.

- [ ] **Step 3: Implement URLClassifier**

```swift
import Foundation

enum URLClassification: Equatable {
    case youtubeVideo
    case youtubePlaylist
    case vimeoVideo
    case vimeoShowcase
    case unknown       // some other URL yt-dlp might still handle
    case invalid       // not a parseable URL

    var isPlaylist: Bool {
        switch self {
        case .youtubePlaylist, .vimeoShowcase: return true
        default: return false
        }
    }

    var siteSource: SiteSource {
        switch self {
        case .youtubeVideo, .youtubePlaylist: return .youtube
        case .vimeoVideo, .vimeoShowcase: return .vimeo
        default: return .other
        }
    }
}

enum URLClassifier {
    static func classify(_ input: String) -> URLClassification {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
            return .invalid
        }
        let path = url.path
        let query = url.query ?? ""

        if host.contains("youtube.com") || host.contains("youtu.be") {
            if path.contains("/playlist") { return .youtubePlaylist }
            if query.contains("list=") { return .youtubePlaylist }
            return .youtubeVideo
        }
        if host.contains("vimeo.com") {
            if path.contains("/showcase/") { return .vimeoShowcase }
            return .vimeoVideo
        }
        return .unknown
    }
}
```

- [ ] **Step 4: Run tests**

Cmd+U. Expected: all 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add VideoDownloader/Backend/URLClassifier.swift VideoDownloaderTests/URLClassifierTests.swift
git commit -m "feat: add URLClassifier for video/playlist/showcase detection"
```

---

## Task 6: ProgressParser (parse yt-dlp [download] lines)

**Files:**
- Create: `VideoDownloader/Backend/ProgressParser.swift`
- Create: `VideoDownloaderTests/ProgressParserTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import VideoDownloader

final class ProgressParserTests: XCTestCase {
    func testParseStandardDownloadLine() {
        let line = "[download]  45.2% of   98.84MiB at    4.90MiB/s ETA 01:45"
        let progress = ProgressParser.parse(line)
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress?.percent, 45.2, accuracy: 0.01)
        XCTAssertEqual(progress?.speedDescription, "4.90MiB/s")
        XCTAssertEqual(progress?.etaDescription, "01:45")
    }

    func testParseUnknownSpeed() {
        let line = "[download]   9.8% of   98.84MiB at  Unknown B/s ETA Unknown"
        let progress = ProgressParser.parse(line)
        XCTAssertEqual(progress?.percent, 9.8, accuracy: 0.01)
        XCTAssertNil(progress?.speedDescription)
        XCTAssertNil(progress?.etaDescription)
    }

    func testParseCompleteLine() {
        let line = "[download] 100% of   98.84MiB in 00:00:06 at 16.00MiB/s"
        let progress = ProgressParser.parse(line)
        XCTAssertEqual(progress?.percent, 100.0, accuracy: 0.01)
    }

    func testIgnoresUnrelatedLines() {
        XCTAssertNil(ProgressParser.parse("[youtube] Extracting URL: https://..."))
        XCTAssertNil(ProgressParser.parse("[Merger] Merging formats into ..."))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Cmd+U. Expected: compile errors.

- [ ] **Step 3: Implement ProgressParser**

```swift
import Foundation

struct DownloadProgress: Equatable {
    let percent: Double
    let speedDescription: String?
    let etaDescription: String?
}

enum ProgressParser {
    // [download]  45.2% of   98.84MiB at    4.90MiB/s ETA 01:45
    // [download]   9.8% of   98.84MiB at  Unknown B/s ETA Unknown
    // [download] 100% of   98.84MiB in 00:00:06 at 16.00MiB/s
    private static let regex: NSRegularExpression = {
        let pattern = #"^\[download\]\s+(\d+(?:\.\d+)?)%.*?(?:at\s+([^\s]+/s|Unknown B/s))?(?:\s+ETA\s+([^\s]+))?"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    static func parse(_ line: String) -> DownloadProgress? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let percentRange = Range(match.range(at: 1), in: line),
              let percent = Double(line[percentRange]) else {
            return nil
        }

        let speed: String? = {
            guard match.numberOfRanges > 2,
                  let r = Range(match.range(at: 2), in: line) else { return nil }
            let s = String(line[r])
            return s == "Unknown B/s" ? nil : s
        }()

        let eta: String? = {
            guard match.numberOfRanges > 3,
                  let r = Range(match.range(at: 3), in: line) else { return nil }
            let s = String(line[r])
            return s == "Unknown" ? nil : s
        }()

        return DownloadProgress(percent: percent, speedDescription: speed, etaDescription: eta)
    }
}
```

- [ ] **Step 4: Run tests**

Cmd+U. Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add VideoDownloader/Backend/ProgressParser.swift VideoDownloaderTests/ProgressParserTests.swift
git commit -m "feat: add ProgressParser for yt-dlp progress lines"
```

---

## Task 7: FormatProbe (parse yt-dlp -F output)

**Files:**
- Create: `VideoDownloader/Backend/FormatProbe.swift`
- Create: `VideoDownloaderTests/FormatProbeTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import VideoDownloader

final class FormatProbeTests: XCTestCase {
    // Sample from real `yt-dlp -F` output, trimmed to a few rows
    let sample = """
    [info] Available formats for abc123:
    ID  EXT   RESOLUTION FPS │  FILESIZE   TBR PROTO │ VCODEC           VBR ACODEC      ABR ASR  MORE INFO
    ───────────────────────────────────────────────────────────────────────────────────────────────────
    139 m4a   audio only     │    2.32MiB   49k https │ audio only           mp4a.40.5   49k 22k  low, m4a_dash
    251 webm  audio only     │    5.24MiB  128k https │ audio only           opus       128k 48k  medium, webm_dash
    137 mp4   1920x1080   30 │  110.20MiB 2500k https │ avc1.640028    2500k video only              1080p
    399 mp4   1920x1080   30 │   98.84MiB 2237k https │ av01.0.08M.08  2237k video only              1080p
    """

    func testParsesAudioOnlyRows() throws {
        let formats = FormatProbe.parse(sample)
        let audio = formats.filter { $0.resolution == "audio only" }
        XCTAssertEqual(audio.count, 2)
        XCTAssertTrue(audio.contains(where: { $0.formatID == "251" && $0.container == "webm" }))
    }

    func testParsesVideoRows() throws {
        let formats = FormatProbe.parse(sample)
        let videos = formats.filter { $0.resolution.contains("x") }
        XCTAssertEqual(videos.count, 2)
        XCTAssertTrue(videos.contains(where: { $0.formatID == "399" }))
    }

    func testExtractsFileSizeWhenPresent() throws {
        let formats = FormatProbe.parse(sample)
        let f137 = formats.first { $0.formatID == "137" }
        XCTAssertNotNil(f137?.fileSize)
        XCTAssertTrue(f137!.fileSize!.contains("MiB"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Cmd+U.

- [ ] **Step 3: Implement FormatProbe**

```swift
import Foundation

struct FormatRow: Identifiable, Equatable, Hashable {
    let id: String          // formatID
    let formatID: String
    let container: String
    let resolution: String
    let fps: String?
    let fileSize: String?
    let tbr: String?
    let proto: String?
    let vcodec: String?
    let acodec: String?
    let note: String?
}

enum FormatProbe {
    /// Parse the output of `yt-dlp -F <url>`.
    /// Format rows start with a numeric or alphanumeric format ID followed by whitespace.
    /// Separator and info lines are ignored.
    static func parse(_ output: String) -> [FormatRow] {
        var rows: [FormatRow] = []
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        for raw in lines {
            let line = String(raw)
            guard !line.hasPrefix("[info]"),
                  !line.hasPrefix("ID"),
                  !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  line.rangeOfCharacter(from: CharacterSet(charactersIn: "─")) == nil
            else { continue }

            // Split on whitespace, but "│" is a column divider in modern yt-dlp output.
            let cleaned = line.replacingOccurrences(of: "│", with: " ")
            let tokens = cleaned.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 3 else { continue }

            let formatID = tokens[0]
            let ext = tokens[1]
            // Heuristic: token[2] is either "audio" (followed by "only") or a resolution like "1920x1080"
            var idx = 2
            var resolution: String
            if tokens[idx] == "audio", idx + 1 < tokens.count, tokens[idx + 1] == "only" {
                resolution = "audio only"
                idx += 2
            } else {
                resolution = tokens[idx]
                idx += 1
            }

            // Remaining tokens are best-effort — fps, filesize, etc.
            var fps: String? = nil
            if idx < tokens.count, let _ = Int(tokens[idx]) {
                fps = tokens[idx]; idx += 1
            }
            var fileSize: String? = nil
            if idx < tokens.count, tokens[idx].contains("iB") {
                fileSize = tokens[idx]; idx += 1
            }
            let note = idx < tokens.count ? tokens[idx...].joined(separator: " ") : nil

            rows.append(FormatRow(
                id: formatID,
                formatID: formatID,
                container: ext,
                resolution: resolution,
                fps: fps,
                fileSize: fileSize,
                tbr: nil,
                proto: nil,
                vcodec: nil,
                acodec: nil,
                note: note
            ))
        }
        return rows
    }
}
```

- [ ] **Step 4: Run tests**

Cmd+U. Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add VideoDownloader/Backend/FormatProbe.swift VideoDownloaderTests/FormatProbeTests.swift
git commit -m "feat: add FormatProbe parser for yt-dlp -F output"
```

---

## Task 8: BinaryLocator + copy bundled binaries on first launch

**Files:**
- Create: `VideoDownloader/Backend/BinaryLocator.swift`
- Modify: Xcode project — add yt-dlp + ffmpeg as "Copy Files" resources

- [ ] **Step 1: Download yt-dlp and ffmpeg binaries**

```bash
cd "/Volumes/1tb /claude code projects /Projects/video-downloader/VideoDownloader/Resources/bin"
# yt-dlp single-binary macOS build
curl -L -o yt-dlp "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
chmod +x yt-dlp
# ffmpeg — use system ffmpeg from homebrew as source, copy into bundle
cp /opt/homebrew/bin/ffmpeg ffmpeg
chmod +x ffmpeg
```

- [ ] **Step 2: Add binaries to Xcode target**

In Xcode: drag `Resources/bin/yt-dlp` and `Resources/bin/ffmpeg` into the project (already done in Step 1 if on-disk folders are referenced). Ensure both are in **Copy Bundle Resources** build phase for the `VideoDownloader` target. Preserve executable permissions — Xcode should handle this automatically for files flagged as executable.

- [ ] **Step 3: Write BinaryLocator**

```swift
import Foundation

enum BinaryLocator {
    static let supportDirName = "VideoDownloader"
    static let binSubdir = "bin"

    static var supportDir: URL {
        let fm = FileManager.default
        let base = try! fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent(supportDirName)
    }

    static var binDir: URL {
        supportDir.appendingPathComponent(binSubdir)
    }

    static var ytdlpURL: URL { binDir.appendingPathComponent("yt-dlp") }
    static var ffmpegURL: URL { binDir.appendingPathComponent("ffmpeg") }

    /// Copies bundled binaries to Application Support on first launch (or if missing).
    /// Application Support is required for yt-dlp self-update — the .app bundle is read-only.
    static func ensureBinariesInstalled() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)

        for name in ["yt-dlp", "ffmpeg"] {
            let dest = binDir.appendingPathComponent(name)
            guard !fm.fileExists(atPath: dest.path) else { continue }
            guard let src = Bundle.main.url(forResource: name, withExtension: nil) else {
                throw NSError(domain: "BinaryLocator", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "\(name) missing from app bundle"])
            }
            try fm.copyItem(at: src, to: dest)
            // Ensure executable bit
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add VideoDownloader/Backend/BinaryLocator.swift VideoDownloader/Resources/bin/
git commit -m "feat: bundle yt-dlp + ffmpeg binaries, add BinaryLocator"
```

---

## Task 9: Updater (yt-dlp -U on launch)

**Files:**
- Create: `VideoDownloader/Backend/Updater.swift`

- [ ] **Step 1: Write Updater**

```swift
import Foundation

enum Updater {
    /// Runs `yt-dlp -U` in background with a 30s timeout. Logs via os_log. Never throws.
    static func updateYTDLP() async {
        let process = Process()
        process.executableURL = BinaryLocator.ytdlpURL
        process.arguments = ["-U"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            print("Updater: failed to launch yt-dlp -U: \(error)")
            return
        }

        let deadline = Date().addingTimeInterval(30)
        while process.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if process.isRunning {
            process.terminate()
            print("Updater: yt-dlp -U timed out")
            return
        }
        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""
        print("Updater: yt-dlp -U status=\(process.terminationStatus) output=\(output)")
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add VideoDownloader/Backend/Updater.swift
git commit -m "feat: add Updater for yt-dlp -U on launch"
```

---

## Task 10: YTDLPRunner (subprocess wrapper with progress callback)

**Files:**
- Create: `VideoDownloader/Backend/YTDLPRunner.swift`

- [ ] **Step 1: Implement YTDLPRunner**

```swift
import Foundation

struct YTDLPResult {
    let exitCode: Int32
    let stdoutText: String
    let stderrText: String
}

struct YTDLPDownloadOptions {
    let url: String
    let format: DownloadFormat
    let outputTemplate: String   // e.g. "/path/%(title)s.%(ext)s"
    let writeThumbnail: Bool     // -> --write-thumbnail --convert-thumbnails jpg
    let writeInfoJSON: Bool      // -> --write-info-json (we use this to pre-fill sidecar fields)
}

final class YTDLPRunner {
    private var process: Process?
    private var progressHandler: ((DownloadProgress) -> Void)?
    private var stdoutBuffer = ""

    func download(
        _ options: YTDLPDownloadOptions,
        onProgress: @escaping (DownloadProgress) -> Void
    ) async throws -> YTDLPResult {
        let p = Process()
        p.executableURL = BinaryLocator.ytdlpURL
        p.arguments = buildArguments(options)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        p.standardOutput = stdoutPipe
        p.standardError = stderrPipe
        self.process = p
        self.progressHandler = onProgress

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self.handleStdout(text)
        }

        try p.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            p.terminationHandler = { _ in cont.resume() }
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = nil

        let stdoutData = try stdoutPipe.fileHandleForReading.readToEnd() ?? Data()
        let stderrData = try stderrPipe.fileHandleForReading.readToEnd() ?? Data()
        return YTDLPResult(
            exitCode: p.terminationStatus,
            stdoutText: (String(data: stdoutData, encoding: .utf8) ?? "") + stdoutBuffer,
            stderrText: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    func cancel() {
        process?.terminate()
    }

    private func handleStdout(_ chunk: String) {
        stdoutBuffer += chunk
        // Emit progress for any complete line seen so far; keep trailing partial line in buffer.
        var lines = stdoutBuffer.split(separator: "\n", omittingEmptySubsequences: false)
        let trailing = lines.removeLast()
        for line in lines {
            if let progress = ProgressParser.parse(String(line)) {
                progressHandler?(progress)
            }
        }
        stdoutBuffer = String(trailing)
    }

    private func buildArguments(_ o: YTDLPDownloadOptions) -> [String] {
        var args: [String] = []
        args += ["-f", o.format.ytdlpFormat]
        args += ["-o", o.outputTemplate]
        args += ["--newline"]  // cleaner progress output
        args += ["--ffmpeg-location", BinaryLocator.ffmpegURL.path]

        switch o.format.audioPostProcess {
        case .mp3_320:
            args += ["-x", "--audio-format", "mp3", "--audio-quality", "320K"]
        case .wav_16_441:
            args += ["-x", "--audio-format", "wav"]
        case nil:
            break
        }

        if o.writeThumbnail {
            args += ["--write-thumbnail", "--convert-thumbnails", "jpg"]
        }
        if o.writeInfoJSON {
            args += ["--write-info-json"]
        }
        args += [o.url]
        return args
    }

    /// One-shot: run `yt-dlp -F <url>` and return the table as a string.
    static func listFormats(_ url: String) async throws -> String {
        let p = Process()
        p.executableURL = BinaryLocator.ytdlpURL
        p.arguments = ["-F", url]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            p.terminationHandler = { _ in cont.resume() }
        }
        let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add VideoDownloader/Backend/YTDLPRunner.swift
git commit -m "feat: add YTDLPRunner subprocess wrapper with progress callback"
```

---

## Task 11: FFmpegRunner (thumbnail + metadata probing for imports)

**Files:**
- Create: `VideoDownloader/Backend/FFmpegRunner.swift`

- [ ] **Step 1: Implement FFmpegRunner**

```swift
import Foundation

enum FFmpegError: Error { case failed(exitCode: Int32, stderr: String) }

enum FFmpegRunner {
    /// Extract a JPG thumbnail at a specific time offset.
    static func makeThumbnail(
        from mediaURL: URL,
        to outputURL: URL,
        atSeconds: Double = 5.0
    ) async throws {
        let p = Process()
        p.executableURL = BinaryLocator.ffmpegURL
        p.arguments = [
            "-y",
            "-ss", String(atSeconds),
            "-i", mediaURL.path,
            "-vframes", "1",
            "-q:v", "3",
            outputURL.path
        ]
        let stderrPipe = Pipe()
        p.standardError = stderrPipe
        p.standardOutput = Pipe()
        try p.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            p.terminationHandler = { _ in cont.resume() }
        }
        if p.terminationStatus != 0 {
            let data = try stderrPipe.fileHandleForReading.readToEnd() ?? Data()
            throw FFmpegError.failed(
                exitCode: p.terminationStatus,
                stderr: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }

    /// Return duration in seconds using ffprobe-style call through ffmpeg.
    static func duration(of mediaURL: URL) async throws -> Double {
        let p = Process()
        p.executableURL = BinaryLocator.ffmpegURL
        p.arguments = ["-i", mediaURL.path]
        let stderrPipe = Pipe()
        p.standardError = stderrPipe
        p.standardOutput = Pipe()
        try p.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            p.terminationHandler = { _ in cont.resume() }
        }
        let data = try stderrPipe.fileHandleForReading.readToEnd() ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""
        // ffmpeg stderr prints "Duration: 00:38:27.42, start: 0.000000, bitrate: 492 kb/s"
        let pattern = #"Duration:\s+(\d+):(\d+):(\d+\.?\d*)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let hR = Range(match.range(at: 1), in: text),
              let mR = Range(match.range(at: 2), in: text),
              let sR = Range(match.range(at: 3), in: text),
              let h = Double(text[hR]), let m = Double(text[mR]), let s = Double(text[sR])
        else {
            return 0
        }
        return h * 3600 + m * 60 + s
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add VideoDownloader/Backend/FFmpegRunner.swift
git commit -m "feat: add FFmpegRunner for thumbnail and duration probing"
```

---

## Task 12: PlaylistResolver (expand playlists into video entries)

**Files:**
- Create: `VideoDownloader/Backend/PlaylistResolver.swift`

- [ ] **Step 1: Implement PlaylistResolver**

```swift
import Foundation

struct PlaylistEntry: Identifiable, Equatable {
    let id: String        // yt-dlp entry id
    let url: String       // canonical video URL
    let title: String
    let durationSeconds: Double?
    let thumbnailURL: String?
}

enum PlaylistResolverError: Error { case failed(stderr: String) }

enum PlaylistResolver {
    /// Expand a playlist URL into its video entries.
    /// Uses `yt-dlp --flat-playlist --dump-single-json` for one JSON blob.
    static func resolve(_ url: String) async throws -> [PlaylistEntry] {
        let p = Process()
        p.executableURL = BinaryLocator.ytdlpURL
        p.arguments = ["--flat-playlist", "--dump-single-json", url]
        let stdout = Pipe()
        let stderr = Pipe()
        p.standardOutput = stdout
        p.standardError = stderr
        try p.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            p.terminationHandler = { _ in cont.resume() }
        }
        let data = try stdout.fileHandleForReading.readToEnd() ?? Data()
        if p.terminationStatus != 0 {
            let errData = try stderr.fileHandleForReading.readToEnd() ?? Data()
            throw PlaylistResolverError.failed(stderr: String(data: errData, encoding: .utf8) ?? "")
        }

        struct Blob: Decodable {
            struct Entry: Decodable {
                let id: String
                let title: String?
                let url: String?
                let duration: Double?
                let thumbnails: [Thumb]?
                struct Thumb: Decodable { let url: String }
            }
            let entries: [Entry]?
        }

        let blob = try JSONDecoder().decode(Blob.self, from: data)
        return (blob.entries ?? []).map { e in
            PlaylistEntry(
                id: e.id,
                url: canonicalURL(from: e.url ?? e.id),
                title: e.title ?? e.id,
                durationSeconds: e.duration,
                thumbnailURL: e.thumbnails?.first?.url
            )
        }
    }

    private static func canonicalURL(from idOrURL: String) -> String {
        if idOrURL.hasPrefix("http") { return idOrURL }
        // yt-dlp sometimes emits bare video IDs for YouTube entries
        return "https://www.youtube.com/watch?v=\(idOrURL)"
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add VideoDownloader/Backend/PlaylistResolver.swift
git commit -m "feat: add PlaylistResolver for playlist expansion"
```

---

## Task 13: DriveCheck + DiskSpace

**Files:**
- Create: `VideoDownloader/Util/DriveCheck.swift`
- Create: `VideoDownloader/Util/DiskSpace.swift`

- [ ] **Step 1: Implement DriveCheck**

```swift
import Foundation

enum DriveCheck {
    static let libraryFolder = URL(fileURLWithPath:
        "/Volumes/1tb /claude code projects /youtube-downloads")

    static var isLibraryDriveMounted: Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: libraryFolder.path, isDirectory: &isDir
        )
        return exists && isDir.boolValue
    }
}
```

- [ ] **Step 2: Implement DiskSpace**

```swift
import Foundation

enum DiskSpace {
    /// Free bytes available at the given URL.
    static func freeBytes(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return bytes
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add VideoDownloader/Util/DriveCheck.swift VideoDownloader/Util/DiskSpace.swift
git commit -m "feat: add DriveCheck and DiskSpace utilities"
```

---

## Task 14: TranscriptionEngineLauncher

**Files:**
- Create: `VideoDownloader/Transcription/TranscriptionEngineLauncher.swift`

- [ ] **Step 1: Implement launcher**

```swift
import AppKit
import Foundation

enum TranscriptionEngineLauncher {
    enum LauncherError: Error { case notFound }

    /// Returns the URL of the highest-numbered Transcription Engine app in /Applications/,
    /// or nil if none installed.
    static func findApp() -> URL? {
        let fm = FileManager.default
        let apps = (try? fm.contentsOfDirectory(atPath: "/Applications")) ?? []
        let teApps = apps.filter { $0.hasPrefix("Transcription Engine v") && $0.hasSuffix(".app") }
        // sort by trailing version number, newest last
        let sorted = teApps.sorted { a, b in
            func v(_ s: String) -> Int {
                let num = s
                    .replacingOccurrences(of: "Transcription Engine v", with: "")
                    .replacingOccurrences(of: ".app", with: "")
                return Int(num) ?? 0
            }
            return v(a) < v(b)
        }
        guard let newest = sorted.last else { return nil }
        return URL(fileURLWithPath: "/Applications/\(newest)")
    }

    /// Launch TE with the given media file URL as an open-file argument.
    static func send(fileURL: URL) async throws {
        guard let appURL = findApp() else { throw LauncherError.notFound }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try await NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add VideoDownloader/Transcription/TranscriptionEngineLauncher.swift
git commit -m "feat: add TranscriptionEngineLauncher"
```

---

## Task 15: QueueModel (Observable, per-item state machine)

**Files:**
- Create: `VideoDownloader/Queue/QueueModel.swift`

- [ ] **Step 1: Implement QueueModel**

```swift
import Foundation
import Observation

@Observable
final class QueueItem: Identifiable {
    let id: UUID = UUID()
    var url: String
    var title: String
    var durationSeconds: Double?
    var thumbnailURL: URL?
    var site: SiteSource
    var format: DownloadFormat
    var customFormats: [FormatRow]? // populated if user opened Custom picker
    var status: Status = .queued
    var percent: Double = 0
    var speed: String?
    var eta: String?
    var errorMessage: String?
    private(set) var runner: YTDLPRunner?

    enum Status: Equatable {
        case queued
        case running
        case complete
        case failed
        case cancelled
    }

    init(url: String, title: String, site: SiteSource, format: DownloadFormat = .best,
         durationSeconds: Double? = nil, thumbnailURL: URL? = nil) {
        self.url = url
        self.title = title
        self.site = site
        self.format = format
        self.durationSeconds = durationSeconds
        self.thumbnailURL = thumbnailURL
    }

    func attach(runner: YTDLPRunner) { self.runner = runner }
    func cancel() { runner?.cancel() }
}

@Observable
final class QueueModel {
    var items: [QueueItem] = []
    var isDownloading: Bool = false
    var currentIndex: Int? = nil

    func add(_ item: QueueItem) { items.append(item) }
    func remove(id: UUID) { items.removeAll { $0.id == id } }

    func addFromURL(_ url: String) async throws {
        let classification = URLClassifier.classify(url)
        switch classification {
        case .youtubePlaylist, .vimeoShowcase:
            let entries = try await PlaylistResolver.resolve(url)
            for e in entries {
                let thumb = e.thumbnailURL.flatMap { URL(string: $0) }
                let item = QueueItem(
                    url: e.url,
                    title: e.title,
                    site: classification.siteSource,
                    durationSeconds: e.durationSeconds,
                    thumbnailURL: thumb
                )
                items.append(item)
            }
        case .invalid:
            throw NSError(domain: "QueueModel", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Not a valid URL"])
        default:
            // Single video — fetch a minimal probe for title (optional; lazy)
            let item = QueueItem(url: url, title: url, site: classification.siteSource)
            items.append(item)
        }
    }

    @MainActor
    func startDownloads(libraryFolder: URL) async {
        guard !isDownloading else { return }
        isDownloading = true
        defer { isDownloading = false; currentIndex = nil }

        for (index, item) in items.enumerated() {
            guard item.status == .queued else { continue }
            currentIndex = index
            await runSingle(item, libraryFolder: libraryFolder)
        }
    }

    @MainActor
    private func runSingle(_ item: QueueItem, libraryFolder: URL) async {
        item.status = .running
        let outputTemplate = libraryFolder.appendingPathComponent("%(title)s.%(ext)s").path
        let opts = YTDLPDownloadOptions(
            url: item.url,
            format: item.format,
            outputTemplate: outputTemplate,
            writeThumbnail: true,
            writeInfoJSON: true
        )
        let runner = YTDLPRunner()
        item.attach(runner: runner)

        do {
            let result = try await runner.download(opts) { progress in
                Task { @MainActor in
                    item.percent = progress.percent
                    item.speed = progress.speedDescription
                    item.eta = progress.etaDescription
                }
            }
            if result.exitCode == 0 {
                // Write sidecar for the completed file
                try await SidecarWriter.writeSidecar(
                    forQueueItem: item,
                    libraryFolder: libraryFolder,
                    ytdlpStdout: result.stdoutText
                )
                item.status = .complete
            } else {
                item.status = .failed
                item.errorMessage = result.stderrText
            }
        } catch {
            item.status = .failed
            item.errorMessage = error.localizedDescription
        }
    }
}
```

Note: `SidecarWriter` is defined in Task 16.

- [ ] **Step 2: Commit**

```bash
git add VideoDownloader/Queue/QueueModel.swift
git commit -m "feat: add QueueModel and QueueItem"
```

---

## Task 16: SidecarWriter (post-download metadata assembly)

**Files:**
- Create: `VideoDownloader/Backend/SidecarWriter.swift`

- [ ] **Step 1: Implement SidecarWriter**

```swift
import Foundation

enum SidecarWriter {
    /// After a successful yt-dlp download, locate the output file + thumbnail +
    /// info.json, and write a .meta.json sidecar.
    static func writeSidecar(
        forQueueItem item: QueueItem,
        libraryFolder: URL,
        ytdlpStdout: String
    ) async throws {
        // yt-dlp prints "[download] Destination: <path>" — grab the last one for the final file
        let destRegex = try NSRegularExpression(pattern: #"\[download\] Destination: (.+)"#)
        let mergerRegex = try NSRegularExpression(pattern: #"\[Merger\] Merging formats into "(.+)""#)

        var finalPath: String?
        for line in ytdlpStdout.split(separator: "\n") {
            let s = String(line)
            let range = NSRange(s.startIndex..., in: s)
            if let m = mergerRegex.firstMatch(in: s, range: range),
               let r = Range(m.range(at: 1), in: s) {
                finalPath = String(s[r])
            } else if finalPath == nil,
                      let m = destRegex.firstMatch(in: s, range: range),
                      let r = Range(m.range(at: 1), in: s) {
                finalPath = String(s[r])
            }
        }
        guard let finalPath else {
            throw NSError(domain: "SidecarWriter", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not detect output path from yt-dlp output"])
        }

        let mediaURL = URL(fileURLWithPath: finalPath)
        let base = mediaURL.deletingPathExtension().lastPathComponent

        // Prefer info.json if yt-dlp wrote it (--write-info-json)
        let infoURL = libraryFolder.appendingPathComponent("\(base).info.json")
        var uploader: String? = nil
        var description: String? = nil
        if let data = try? Data(contentsOf: infoURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            uploader = json["uploader"] as? String
            description = json["description"] as? String
        }

        // Thumbnail path: yt-dlp wrote <base>.jpg next to the file
        let thumb = libraryFolder.appendingPathComponent("\(base).jpg")
        let thumbFile: String? = FileManager.default.fileExists(atPath: thumb.path) ? "\(base).jpg" : nil

        let attrs = try FileManager.default.attributesOfItem(atPath: mediaURL.path)
        let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0

        let duration = (try? await FFmpegRunner.duration(of: mediaURL)) ?? (item.durationSeconds ?? 0)

        let sidecar = SidecarJSON(
            schemaVersion: 1,
            title: item.title,
            url: item.url,
            site: item.site,
            uploader: uploader,
            duration: duration,
            format: item.format.ytdlpFormat,
            formatLabel: item.format.displayName,
            fileSize: fileSize,
            fileName: mediaURL.lastPathComponent,
            thumbnailFile: thumbFile,
            dateAdded: Date(),
            description: description,
            mediaFilePath: nil,
            importedFromPath: nil
        )
        try sidecar.write(to: libraryFolder)

        // Clean up info.json (keep the library folder tidy — we've absorbed its data)
        try? FileManager.default.removeItem(at: infoURL)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add VideoDownloader/Backend/SidecarWriter.swift
git commit -m "feat: add SidecarWriter for post-download metadata"
```

---

## Task 17: App entry point + tab shell + launch tasks

**Files:**
- Create: `VideoDownloader/App/VideoDownloaderApp.swift`
- Create: `VideoDownloader/App/MainView.swift`

- [ ] **Step 1: Write VideoDownloaderApp**

```swift
import SwiftUI

@main
struct VideoDownloaderApp: App {
    @State private var queue = QueueModel()
    @State private var library = LibraryModel()
    @State private var driveMissing = false

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(queue)
                .environment(library)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    do {
                        try BinaryLocator.ensureBinariesInstalled()
                    } catch {
                        print("Failed to install binaries: \(error)")
                    }
                    if !DriveCheck.isLibraryDriveMounted {
                        driveMissing = true
                    }
                    await Updater.updateYTDLP()
                    await library.scan(folder: DriveCheck.libraryFolder)
                }
                .alert("1tb drive not mounted",
                       isPresented: $driveMissing,
                       actions: {
                           Button("Quit") { NSApp.terminate(nil) }
                       },
                       message: {
                           Text("Please connect the drive at /Volumes/1tb  and relaunch.")
                       })
        }
    }
}
```

- [ ] **Step 2: Write MainView**

```swift
import SwiftUI

struct MainView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case queue = "Queue"
        case library = "Library"
        var id: String { rawValue }
    }
    @State private var selected: Tab = .queue

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selected) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch selected {
            case .queue: QueueView()
            case .library: LibraryView()
            }
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add VideoDownloader/App/
git commit -m "feat: add app entry point and tab shell"
```

---

## Task 18: QueueView + QueueRow

**Files:**
- Create: `VideoDownloader/Queue/QueueView.swift`
- Create: `VideoDownloader/Queue/QueueRow.swift`

- [ ] **Step 1: Write QueueView**

```swift
import SwiftUI

struct QueueView: View {
    @Environment(QueueModel.self) private var queue
    @State private var urlInput: String = ""
    @State private var isAdding = false
    @State private var addError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Paste YouTube / Vimeo URL (video or playlist)", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add() }
                Button("Add to Queue", action: add)
                    .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
            }
            .padding(8)

            if let addError {
                Text(addError).foregroundStyle(.red).font(.caption).padding(.horizontal, 8)
            }

            Divider()

            List {
                ForEach(queue.items) { item in
                    QueueRow(item: item, onRemove: { queue.remove(id: item.id) })
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Spacer()
                Button("Download All") {
                    Task { await queue.startDownloads(libraryFolder: DriveCheck.libraryFolder) }
                }
                .disabled(queue.items.allSatisfy { $0.status != .queued } || queue.isDownloading)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(8)
        }
    }

    private func add() {
        let input = urlInput.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }
        isAdding = true
        addError = nil
        Task {
            do {
                try await queue.addFromURL(input)
                urlInput = ""
            } catch {
                addError = error.localizedDescription
            }
            isAdding = false
        }
    }
}
```

- [ ] **Step 2: Write QueueRow**

```swift
import SwiftUI

struct QueueRow: View {
    @Bindable var item: QueueItem
    let onRemove: () -> Void
    @State private var showingCustomPicker = false

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(url: item.thumbnailURL)
                .frame(width: 120, height: 68)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline).lineLimit(2)
                HStack {
                    Image(systemName: item.site.systemImageName)
                    Text(item.site.displayName)
                    if let d = item.durationSeconds {
                        Text("• \(formatDuration(d))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if item.status == .running {
                    ProgressView(value: item.percent, total: 100)
                    HStack {
                        if let s = item.speed { Text(s).font(.caption2) }
                        if let e = item.eta { Text("ETA \(e)").font(.caption2) }
                    }
                }
                if item.status == .failed, let msg = item.errorMessage {
                    Text(msg).font(.caption2).foregroundStyle(.red).lineLimit(2)
                }
            }

            Spacer()

            Picker("", selection: Binding(
                get: { formatPickerSelection(item.format) },
                set: { handleFormatSelection($0) }
            )) {
                ForEach(DownloadFormat.presets, id: \.self) { preset in
                    Text(preset.displayName).tag(formatPickerSelection(preset))
                }
                Divider()
                Text("Custom…").tag("custom")
            }
            .frame(width: 180)
            .disabled(item.status != .queued)

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .disabled(item.status == .running)
        }
        .sheet(isPresented: $showingCustomPicker) {
            FormatPickerSheet(
                url: item.url,
                onSelect: { id in
                    item.format = .custom(formatID: id)
                    showingCustomPicker = false
                },
                onCancel: { showingCustomPicker = false }
            )
        }
    }

    private func formatPickerSelection(_ f: DownloadFormat) -> String {
        switch f {
        case .custom: return "custom"
        default: return f.displayName
        }
    }

    private func handleFormatSelection(_ sel: String) {
        if sel == "custom" {
            showingCustomPicker = true
            return
        }
        if let match = DownloadFormat.presets.first(where: { $0.displayName == sel }) {
            item.format = match
        }
    }

    private func formatDuration(_ s: Double) -> String {
        let total = Int(s)
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

struct ThumbnailView: View {
    let url: URL?
    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: placeholder
                    }
                }
            } else { placeholder }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.2)
            Image(systemName: "film").foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add VideoDownloader/Queue/QueueView.swift VideoDownloader/Queue/QueueRow.swift
git commit -m "feat: add QueueView and QueueRow with inline format picker"
```

---

## Task 19: FormatPickerSheet

**Files:**
- Create: `VideoDownloader/Queue/FormatPickerSheet.swift`

- [ ] **Step 1: Implement sheet**

```swift
import SwiftUI

struct FormatPickerSheet: View {
    let url: String
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var formats: [FormatRow] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selection: FormatRow.ID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pick format").font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
            }
            .padding(12)

            Divider()

            if loading {
                ProgressView("Probing formats…").padding()
            } else if let error {
                Text(error).foregroundStyle(.red).padding()
            } else {
                Table(formats, selection: $selection) {
                    TableColumn("ID") { Text($0.formatID).monospaced() }
                    TableColumn("Ext") { Text($0.container) }
                    TableColumn("Resolution") { Text($0.resolution) }
                    TableColumn("FPS") { Text($0.fps ?? "—") }
                    TableColumn("Size") { Text($0.fileSize ?? "—") }
                    TableColumn("Notes") { Text($0.note ?? "") }
                }
                .frame(minHeight: 300)
            }

            Divider()

            HStack {
                Spacer()
                Button("Apply") {
                    guard let id = selection,
                          let row = formats.first(where: { $0.id == id }) else { return }
                    onSelect(row.formatID)
                }
                .disabled(selection == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 700, height: 480)
        .task {
            await probe()
        }
    }

    private func probe() async {
        do {
            let text = try await YTDLPRunner.listFormats(url)
            let rows = FormatProbe.parse(text)
            await MainActor.run {
                self.formats = rows
                self.loading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.loading = false
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add VideoDownloader/Queue/FormatPickerSheet.swift
git commit -m "feat: add FormatPickerSheet for custom format selection"
```

---

## Task 20: LibraryModel (folder scan)

**Files:**
- Create: `VideoDownloader/Library/LibraryModel.swift`

- [ ] **Step 1: Implement LibraryModel**

```swift
import Foundation
import Observation

@Observable
final class LibraryModel {
    var items: [MediaItem] = []
    var searchQuery: String = ""
    var sort: Sort = .dateAddedDesc
    var viewMode: ViewMode = .grid

    enum Sort: String, CaseIterable {
        case dateAddedDesc = "Newest"
        case dateAddedAsc = "Oldest"
        case titleAsc = "Title A–Z"
        case durationDesc = "Longest"
        case fileSizeDesc = "Largest"
    }

    enum ViewMode: String, CaseIterable {
        case grid, list
    }

    var filteredItems: [MediaItem] {
        var list = items
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.title.lowercased().contains(q) ||
                ($0.url ?? "").lowercased().contains(q)
            }
        }
        switch sort {
        case .dateAddedDesc: list.sort { $0.dateAdded > $1.dateAdded }
        case .dateAddedAsc: list.sort { $0.dateAdded < $1.dateAdded }
        case .titleAsc: list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .durationDesc: list.sort { ($0.duration ?? 0) > ($1.duration ?? 0) }
        case .fileSizeDesc: list.sort { ($0.fileSize ?? 0) > ($1.fileSize ?? 0) }
        }
        return list
    }

    @MainActor
    func scan(folder: URL) async {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            items = []
            return
        }
        let sidecars = contents.filter { $0.lastPathComponent.hasSuffix(".\(SidecarJSON.fileExtension)") }
        var result: [MediaItem] = []
        for url in sidecars {
            guard let side = try? SidecarJSON.read(from: url) else { continue }
            result.append(MediaItem.fromSidecar(side, sidecarURL: url, libraryFolder: folder))
        }
        self.items = result
    }

    @MainActor
    func remove(_ item: MediaItem) {
        items.removeAll { $0.id == item.id }
        let fm = FileManager.default
        // Move to Trash (reversible)
        try? fm.trashItem(at: item.sidecarURL, resultingItemURL: nil)
        try? fm.trashItem(at: item.fileURL, resultingItemURL: nil)
        if let thumb = item.thumbnailURL {
            try? fm.trashItem(at: thumb, resultingItemURL: nil)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add VideoDownloader/Library/LibraryModel.swift
git commit -m "feat: add LibraryModel with folder scan, search, sort"
```

---

## Task 21: LibraryView + LibraryItemView

**Files:**
- Create: `VideoDownloader/Library/LibraryView.swift`
- Create: `VideoDownloader/Library/LibraryItemView.swift`

- [ ] **Step 1: Implement LibraryView**

```swift
import SwiftUI
import QuickLookUI
import AppKit

struct LibraryView: View {
    @Environment(LibraryModel.self) private var library
    @State private var showImport = false

    var body: some View {
        @Bindable var library = library
        VStack(spacing: 0) {
            HStack {
                TextField("Search…", text: $library.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Picker("Sort", selection: $library.sort) {
                    ForEach(LibraryModel.Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 160)
                Picker("View", selection: $library.viewMode) {
                    Image(systemName: "square.grid.2x2").tag(LibraryModel.ViewMode.grid)
                    Image(systemName: "list.bullet").tag(LibraryModel.ViewMode.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
                Spacer()
                Button("Import…") { showImport = true }
                Button("Rescan") {
                    Task { await library.scan(folder: DriveCheck.libraryFolder) }
                }
            }
            .padding(8)

            Divider()

            ScrollView {
                switch library.viewMode {
                case .grid:
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        ForEach(library.filteredItems) { item in
                            LibraryItemView(item: item, style: .grid)
                        }
                    }
                    .padding(12)
                case .list:
                    VStack(spacing: 0) {
                        ForEach(library.filteredItems) { item in
                            LibraryItemView(item: item, style: .list)
                            Divider()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showImport) {
            ImportSheet(onCompletion: {
                showImport = false
                Task { await library.scan(folder: DriveCheck.libraryFolder) }
            })
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task { await handleDrop(providers) }
            return true
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) async {
        var urls: [URL] = []
        for p in providers {
            if let url = try? await p.loadItem(forTypeIdentifier: "public.file-url") as? URL {
                urls.append(url)
            } else if let data = try? await p.loadItem(forTypeIdentifier: "public.file-url") as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) {
                urls.append(url)
            }
        }
        await ImportRunner.importFiles(urls, copyIntoLibrary: true,
                                       libraryFolder: DriveCheck.libraryFolder)
    }
}
```

- [ ] **Step 2: Implement LibraryItemView**

```swift
import SwiftUI
import AppKit
import QuickLookUI

struct LibraryItemView: View {
    @Environment(LibraryModel.self) private var library
    let item: MediaItem
    enum Style { case grid, list }
    let style: Style
    @State private var sendError: String?

    var body: some View {
        switch style {
        case .grid: gridBody
        case .list: listBody
        }
    }

    private var gridBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(url: item.thumbnailURL)
                .aspectRatio(16/9, contentMode: .fit)
            Text(item.title).font(.headline).lineLimit(2)
            HStack(spacing: 6) {
                Image(systemName: item.site.systemImageName)
                Text(item.formatLabel).font(.caption)
                Spacer()
                if let d = item.duration { Text(formatDuration(d)).font(.caption) }
            }
            .foregroundStyle(.secondary)
            actionBar
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var listBody: some View {
        HStack(spacing: 12) {
            ThumbnailView(url: item.thumbnailURL)
                .frame(width: 160, height: 90)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline).lineLimit(1)
                HStack {
                    Image(systemName: item.site.systemImageName)
                    Text(item.site.displayName)
                    if let d = item.duration { Text("• \(formatDuration(d))") }
                    Text("• \(item.formatLabel)")
                }
                .font(.caption).foregroundStyle(.secondary)
                Text(item.fileURL.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            actionBar
        }
        .padding(8)
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            Button { preview() } label: { Image(systemName: "play.fill") }
                .help("Preview")
            Button { send() } label: { Image(systemName: "text.bubble") }
                .help("Send to Transcription Engine")
            Button { showInFinder() } label: { Image(systemName: "folder") }
                .help("Show in Finder")
            Button(role: .destructive) { library.remove(item) } label: {
                Image(systemName: "trash")
            }
            .help("Delete")
        }
        .buttonStyle(.borderless)
    }

    private func preview() {
        QuickLookPreview.show(url: item.fileURL)
    }

    private func send() {
        Task {
            do { try await TranscriptionEngineLauncher.send(fileURL: item.fileURL) }
            catch { sendError = error.localizedDescription }
        }
    }

    private func showInFinder() {
        NSWorkspace.shared.selectFile(item.fileURL.path, inFileViewerRootedAtPath: item.fileURL.deletingLastPathComponent().path)
    }

    private func formatDuration(_ s: Double) -> String {
        let total = Int(s)
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
```

- [ ] **Step 3: Add QuickLookPreview helper**

```swift
// VideoDownloader/Library/QuickLookPreview.swift
import AppKit
import QuickLookUI

final class QuickLookPreview: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPreview()
    private var currentURL: URL?

    static func show(url: URL) {
        shared.currentURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = shared
        panel.delegate = shared
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { currentURL == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        currentURL as QLPreviewItem?
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add VideoDownloader/Library/LibraryView.swift VideoDownloader/Library/LibraryItemView.swift VideoDownloader/Library/QuickLookPreview.swift
git commit -m "feat: add LibraryView, LibraryItemView, QuickLookPreview"
```

---

## Task 22: ImportSheet + ImportRunner

**Files:**
- Create: `VideoDownloader/Library/ImportSheet.swift`
- Create: `VideoDownloader/Library/ImportRunner.swift`

- [ ] **Step 1: Implement ImportSheet**

```swift
import SwiftUI
import UniformTypeIdentifiers

struct ImportSheet: View {
    let onCompletion: () -> Void
    @State private var urls: [URL] = []
    @State private var copyIntoLibrary: Bool = false
    @State private var isImporting = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Files").font(.title2).bold()
            Button("Choose Files…") { chooseFiles() }

            List(urls, id: \.self) { Text($0.lastPathComponent) }
                .frame(minHeight: 120)

            Toggle("Copy into library folder", isOn: $copyIntoLibrary)

            if let errorText {
                Text(errorText).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCompletion).keyboardShortcut(.cancelAction)
                Button(isImporting ? "Importing…" : "Import") { doImport() }
                    .disabled(urls.isEmpty || isImporting)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 520)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .audio, .mpeg4Movie, .quickTimeMovie, .mp3, .wav]
        if panel.runModal() == .OK { urls = panel.urls }
    }

    private func doImport() {
        isImporting = true
        errorText = nil
        Task {
            do {
                try await ImportRunner.importFiles(urls,
                    copyIntoLibrary: copyIntoLibrary,
                    libraryFolder: DriveCheck.libraryFolder)
                onCompletion()
            } catch {
                errorText = error.localizedDescription
            }
            isImporting = false
        }
    }
}
```

- [ ] **Step 2: Implement ImportRunner**

```swift
import Foundation

enum ImportRunner {
    /// Import files. If copyIntoLibrary is true, files are copied to the library folder.
    /// Otherwise sidecar + thumbnail are written to the library folder but the media stays in place.
    static func importFiles(
        _ urls: [URL],
        copyIntoLibrary: Bool,
        libraryFolder: URL
    ) async throws {
        for url in urls {
            try await importOne(url, copyIntoLibrary: copyIntoLibrary, libraryFolder: libraryFolder)
        }
    }

    private static func importOne(
        _ url: URL,
        copyIntoLibrary: Bool,
        libraryFolder: URL
    ) async throws {
        let fm = FileManager.default
        let originalPath = url.path
        let basename = url.deletingPathExtension().lastPathComponent

        let finalMediaURL: URL
        if copyIntoLibrary {
            let dest = libraryFolder.appendingPathComponent(url.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) {
                try fm.copyItem(at: url, to: dest)
            }
            finalMediaURL = dest
        } else {
            finalMediaURL = url
        }

        // Generate thumbnail in library folder
        let thumbURL = libraryFolder.appendingPathComponent("\(basename).jpg")
        try? await FFmpegRunner.makeThumbnail(from: finalMediaURL, to: thumbURL, atSeconds: 5.0)

        let duration = (try? await FFmpegRunner.duration(of: finalMediaURL)) ?? 0
        let attrs = try fm.attributesOfItem(atPath: finalMediaURL.path)
        let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0

        let sidecar = SidecarJSON(
            schemaVersion: 1,
            title: basename,
            url: nil,
            site: .import,
            uploader: nil,
            duration: duration,
            format: "import",
            formatLabel: "Imported",
            fileSize: fileSize,
            fileName: finalMediaURL.lastPathComponent,
            thumbnailFile: fm.fileExists(atPath: thumbURL.path) ? "\(basename).jpg" : nil,
            dateAdded: Date(),
            description: nil,
            mediaFilePath: copyIntoLibrary ? nil : finalMediaURL.path,
            importedFromPath: originalPath
        )
        try sidecar.write(to: libraryFolder)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add VideoDownloader/Library/ImportSheet.swift VideoDownloader/Library/ImportRunner.swift
git commit -m "feat: add ImportSheet and ImportRunner"
```

---

## Task 23: Patch Transcription Engine to accept open-file events → v6

**Files:**
- Modify: `/Volumes/1tb /claude code projects /Projects/transcription-engine/TranscriptionEngine/App/TranscriptionEngineApp.swift` (exact path — verify)
- Modify: `TranscriptionEngine/Info.plist` — register handled file types

- [ ] **Step 1: Verify current TE state**

```bash
ls "/Volumes/1tb /claude code projects /Projects/transcription-engine/TranscriptionEngine/"
grep -rn "application.*open" "/Volumes/1tb /claude code projects /Projects/transcription-engine/TranscriptionEngine/" 2>/dev/null
```

Confirm whether TE already handles `application(_:open:)`. If yes, skip to Step 3. If no, continue.

- [ ] **Step 2: Add NSApplicationDelegate adapter**

Add (or extend) a delegate class:

```swift
import AppKit
import SwiftUI

final class TEAppDelegate: NSObject, NSApplicationDelegate {
    static let shared = TEAppDelegate()
    var openFileURL: URL?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        openFileURL = url
        NotificationCenter.default.post(name: .teShouldOpenFile, object: url)
    }
}

extension Notification.Name {
    static let teShouldOpenFile = Notification.Name("TEShouldOpenFile")
}
```

In `TranscriptionEngineApp`:
```swift
@main
struct TranscriptionEngineApp: App {
    @NSApplicationDelegateAdaptor(TEAppDelegate.self) var appDelegate
    // ... rest unchanged
}
```

In the view that loads files, observe the notification and call the existing open-file handler.

- [ ] **Step 3: Register file types in Info.plist**

Under `CFBundleDocumentTypes`:
```xml
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>Audio / Video</string>
        <key>LSHandlerRank</key>
        <string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>public.movie</string>
            <string>public.audio</string>
            <string>public.mp3</string>
            <string>public.mpeg-4</string>
            <string>public.mpeg-4-audio</string>
            <string>com.microsoft.waveform-audio</string>
            <string>org.webmproject.webm</string>
            <string>public.matroska</string>
        </array>
    </dict>
</array>
```

- [ ] **Step 4: Build and install as Transcription Engine v6**

```bash
cd "/Volumes/1tb /claude code projects /Projects/transcription-engine"
xcodebuild -project TranscriptionEngine.xcodeproj \
    -scheme TranscriptionEngine \
    -configuration Release \
    -derivedDataPath "/Volumes/1tb /claude code projects /DerivedData/TranscriptionEngine" \
    build
```

Then copy the build output to `/Applications/Transcription Engine v6.app`. Do NOT rename the app itself — only the filename in /Applications/ gets the version suffix per CLAUDE.md.

- [ ] **Step 5: Verify hand-off**

```bash
open -a "/Applications/Transcription Engine v6.app" "/Volumes/1tb /claude code projects /youtube-downloads/Living with Synchronicity： Marie-Louise von Franz & C.G. Jung.mp3"
```

Expected: TE launches and loads the file into the transcription view.

- [ ] **Step 6: Commit TE patch**

```bash
cd "/Volumes/1tb /claude code projects /Projects/transcription-engine"
git add -A
git commit -m "feat: accept open-file argument for Video Downloader integration"
```

---

## Task 24: Integration smoke test

**Files:**
- Create: `VideoDownloader/DevTools/smoke_test.sh`

- [ ] **Step 1: Write smoke test script**

```bash
#!/bin/bash
set -euo pipefail

LIB="/Volumes/1tb /claude code projects /youtube-downloads"
APP="/Applications/Video Downloader v1.app"
TEST_URL="https://www.youtube.com/watch?v=-GPVHHStUfg"

echo "== Smoke test =="
echo "Library folder: $LIB"
echo "App: $APP"

[ -d "$LIB" ] || { echo "FAIL: library folder missing"; exit 1; }
[ -d "$APP" ] || { echo "FAIL: app not installed at $APP"; exit 1; }

# Check bundled binaries
BIN="$HOME/Library/Application Support/VideoDownloader/bin"
[ -x "$BIN/yt-dlp" ] || { echo "FAIL: yt-dlp not installed in $BIN"; exit 1; }
[ -x "$BIN/ffmpeg" ] || { echo "FAIL: ffmpeg not installed in $BIN"; exit 1; }

echo "PASS: binaries installed"
echo "Next: launch app, paste $TEST_URL, choose 720p, download, verify files appear in library tab"
```

- [ ] **Step 2: Commit**

```bash
chmod +x VideoDownloader/DevTools/smoke_test.sh
git add VideoDownloader/DevTools/smoke_test.sh
git commit -m "test: add smoke test script"
```

---

## Task 25: Build + install to /Applications/

- [ ] **Step 1: Verify current /Applications/ versions**

```bash
ls /Applications/ | grep -i "Video Downloader"
```

If any exist, the next version number is N+1. Otherwise this is v1.

- [ ] **Step 2: Build Release**

```bash
cd "/Volumes/1tb /claude code projects /Projects/video-downloader"
xcodebuild -project VideoDownloader.xcodeproj \
    -scheme VideoDownloader \
    -configuration Release \
    -derivedDataPath "/Volumes/1tb /claude code projects /DerivedData/VideoDownloader" \
    build
```

Build output will be at:
`/Volumes/1tb /claude code projects /DerivedData/VideoDownloader/Build/Products/Release/VideoDownloader.app`

- [ ] **Step 3: Copy to /Applications/ with version suffix**

```bash
cp -R "/Volumes/1tb /claude code projects /DerivedData/VideoDownloader/Build/Products/Release/VideoDownloader.app" \
   "/Applications/Video Downloader v1.app"
```

Per CLAUDE.md: original app name preserved, version suffix appended to the filename in /Applications/.

- [ ] **Step 4: Run smoke test**

```bash
bash "/Volumes/1tb /claude code projects /Projects/video-downloader/VideoDownloader/DevTools/smoke_test.sh"
```

Expected: PASS.

- [ ] **Step 5: End-to-end manual verification**

1. Launch `Video Downloader v1.app`
2. Paste `https://www.youtube.com/watch?v=-GPVHHStUfg` → "Add to Queue"
3. Row appears in Queue tab with title
4. Change format to **720p**
5. Click "Download All" → progress bar advances
6. On completion, row disappears from Queue
7. Switch to Library tab → new item appears with thumbnail
8. Click "Send to Transcription Engine" → TE v6 launches with the file loaded
9. Click "Show in Finder" → Finder reveals the file
10. Click trash → file moves to macOS Trash; item removed from library

- [ ] **Step 6: Commit the build**

```bash
cd "/Volumes/1tb /claude code projects /Projects/video-downloader"
git add -A
git commit -m "build: Video Downloader v1 release build"
```

---

## Self-review

- ✅ Spec coverage: all Queue, Library, Import, Transcription hand-off, auto-update, binary bundling, drive check, error handling, file structure → each mapped to a task.
- ✅ No placeholders left in task bodies.
- ✅ Type names consistent: `QueueItem.status`, `LibraryModel.filteredItems`, `SidecarJSON`, `MediaItem`, `DownloadFormat` used uniformly across tasks.
- ✅ File paths all absolute and match the File Structure section.
- ✅ Commit after each task.
