import Foundation

enum YTDLPSearch {

    enum SearchError: LocalizedError {
        case processFailed(stderr: String, exitCode: Int32)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .processFailed(let stderr, let code):
                let head = String(stderr.prefix(200))
                return "yt-dlp search failed (exit \(code)): \(head)"
            case .cancelled:
                return "Search cancelled"
            }
        }
    }

    /// Runs `yt-dlp ytsearch<N>:<query> --flat-playlist --dump-json`.
    /// The `processStarted` hook exposes the live Process so the caller can cancel.
    static func search(
        query: String,
        limit: Int = 20,
        processStarted: (@Sendable (Process) -> Void)? = nil
    ) async throws -> [SearchResult] {
        let p = Process()
        p.executableURL = BinaryLocator.ytdlpURL
        p.arguments = [
            "--flat-playlist",
            "--dump-json",
            "--no-warnings",
            "ytsearch\(limit):\(query)"
        ]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        p.standardOutput = stdoutPipe
        p.standardError = stderrPipe

        try p.run()
        processStarted?(p)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            p.terminationHandler = { _ in cont.resume() }
        }

        let stdoutData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
        let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

        if p.terminationStatus != 0 {
            // SIGTERM from cancel() comes through as exit 15 / non-zero — classify as cancelled
            // if stdout is empty and the process was signaled.
            if p.terminationReason == .uncaughtSignal {
                throw SearchError.cancelled
            }
            throw SearchError.processFailed(stderr: stderrText, exitCode: p.terminationStatus)
        }

        return parse(stdoutText)
    }

    /// Pure parser: takes yt-dlp stdout (one JSON object per line) and returns SearchResults.
    /// Malformed lines are skipped silently.
    static func parse(_ stdout: String) -> [SearchResult] {
        var results: [SearchResult] = []
        let decoder = JSONDecoder()
        for line in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.hasPrefix("{") else { continue }
            guard let data = trimmed.data(using: .utf8) else { continue }
            guard let raw = try? decoder.decode(RawEntry.self, from: data) else { continue }
            guard let id = raw.id, !id.isEmpty else { continue }

            let thumb = raw.thumbnails?.last?.url ?? raw.thumbnail
            let thumbURL = thumb.flatMap { URL(string: $0) }

            results.append(SearchResult(
                id: id,
                title: raw.title ?? id,
                channel: raw.channel ?? raw.uploader,
                durationSeconds: raw.duration,
                thumbnailURL: thumbURL,
                viewCount: raw.view_count
            ))
        }
        return results
    }

    // Maps only the fields we need. yt-dlp emits many more — let JSONDecoder ignore them.
    private struct RawEntry: Decodable {
        let id: String?
        let title: String?
        let channel: String?
        let uploader: String?
        let duration: Double?
        let thumbnail: String?
        let thumbnails: [Thumb]?
        let view_count: Int?

        struct Thumb: Decodable {
            let url: String?
        }
    }
}
