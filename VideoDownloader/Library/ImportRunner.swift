import Foundation

enum ImportRunner {
    /// Import files. If copyIntoLibrary is true, media files are copied to the library folder.
    /// Otherwise sidecar + thumbnail are written to the library folder but the media stays in place
    /// (tracked via sidecar's mediaFilePath).
    static func importFiles(
        _ urls: [URL],
        copyIntoLibrary: Bool,
        libraryFolder: URL
    ) async throws {
        for url in urls {
            try await importOne(url, copyIntoLibrary: copyIntoLibrary, libraryFolder: libraryFolder)
        }
    }

    private static func importOne(
        _ url: URL,
        copyIntoLibrary: Bool,
        libraryFolder: URL
    ) async throws {
        let fm = FileManager.default
        let originalPath = url.path
        let basename = url.deletingPathExtension().lastPathComponent

        let finalMediaURL: URL
        if copyIntoLibrary {
            let dest = libraryFolder.appendingPathComponent(url.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) {
                try fm.copyItem(at: url, to: dest)
            }
            finalMediaURL = dest
        } else {
            finalMediaURL = url
        }

        let thumbURL = libraryFolder.appendingPathComponent("\(basename).jpg")
        try? await FFmpegRunner.makeThumbnail(from: finalMediaURL, to: thumbURL, atSeconds: 5.0)

        let duration = (try? await FFmpegRunner.duration(of: finalMediaURL)) ?? 0
        let attrs = try fm.attributesOfItem(atPath: finalMediaURL.path)
        let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0

        let sidecar = SidecarJSON(
            schemaVersion: 1,
            title: basename,
            url: nil,
            site: .import,
            uploader: nil,
            duration: duration,
            format: "import",
            formatLabel: "Imported",
            fileSize: fileSize,
            fileName: finalMediaURL.lastPathComponent,
            thumbnailFile: fm.fileExists(atPath: thumbURL.path) ? "\(basename).jpg" : nil,
            dateAdded: Date(),
            description: nil,
            mediaFilePath: copyIntoLibrary ? nil : finalMediaURL.path,
            importedFromPath: originalPath
        )
        try sidecar.write(to: libraryFolder)
    }
}
