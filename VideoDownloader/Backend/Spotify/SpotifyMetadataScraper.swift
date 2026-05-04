import Foundation

enum SpotifyMetadataScraperError: Error {
    case empty
    case noStructuredData
    case malformedJSON(String)
    case httpError(Int)
}

enum SpotifyMetadataScraper {
    /// Fetches and parses a public Spotify playlist via the embed endpoint
    /// (the embed page exposes a `__NEXT_DATA__` JSON blob with full track listing,
    /// while the main playlist page is a JS-rendered SPA without server-rendered tracks).
    static func fetch(playlistID: String) async throws -> SpotifyPlaylistMetadata {
        let urls = [
            "https://open.spotify.com/embed/playlist/\(playlistID)",
            "https://open.spotify.com/playlist/\(playlistID)"
        ]
        var lastError: Error?
        for s in urls {
            guard let url = URL(string: s) else { continue }
            var req = URLRequest(url: url)
            req.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    lastError = SpotifyMetadataScraperError.httpError(http.statusCode)
                    continue
                }
                guard let html = String(data: data, encoding: .utf8) else {
                    lastError = SpotifyMetadataScraperError.empty
                    continue
                }
                return try parse(html: html, playlistID: playlistID)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? SpotifyMetadataScraperError.empty
    }

    /// Parse playlist metadata from raw HTML. Pure function for testability.
    static func parse(html: String, playlistID: String) throws -> SpotifyPlaylistMetadata {
        guard !html.isEmpty else { throw SpotifyMetadataScraperError.empty }

        // Try __NEXT_DATA__ first (embed page format — full tracks)
        if let initial = extractInitialState(html: html),
           let parsed = try? parseInitialState(initial, playlistID: playlistID) {
            return parsed
        }
        // Fallback: JSON-LD (basic info, fewer fields)
        if let jsonld = extractJSONLD(html: html),
           let parsed = try? parseJSONLD(jsonld, playlistID: playlistID) {
            return parsed
        }
        throw SpotifyMetadataScraperError.noStructuredData
    }

    // MARK: - JSON-LD

    private static func extractJSONLD(html: String) -> Data? {
        let pattern = #"<script type="application/ld\+json">(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let m = regex.firstMatch(in: html, options: [], range: range),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r]).data(using: .utf8)
    }

    private static func parseJSONLD(_ data: Data, playlistID: String) throws -> SpotifyPlaylistMetadata {
        let obj = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let name = obj["name"] as? String ?? ""
        let description = obj["description"] as? String ?? ""
        let coverURL: URL? = (obj["image"] as? String).flatMap(URL.init(string:))
        let trackArr = obj["track"] as? [[String: Any]] ?? []
        let tracks: [SpotifyTrack] = trackArr.enumerated().compactMap { idx, item in
            guard let trackName = item["name"] as? String,
                  let trackURL = item["url"] as? String,
                  let id = trackIDFromURL(trackURL) else { return nil }
            let durationISO = item["duration"] as? String ?? ""
            let artistsArr = item["byArtist"] as? [[String: Any]] ?? []
            let artists = artistsArr.compactMap { $0["name"] as? String }
            let albumName = (item["inAlbum"] as? [String: Any])?["name"] as? String ?? ""
            return SpotifyTrack(
                id: id,
                uri: "spotify:track:\(id)",
                title: trackName,
                artists: artists,
                album: albumName,
                durationMs: parseISO8601Duration(durationISO),
                trackNumber: idx + 1,
                artworkURL: nil
            )
        }
        guard !tracks.isEmpty else { throw SpotifyMetadataScraperError.noStructuredData }
        return SpotifyPlaylistMetadata(
            id: playlistID,
            uri: "spotify:playlist:\(playlistID)",
            name: name,
            description: description,
            coverURL: coverURL,
            tracks: tracks
        )
    }

    private static func trackIDFromURL(_ urlString: String) -> String? {
        guard let u = URL(string: urlString) else { return nil }
        let comps = u.path.split(separator: "/").map(String.init)
        guard comps.count >= 2, comps[0].lowercased() == "track" else { return nil }
        return comps[1]
    }

    private static func parseISO8601Duration(_ s: String) -> Int {
        var total = 0, current = ""
        for ch in s {
            if ch.isNumber { current.append(ch); continue }
            guard let n = Int(current) else { current = ""; continue }
            switch ch {
            case "H": total += n * 3_600_000
            case "M": total += n * 60_000
            case "S": total += n * 1_000
            default: break
            }
            current = ""
        }
        return total
    }

    // MARK: - __NEXT_DATA__ (embed page)

    private static func extractInitialState(html: String) -> Data? {
        let pattern = #"<script id="__NEXT_DATA__"[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let m = regex.firstMatch(in: html, options: [], range: range),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r]).data(using: .utf8)
    }

    private static func parseInitialState(_ data: Data, playlistID: String) throws -> SpotifyPlaylistMetadata {
        let root = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let pageProps = ((root["props"] as? [String: Any])?["pageProps"] as? [String: Any]) ?? [:]

        // The embed page uses pageProps.state.data.entity, with trackList[].
        let entity = findEntity(in: pageProps) ?? [:]
        let name = entity["name"] as? String ?? ""
        let description = entity["description"] as? String ?? ""

        // Cover art: try `coverArt.sources[0].url` first, then `images[0].url`
        var coverURL: URL?
        if let coverArt = entity["coverArt"] as? [String: Any],
           let sources = coverArt["sources"] as? [[String: Any]],
           let urlStr = sources.first?["url"] as? String {
            coverURL = URL(string: urlStr)
        } else if let images = entity["images"] as? [[String: Any]],
                  let urlStr = images.first?["url"] as? String {
            coverURL = URL(string: urlStr)
        }

        // Tracks: embed page uses trackList; full page uses tracks.items.
        let trackList = entity["trackList"] as? [[String: Any]] ?? []
        let trackItems = (entity["tracks"] as? [String: Any])?["items"] as? [[String: Any]] ?? []

        let tracks: [SpotifyTrack]
        if !trackList.isEmpty {
            tracks = trackList.enumerated().compactMap { parseEmbedTrack(item: $0.element, index: $0.offset) }
        } else if !trackItems.isEmpty {
            tracks = trackItems.enumerated().compactMap { parseFullPageTrack(item: $0.element, index: $0.offset) }
        } else {
            tracks = []
        }

        guard !tracks.isEmpty else { throw SpotifyMetadataScraperError.noStructuredData }

        return SpotifyPlaylistMetadata(
            id: playlistID,
            uri: "spotify:playlist:\(playlistID)",
            name: name,
            description: description,
            coverURL: coverURL,
            tracks: tracks
        )
    }

    /// The embed `__NEXT_DATA__` nests entity under different paths depending on page type.
    /// Walk the dictionary tree looking for the first dict that has a `trackList` array
    /// or `tracks.items` array along with a `name`.
    private static func findEntity(in obj: Any) -> [String: Any]? {
        if let d = obj as? [String: Any] {
            if d["trackList"] is [[String: Any]] || (d["tracks"] as? [String: Any])?["items"] is [[String: Any]] {
                if d["name"] != nil { return d }
            }
            // Common direct paths
            if let entity = d["entity"] as? [String: Any] {
                if let found = findEntity(in: entity) { return found }
            }
            if let state = d["state"] as? [String: Any],
               let dataDict = state["data"] as? [String: Any],
               let entity = dataDict["entity"] as? [String: Any] {
                return entity
            }
            for (_, v) in d {
                if let found = findEntity(in: v) { return found }
            }
        }
        if let arr = obj as? [Any] {
            for v in arr {
                if let found = findEntity(in: v) { return found }
            }
        }
        return nil
    }

    private static func parseEmbedTrack(item: [String: Any], index: Int) -> SpotifyTrack? {
        guard let uri = item["uri"] as? String else { return nil }
        let id = uri.replacingOccurrences(of: "spotify:track:", with: "")
        let title = item["title"] as? String ?? ""
        // Embed format: `subtitle` is the artist line ("Artist · Artist"), `artists` may also be present.
        var artists: [String] = []
        if let arr = item["artists"] as? [[String: Any]] {
            artists = arr.compactMap { $0["name"] as? String }
        }
        if artists.isEmpty, let subtitle = item["subtitle"] as? String, !subtitle.isEmpty {
            artists = subtitle.components(separatedBy: ", ").flatMap { $0.components(separatedBy: " · ") }
        }
        let durationMs = (item["duration"] as? Int) ?? 0
        let artworkURL = (item["imageUrl"] as? String).flatMap(URL.init(string:))
        return SpotifyTrack(
            id: id,
            uri: "spotify:track:\(id)",
            title: title,
            artists: artists,
            album: item["albumName"] as? String ?? "",
            durationMs: durationMs,
            trackNumber: index + 1,
            artworkURL: artworkURL
        )
    }

    private static func parseFullPageTrack(item: [String: Any], index: Int) -> SpotifyTrack? {
        let track = (item["track"] as? [String: Any]) ?? item
        guard let id = track["id"] as? String,
              let title = track["name"] as? String else { return nil }
        let artistsArr = track["artists"] as? [[String: Any]] ?? []
        let artists = artistsArr.compactMap { $0["name"] as? String }
        let albumDict = track["album"] as? [String: Any] ?? [:]
        let albumName = albumDict["name"] as? String ?? ""
        let albumImages = albumDict["images"] as? [[String: Any]] ?? []
        let artworkURL = (albumImages.first?["url"] as? String).flatMap(URL.init(string:))
        return SpotifyTrack(
            id: id,
            uri: "spotify:track:\(id)",
            title: title,
            artists: artists,
            album: albumName,
            durationMs: track["duration_ms"] as? Int ?? 0,
            trackNumber: index + 1,
            artworkURL: artworkURL
        )
    }
}
