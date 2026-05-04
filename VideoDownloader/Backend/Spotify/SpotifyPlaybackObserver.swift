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
            guard let self, let info = note.userInfo as? [String: Any] else { return }
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
