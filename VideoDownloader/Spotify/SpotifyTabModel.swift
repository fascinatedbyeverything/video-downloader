import Foundation
import Observation

@Observable
@MainActor
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
    var phase: Phase = .idle

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

            let active = ActiveCapture(metadata: meta, currentTrackIndex: 0,
                                       completedTrackIDs: [], outputFolder: playlistFolder)
            phase = .capturing(active: active)

            let segmenter = SpotifyTrackSegmenter { [weak self] result in
                guard let self else { return }
                Task { @MainActor in self.handleSegment(result) }
            }
            self.segmenter = segmenter

            let observer = SpotifyPlaybackObserver { [weak self] event in
                guard let self else { return }
                Task { @MainActor in
                    self.segmenter?.onPlaybackEvent(event)
                    self.handleEvent(event)
                }
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

    private func handleSegment(_ result: SpotifySegmentResult) {
        guard case var .capturing(active) = phase else { return }
        let trackNumber = active.metadata.tracks.firstIndex(where: { $0.id == result.trackID })
            .map { $0 + 1 } ?? 0
        let coverArtURL = active.metadata.tracks.first(where: { $0.id == result.trackID })?.artworkURL ?? active.metadata.coverURL
        let req = SpotifyEncodeRequest(
            segment: result,
            trackNumber: trackNumber,
            outputFolder: active.outputFolder,
            coverArtURL: coverArtURL
        )
        Task.detached {
            do {
                _ = try await SpotifyEncoder.encode(req)
                await MainActor.run {
                    if case var .capturing(active2) = self.phase {
                        active2.completedTrackIDs.insert(result.trackID)
                        self.phase = .capturing(active: active2)
                    }
                }
            } catch {
                await MainActor.run {
                    self.phase = .error("Encode failed: \(error.localizedDescription)")
                }
            }
        }
        active.completedTrackIDs.insert(result.trackID)
        phase = .capturing(active: active)
    }

    private func handleEvent(_ event: SpotifyNotificationPayload) {
        guard case var .capturing(active) = phase else { return }
        if let idx = active.metadata.tracks.firstIndex(where: { $0.id == event.trackID }) {
            active.currentTrackIndex = idx
            phase = .capturing(active: active)
        }
        if event.playerState == .stopped,
           active.completedTrackIDs.count == active.metadata.tracks.count {
            phase = .finished(folder: active.outputFolder,
                              capturedTrackCount: active.completedTrackIDs.count)
            stopCapture()
        }
    }

    private func sanitize(_ s: String) -> String {
        let bad: Set<Character> = ["/", ":", "\\", "*", "?", "\"", "<", ">", "|"]
        return String(s.map { bad.contains($0) ? "-" : $0 })
    }
}
