import Foundation

enum URLClassification: Equatable {
    case youtubeVideo
    case youtubePlaylist
    case vimeoVideo
    case vimeoShowcase
    case unknown
    case invalid

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
        guard let url = URL(string: trimmed),
              let scheme = url.scheme, !scheme.isEmpty,
              let host = url.host, !host.isEmpty else {
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
        return .unknown
    }
}
