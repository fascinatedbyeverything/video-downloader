import Foundation

struct SpotifyTrack: Equatable, Identifiable {
    let id: String                 // Spotify track ID
    let uri: String                // spotify:track:<id>
    let title: String
    let artists: [String]
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
