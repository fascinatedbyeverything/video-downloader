import Foundation

enum FFmpegError: Error {
    case failed(exitCode: Int32, stderr: String)
}

enum FFmpegRunner {
    /// Extract a JPG thumbnail at a specific time offset.
    static func makeThumbnail(
        from mediaURL: URL,
        to outputURL: URL,
        atSeconds: Double = 5.0
    ) async throws {
        let p = Process()
        p.executableURL = BinaryLocator.ffmpegURL
        p.arguments = [
            "-y",
            "-ss", String(atSeconds),
            "-i", mediaURL.path,
            "-vframes", "1",
            "-q:v", "3",
            outputURL.path
        ]
        let stderrPipe = Pipe()
        p.standardError = stderrPipe
        p.standardOutput = Pipe()
        try p.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            p.terminationHandler = { _ in cont.resume() }
        }
        if p.terminationStatus != 0 {
            let data = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            throw FFmpegError.failed(
                exitCode: p.terminationStatus,
                stderr: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }

    /// Return duration in seconds by parsing ffmpeg's stderr "Duration:" line.
    static func duration(of mediaURL: URL) async throws -> Double {
        let p = Process()
        p.executableURL = BinaryLocator.ffmpegURL
        p.arguments = ["-i", mediaURL.path]
        let stderrPipe = Pipe()
        p.standardError = stderrPipe
        p.standardOutput = Pipe()
        try p.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            p.terminationHandler = { _ in cont.resume() }
        }
        let data = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""
        let pattern = #"Duration:\s+(\d+):(\d+):(\d+\.?\d*)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let hR = Range(match.range(at: 1), in: text),
              let mR = Range(match.range(at: 2), in: text),
              let sR = Range(match.range(at: 3), in: text),
              let h = Double(text[hR]), let m = Double(text[mR]), let s = Double(text[sR])
        else {
            return 0
        }
        return h * 3600 + m * 60 + s
    }
}
