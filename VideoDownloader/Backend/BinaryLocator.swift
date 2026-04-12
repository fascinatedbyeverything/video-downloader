import Foundation

enum BinaryLocator {
    static let supportDirName = "VideoDownloader"
    static let binSubdir = "bin"

    /// Absolute path to the system ffmpeg installed by Homebrew.
    static let systemFFmpegPath = "/opt/homebrew/bin/ffmpeg"

    static var supportDir: URL {
        let fm = FileManager.default
        let base = try! fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent(supportDirName)
    }

    static var binDir: URL {
        supportDir.appendingPathComponent(binSubdir)
    }

    /// The yt-dlp binary in Application Support (after first-launch install).
    static var ytdlpURL: URL { binDir.appendingPathComponent("yt-dlp") }

    /// The system ffmpeg (Homebrew). Not bundled.
    static var ffmpegURL: URL { URL(fileURLWithPath: systemFFmpegPath) }

    /// Copies the bundled yt-dlp to Application Support if missing.
    /// The .app bundle is read-only at runtime, so yt-dlp -U needs a writable copy.
    static func ensureBinariesInstalled() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)

        let dest = ytdlpURL
        guard !fm.fileExists(atPath: dest.path) else { return }
        guard let src = Bundle.main.url(forResource: "yt-dlp", withExtension: nil) else {
            throw NSError(domain: "BinaryLocator", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "yt-dlp missing from app bundle"])
        }
        try fm.copyItem(at: src, to: dest)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
    }

    /// Returns true if the system ffmpeg exists at the expected Homebrew path.
    static var isFFmpegAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: systemFFmpegPath)
    }
}
