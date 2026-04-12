import Foundation

enum SidecarWriter {
    /// After a successful yt-dlp download, locate the output file + thumbnail +
    /// info.json, and write a .meta.json sidecar.
    static func writeSidecar(
        forQueueItem item: QueueItem,
        libraryFolder: URL,
        ytdlpStdout: String
    ) async throws {
        // Primary: yt-dlp prints "VDFINAL:<absolute path>" after post-processing
        // (we pass `--print after_move:VDFINAL:%(filepath)s` in YTDLPRunner).
        // Fallback: parse [Merger] / [ExtractAudio] / [download] Destination lines.
        let destRegex = try NSRegularExpression(pattern: #"\[download\] Destination: (.+)"#)
        let mergerRegex = try NSRegularExpression(pattern: #"\[Merger\] Merging formats into "(.+)""#)
        let extractRegex = try NSRegularExpression(pattern: #"\[ExtractAudio\] Destination: (.+)"#)

        var finalPath: String?
        for line in ytdlpStdout.split(separator: "\n") {
            let s = String(line)
            if let prefixRange = s.range(of: "VDFINAL:") {
                finalPath = String(s[prefixRange.upperBound...])
                continue
            }
            let range = NSRange(s.startIndex..., in: s)
            if let m = mergerRegex.firstMatch(in: s, range: range),
               let r = Range(m.range(at: 1), in: s) {
                finalPath = String(s[r])
            } else if let m = extractRegex.firstMatch(in: s, range: range),
                      let r = Range(m.range(at: 1), in: s) {
                finalPath = String(s[r])
            } else if finalPath == nil,
                      let m = destRegex.firstMatch(in: s, range: range),
                      let r = Range(m.range(at: 1), in: s) {
                finalPath = String(s[r])
            }
        }

        guard let finalPath else {
            throw NSError(domain: "SidecarWriter", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not detect output path from yt-dlp output"])
        }

        let mediaURL = URL(fileURLWithPath: finalPath)
        let base = mediaURL.deletingPathExtension().lastPathComponent

        // Prefer info.json if yt-dlp wrote it (--write-info-json)
        let infoURL = libraryFolder.appendingPathComponent("\(base).info.json")
        var uploader: String? = nil
        var description: String? = nil
        if let data = try? Data(contentsOf: infoURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            uploader = json["uploader"] as? String
            description = json["description"] as? String
        }

        let thumb = libraryFolder.appendingPathComponent("\(base).jpg")
        let thumbFile: String? = FileManager.default.fileExists(atPath: thumb.path) ? "\(base).jpg" : nil

        let attrs = try FileManager.default.attributesOfItem(atPath: mediaURL.path)
        let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0

        let duration = (try? await FFmpegRunner.duration(of: mediaURL)) ?? (item.durationSeconds ?? 0)

        let sidecar = SidecarJSON(
            schemaVersion: 1,
            title: item.title,
            url: item.url,
            site: item.site,
            uploader: uploader,
            duration: duration,
            format: item.format.ytdlpFormat,
            formatLabel: item.format.displayName,
            fileSize: fileSize,
            fileName: mediaURL.lastPathComponent,
            thumbnailFile: thumbFile,
            dateAdded: Date(),
            description: description,
            mediaFilePath: nil,
            importedFromPath: nil
        )
        try sidecar.write(to: libraryFolder)

        // Clean up info.json — we've absorbed it
        try? FileManager.default.removeItem(at: infoURL)
    }
}
