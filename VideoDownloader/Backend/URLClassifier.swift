import Foundation

enum URLClassification: Equatable {
    case youtubeVideo
    case youtubePlaylist
    case vimeoVideo
    case vimeoShowcase
    case spotifyPlaylist
    case spotifyTrack
    case unknown
    case invalid

    var isPlaylist: Bool {
        switch self {
        case .youtubePlaylist, .vimeoShowcase, .spotifyPlaylist: return true
        default: return false
        }
    }

    var siteSource: SiteSource {
        switch self {
        case .youtubeVideo, .youtubePlaylist: return .youtube
        case .vimeoVideo, .vimeoShowcase: return .vimeo
        case .spotifyPlaylist, .spotifyTrack: return .spotify
        default: return .other
        }
    }
}

enum URLClassifier {
    static func classify(_ input: String) -> URLClassification {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme, !scheme.isEmpty else {
            return .invalid
        }
        let host = url.host ?? ""
        // spotify: URI scheme has no host
        if host.isEmpty && scheme.lowercased() != "spotify" {
            return .invalid
        }
        let lowercasedHost = host.lowercased()
        let path = url.path
        let query = url.query ?? ""

        if lowercasedHost.contains("youtube.com") || lowercasedHost.contains("youtu.be") {
            if path.contains("/playlist") { return .youtubePlaylist }
            if query.contains("list=") { return .youtubePlaylist }
            return .youtubeVideo
        }
        if lowercasedHost.contains("vimeo.com") {
            if path.contains("/showcase/") { return .vimeoShowcase }
            return .vimeoVideo
        }
        if lowercasedHost.contains("open.spotify.com") || lowercasedHost.contains("spotify.com") {
            if path.contains("/playlist/") { return .spotifyPlaylist }
            if path.contains("/track/") { return .spotifyTrack }
            return .unknown
        }
        if scheme.lowercased() == "spotify" {
            let raw = trimmed.lowercased()
            if raw.contains(":playlist:") { return .spotifyPlaylist }
            if raw.contains(":track:") { return .spotifyTrack }
            return .unknown
        }
        return .unknown
    }
}
