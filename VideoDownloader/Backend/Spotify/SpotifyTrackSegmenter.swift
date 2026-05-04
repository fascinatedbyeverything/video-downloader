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

        if event.playerState == .stopped {
            emitCurrent()
            current = nil
            return
        }

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
