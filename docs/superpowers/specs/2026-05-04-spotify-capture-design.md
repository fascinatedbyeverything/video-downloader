# Spotify Playlist Capture — Design Spec

**Date:** 2026-05-04
**Project location:** `/Volumes/fbe ebosuite live 18tb/Projects/video-downloader/`
**Build output:** `/Applications/Video Downloader v3.app`

## Purpose

Add Spotify playlist → audio capture as a fourth first-class URL type alongside YouTube video, YouTube → MP3, and Vimeo. User pastes a Spotify playlist URL and receives a folder of per-track WAV (lossless capture of the decoded stream) plus MP3 320 (parity with YouTube → MP3 path) with full ID3 tags.

## Constraints

- Spotify Premium account required (Free can't play arbitrary tracks on demand and inserts ads)
- Spotify Mac app must be installed and signed in
- macOS 14.2+ (CoreAudio Process Tap API; existing app targets 14.0 — bump deployment target to 14.2)
- Real-time capture: a 60-min playlist takes 60 min to capture
- Zotify/librespot path is broken as of March 2026 — direct DRM-bypass not viable

## Architecture

New parallel pipeline in the existing app. YouTube/Vimeo path (`Backend/YTDLPRunner` etc.) is untouched.

```
Spotify/                            ★ NEW UI module
  SpotifyTabView.swift              — 4th tab in MainView
  SpotifyPreviewView.swift          — playlist preview + duration estimate
  SpotifyCaptureView.swift          — live capture progress (current track, segments written)
  SpotifyTabModel.swift             — @Observable state

Backend/Spotify/                    ★ NEW backend module
  SpotifyURL.swift                  — URL → playlist URI parsing, classification
  SpotifyMetadataScraper.swift      — fetches public playlist HTML, parses embedded JSON
  SpotifyAppController.swift        — AppleScript: launch, play, pause, current track query
  SpotifyPlaybackObserver.swift     — NSDistributedNotificationCenter `com.spotify.client.PlaybackStateChanged`
  SpotifyAudioCaptureRunner.swift   — CoreAudio Process Tap (CATap) capturing Spotify.app PCM
  SpotifyTrackSegmenter.swift       — wires capture stream + track-change events into segments
  SpotifyEncoder.swift              — writes WAV (PCM passthrough) + MP3 320 (via system ffmpeg) + ID3 tags

Model/SiteSource.swift              — extend with .spotify case
Backend/URLClassifier.swift         — extend to recognize spotify.com / spotify: URLs
```

**Capture API choice:** CoreAudio Process Tap (`AudioHardwareCreateProcessTap`, macOS 14.2+) captures audio for Spotify.app's process specifically — no virtual audio driver, no system-audio bleed. ScreenCaptureKit's `capturesAudio` filters video by app but mixes all system audio, so it's unsuitable here.

**Permissions:**
- Apple Events automation for `com.spotify.client` (system prompts on first AppleScript call)
- CoreAudio system audio access (system prompts on first tap)

## Data flow

1. User pastes URL into Spotify tab
2. `SpotifyURL` parses → playlist URI
3. `SpotifyMetadataScraper` fetches the public playlist page, parses embedded JSON for tracks, total duration, cover art
4. UI shows preview: cover, track list, "47 tracks, ~3h 14m capture time"
5. User clicks "Start Capture" → choose output folder
6. `SpotifyAppController` launches/raises Spotify, calls `play track <playlist URI>`
7. `SpotifyAudioCaptureRunner` starts CATap, streams PCM into a ring buffer
8. `SpotifyPlaybackObserver` subscribes to `com.spotify.client.PlaybackStateChanged`
9. On each track-change event, `SpotifyTrackSegmenter`:
   - Closes previous segment in ring buffer at event timestamp
   - Hands segment + previous track metadata to `SpotifyEncoder`
   - Encoder writes `<NN> - <Artist> - <Title>.wav` and `.mp3` with ID3 tags
   - Files appear in Library immediately
10. On final track end (state goes to stopped or playlist-end notification), capture stops

## File layout

```
<output-folder>/<Playlist Name>/
  01 - Artist - Track.wav
  01 - Artist - Track.mp3
  02 - ...
  cover.jpg
  playlist.meta.json   (sidecar, follows existing SidecarJSON schema with site=spotify)
```

## Error handling

| Condition | Behavior |
|---|---|
| Spotify.app not installed | Block at preview, show install link |
| Spotify Free detected (ads play) | Detect via mismatch between expected track and actual `current track`; abort, show error |
| Screen Recording / Automation permission denied | System prompt; if denied, show retry button + System Settings deeplink |
| Scrape fails (private playlist or HTML changed) | Fall back to play-and-discover mode (no upfront preview, tracks appear as they capture) |
| User pauses Spotify mid-capture | Encoder pauses, capture continues paused; resumes when playback resumes |
| User closes Spotify | Capture ends gracefully; tracks already segmented are preserved |
| App crash mid-playlist | Already-written tracks intact (incremental write is the recovery story) |
| Track-change notification missed | 1Hz polling fallback on `current track id` as safety net |

## Testing

- Unit: `SpotifyURL` (URL → URI mapping for all Spotify URL forms)
- Unit: `SpotifyMetadataScraper` against captured HTML fixtures (1 public, 1 private placeholder)
- Unit: `SpotifyTrackSegmenter` with mock audio buffers + injected track-change events
- Integration (manual): capture a 3-track public playlist end-to-end, verify 3 × WAV + 3 × MP3 with correct tags + cover art

## Out of scope (v1)

- Spotify Web API integration (developer app registration)
- Search within Spotify catalog (user pastes URL, doesn't browse)
- Multi-playlist queueing (one playlist at a time)
- Episode/podcast capture (playlists only)
- Resume / re-capture for partial captures (manual re-run)
