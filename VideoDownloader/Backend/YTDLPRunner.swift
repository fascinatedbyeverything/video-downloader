import Foundation

struct YTDLPResult {
    let exitCode: Int32
    let stdoutText: String
    let stderrText: String
}

struct YTDLPDownloadOptions {
    let url: String
    let format: DownloadFormat
    let outputTemplate: String   // e.g. "/path/%(title)s.%(ext)s"
    let writeThumbnail: Bool
    let writeInfoJSON: Bool
}

final class YTDLPRunner: @unchecked Sendable {
    private var process: Process?
    private var progressHandler: (@Sendable (DownloadProgress) -> Void)?
    private var stdoutBuffer = ""   // trailing partial line awaiting a newline
    private var fullStdout = ""     // complete captured stdout for post-run parsing

    func download(
        _ options: YTDLPDownloadOptions,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> YTDLPResult {
        let p = Process()
        p.executableURL = BinaryLocator.ytdlpURL
        p.arguments = buildArguments(options)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        p.standardOutput = stdoutPipe
        p.standardError = stderrPipe
        self.process = p
        self.progressHandler = onProgress

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self.handleStdout(text)
        }

        try p.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            p.terminationHandler = { _ in cont.resume() }
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = nil

        let stdoutData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
        let tail = String(data: stdoutData, encoding: .utf8) ?? ""
        let combinedStdout = fullStdout + tail
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

        // Debug log — always writes the last run's full output so we can see what happened
        let debugLog = """
        === yt-dlp run @ \(Date()) ===
        args: \(p.arguments ?? [])
        exitCode: \(p.terminationStatus)
        --- stdout ---
        \(combinedStdout)
        --- stderr ---
        \(stderrText)
        === end ===

        """
        try? debugLog.write(toFile: "/tmp/vd-last-download.log", atomically: true, encoding: .utf8)

        return YTDLPResult(
            exitCode: p.terminationStatus,
            stdoutText: combinedStdout,
            stderrText: stderrText
        )
    }

    func cancel() {
        process?.terminate()
    }

    private func handleStdout(_ chunk: String) {
        fullStdout += chunk
        stdoutBuffer += chunk
        var lines = stdoutBuffer.split(separator: "\n", omittingEmptySubsequences: false)
        let trailing = lines.removeLast()
        for line in lines {
            if let progress = ProgressParser.parse(String(line)) {
                progressHandler?(progress)
            }
        }
        stdoutBuffer = String(trailing)
    }

    private func buildArguments(_ o: YTDLPDownloadOptions) -> [String] {
        var args: [String] = []
        args += ["-f", o.format.ytdlpFormat]
        args += ["-o", o.outputTemplate]
        args += ["--newline"]
        args += ["--ffmpeg-location", BinaryLocator.ffmpegURL.path]

        switch o.format.audioPostProcess {
        case .mp3_320:
            args += ["-x", "--audio-format", "mp3", "--audio-quality", "320K"]
        case .wav_16_441:
            args += ["-x", "--audio-format", "wav"]
        case nil:
            // Video download — NEVER webm. Force H.264/H.265 preference and mp4 container.
            args += ["--format-sort", "vcodec:h264,vcodec:avc1,vcodec:h265,vcodec:hevc,ext:mp4"]
            args += ["--merge-output-format", "mp4"]
        }

        if o.writeThumbnail {
            args += ["--write-thumbnail", "--convert-thumbnails", "jpg"]
        }
        if o.writeInfoJSON {
            args += ["--write-info-json"]
        }
        // Print the final post-processed file path on its own line for SidecarWriter to parse.
        args += ["--print", "after_move:VDFINAL:%(filepath)s"]
        args += [o.url]
        return args
    }

    /// One-shot: run `yt-dlp -F <url>` and return the table as a string.
    static func listFormats(_ url: String) async throws -> String {
        let p = Process()
        p.executableURL = BinaryLocator.ytdlpURL
        p.arguments = ["-F", url]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            p.terminationHandler = { _ in cont.resume() }
        }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
