# Video Downloader v1

macOS SwiftUI app for downloading YouTube and Vimeo videos with quality options, audio extraction, a folder-scan library, file import, and a one-click hand-off to the existing Transcription Engine app.

## Documents

- Design spec: [`docs/superpowers/specs/2026-04-12-video-downloader-design.md`](docs/superpowers/specs/2026-04-12-video-downloader-design.md)
- Implementation plan: [`docs/superpowers/plans/2026-04-12-video-downloader.md`](docs/superpowers/plans/2026-04-12-video-downloader.md)

## Build

Project is generated via `xcodegen` from `project.yml`. To regenerate:

```bash
cd "/Volumes/1tb /claude code projects /Projects/video-downloader"
xcodegen
```

Release build + install to `/Applications/`:

```bash
xcodebuild -project VideoDownloader.xcodeproj \
    -scheme VideoDownloader \
    -configuration Release \
    -derivedDataPath "/Volumes/1tb /claude code projects /DerivedData/VideoDownloader" \
    build
cp -R "/Volumes/1tb /claude code projects /DerivedData/VideoDownloader/Build/Products/Release/VideoDownloader.app" \
   "/Applications/Video Downloader v1.app"
```
