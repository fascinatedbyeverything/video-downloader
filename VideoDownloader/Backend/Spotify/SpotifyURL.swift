import Foundation

struct SpotifyURL: Equatable {
    enum Kind: String { case playlist, track, album, artist }

    let kind: Kind
    let id: String

    var uri: String { "spotify:\(kind.rawValue):\(id)" }
    var publicWebURL: String { "https://open.spotify.com/\(kind.rawValue)/\(id)" }

    static func parse(_ input: String) -> SpotifyURL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // spotify:KIND:ID
        if trimmed.lowercased().hasPrefix("spotify:") {
            let parts = trimmed.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3,
                  let kind = Kind(rawValue: String(parts[1]).lowercased()) else { return nil }
            let id = String(parts[2])
            guard isValidID(id) else { return nil }
            return SpotifyURL(kind: kind, id: id)
        }

        // https://open.spotify.com/KIND/ID(?si=...)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased(),
              host.contains("spotify.com") else { return nil }

        let comps = url.path.split(separator: "/").map(String.init)
        guard comps.count >= 2,
              let kind = Kind(rawValue: comps[0].lowercased()) else { return nil }
        let id = comps[1]
        guard isValidID(id) else { return nil }
        return SpotifyURL(kind: kind, id: id)
    }

    private static func isValidID(_ id: String) -> Bool {
        // Spotify IDs are base62 strings, typically 22 chars
        guard id.count >= 16, id.count <= 32 else { return false }
        return id.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
