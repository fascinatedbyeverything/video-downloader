import Foundation

struct PlaylistEntry: Identifiable, Equatable {
    let id: String
    let url: String
    let title: String
    let durationSeconds: Double?
    let thumbnailURL: String?
}

enum PlaylistResolverError: Error { case failed(stderr: String) }

enum PlaylistResolver {
    /// Expand a playlist URL into its video entries using `yt-dlp --flat-playlist --dump-single-json`.
    static func resolve(_ url: String) async throws -> [PlaylistEntry] {
        let p = Process()
        p.executableURL = BinaryLocator.ytdlpURL
        p.arguments = ["--flat-playlist", "--dump-single-json", url]
        let stdout = Pipe()
        let stderr = Pipe()
        p.standardOutput = stdout
        p.standardError = stderr
        try p.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            p.terminationHandler = { _ in cont.resume() }
        }
        let data = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
        if p.terminationStatus != 0 {
            let errData = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
            throw PlaylistResolverError.failed(stderr: String(data: errData, encoding: .utf8) ?? "")
        }

        struct Blob: Decodable {
            struct Entry: Decodable {
                let id: String
                let title: String?
                let url: String?
                let duration: Double?
                let thumbnails: [Thumb]?
                struct Thumb: Decodable { let url: String }
            }
            let entries: [Entry]?
        }

        let blob = try JSONDecoder().decode(Blob.self, from: data)
        return (blob.entries ?? []).map { e in
            PlaylistEntry(
                id: e.id,
                url: canonicalURL(from: e.url ?? e.id),
                title: e.title ?? e.id,
                durationSeconds: e.duration,
                thumbnailURL: e.thumbnails?.first?.url
            )
        }
    }

    private static func canonicalURL(from idOrURL: String) -> String {
        if idOrURL.hasPrefix("http") { return idOrURL }
        return "https://www.youtube.com/watch?v=\(idOrURL)"
    }
}
