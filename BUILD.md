# Build Instructions — Video Downloader v3 (with Spotify Capture)

This branch (`feat/spotify-capture`) adds Spotify playlist → WAV + MP3 320 capture as a 4th URL type. Real-time capture via CoreAudio Process Tap + AppleScript playback control + NSDistributedNotificationCenter for track-change segmentation.

## Prerequisites

- **macOS 14.2+** (CoreAudio Process Tap API was introduced in 14.2)
- **Xcode 16+** with macOS 14.2 SDK
- **Homebrew + ffmpeg + xcodegen:**
  ```
  brew install ffmpeg xcodegen
  ```
- **Spotify desktop app** installed and signed into a **Spotify Premium** account (Free can't play arbitrary tracks on demand)

## Build steps

```bash
cd <project-folder>
git checkout feat/spotify-capture
xcodegen
xcodebuild -project VideoDownloader.xcodeproj -scheme VideoDownloader -configuration Release \
  -derivedDataPath ./DerivedData \
  build
```

The built app is at:
```
./DerivedData/Build/Products/Release/VideoDownloader.app
```

Copy it to `/Applications/` with a versioned name:
```bash
cp -R ./DerivedData/Build/Products/Release/VideoDownloader.app "/Applications/Video Downloader v3.app"
```

## Running tests

```bash
xcodebuild -project VideoDownloader.xcodeproj -scheme VideoDownloader \
  -derivedDataPath ./DerivedData test
```

Test targets:
- `URLClassifierSpotifyTests` — Spotify URL classification
- `SpotifyURLTests` — URL → URI parser
- `SpotifyMetadataScraperTests` — public playlist HTML scraping (uses fixture)
- `SpotifyTrackSegmenterTests` — PCM segmentation by track-change events

## First-run permissions (when launching the app)

The first time you click Spotify tab → Start Capture, macOS will prompt for:

1. **Apple Events permission** for `com.spotify.client` — grant. (Allows AppleScript control.)
2. **System audio recording permission** — grant. (Allows CoreAudio Process Tap to read Spotify's audio.)

If you decline either, capture won't start. Re-grant in System Settings → Privacy & Security.

## Manual integration test

1. Launch `Video Downloader v3.app`
2. Click the **Spotify** tab
3. Paste a public Spotify playlist URL — e.g. `https://open.spotify.com/playlist/0sooekw4rFNXqCeOOVGtqY` (Fuck Buttons "Olympians", 10 tracks)
4. Click **Load** — preview should show track list + cover art
5. Click **Start Capture** — choose an output folder
6. Approve macOS permission prompts
7. Spotify launches and starts playing the playlist
8. Each track appears as "complete" in the UI as Spotify advances
9. Output folder fills with `01 - Artist - Title.wav` and `01 - Artist - Title.mp3` per track

## Architecture overview

New code lives in:
- `VideoDownloader/Spotify/` — UI (4th tab)
- `VideoDownloader/Backend/Spotify/` — backend pipeline
- `VideoDownloaderTests/SpotifyURLTests.swift` etc. — unit tests
- `VideoDownloaderTests/Fixtures/spotify_playlist_public.html` — captured Spotify HTML for parser tests

Existing code touched:
- `project.yml` — bumped deployment target 14.0 → 14.2; added entitlements + automation usage description
- `VideoDownloader/Model/SiteSource.swift` — added `.spotify` case
- `VideoDownloader/Backend/URLClassifier.swift` — recognizes Spotify URLs
- `VideoDownloader/App/MainView.swift` — added 4th tab

The YouTube/Vimeo path (`Backend/YTDLPRunner` etc.) is unchanged.

## Spec / plan

- Design: `docs/superpowers/specs/2026-05-04-spotify-capture-design.md`
- Implementation plan: `docs/superpowers/plans/2026-05-04-spotify-capture.md`
