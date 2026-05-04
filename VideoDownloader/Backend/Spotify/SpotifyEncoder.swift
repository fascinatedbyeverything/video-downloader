import Foundation
import AVFoundation

enum SpotifyEncoderError: Error {
    case wavWriteFailed(String)
    case ffmpegFailed(Int32, String)
}

struct SpotifyEncodeRequest {
    let segment: SpotifySegmentResult
    let trackNumber: Int
    let outputFolder: URL
    let coverArtURL: URL?
}

enum SpotifyEncoder {
    /// Writes WAV (16-bit PCM) and MP3 320 to outputFolder.
    /// Filenames: "<NN> - <Artist> - <Title>.{wav,mp3}".
    static func encode(_ req: SpotifyEncodeRequest) async throws -> (wav: URL, mp3: URL) {
        let baseName = filename(req: req)
        let wavURL = req.outputFolder.appendingPathComponent("\(baseName).wav")
        let mp3URL = req.outputFolder.appendingPathComponent("\(baseName).mp3")

        try writeWAV(samples: req.segment.samples,
                     sampleRate: req.segment.sampleRate,
                     channelCount: req.segment.channelCount,
                     to: wavURL)

        try await runFFmpegToMP3(
            wavURL: wavURL,
            mp3URL: mp3URL,
            title: req.segment.trackName,
            artist: req.segment.artist,
            album: req.segment.album,
            trackNumber: req.trackNumber,
            coverArtURL: req.coverArtURL
        )

        return (wav: wavURL, mp3: mp3URL)
    }

    private static func filename(req: SpotifyEncodeRequest) -> String {
        let nn = String(format: "%02d", req.trackNumber)
        let artist = sanitize(req.segment.artist).trimmingCharacters(in: .whitespaces)
        let title = sanitize(req.segment.trackName).trimmingCharacters(in: .whitespaces)
        if artist.isEmpty { return "\(nn) - \(title)" }
        return "\(nn) - \(artist) - \(title)"
    }

    private static func sanitize(_ s: String) -> String {
        let bad: Set<Character> = ["/", ":", "\\", "*", "?", "\"", "<", ">", "|"]
        return String(s.map { bad.contains($0) ? "-" : $0 })
    }

    private static func writeWAV(samples: [Float], sampleRate: Double, channelCount: Int, to url: URL) throws {
        guard channelCount > 0, !samples.isEmpty else {
            throw SpotifyEncoderError.wavWriteFailed("empty samples or zero channels")
        }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: true
        ) else {
            throw SpotifyEncoderError.wavWriteFailed("invalid format")
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: true)

        let frameCount = AVAudioFrameCount(samples.count / channelCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw SpotifyEncoderError.wavWriteFailed("buffer alloc")
        }
        buffer.frameLength = frameCount
        if let dst = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { src in
                memcpy(dst[0], src.baseAddress, samples.count * MemoryLayout<Float>.size)
            }
        }
        try file.write(from: buffer)
    }

    private static func runFFmpegToMP3(
        wavURL: URL, mp3URL: URL,
        title: String, artist: String, album: String,
        trackNumber: Int, coverArtURL: URL?
    ) async throws {
        var args: [String] = ["-y", "-i", wavURL.path]

        var coverTmpURL: URL?
        if let cover = coverArtURL,
           let data = try? Data(contentsOf: cover) {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("vd_cover_\(UUID().uuidString).jpg")
            try? data.write(to: tmp)
            coverTmpURL = tmp
            args += [
                "-i", tmp.path,
                "-map", "0:a", "-map", "1:0",
                "-c:v", "copy",
                "-id3v2_version", "3",
                "-metadata:s:v", "title=Album cover",
                "-metadata:s:v", "comment=Cover (front)"
            ]
        }
        args += [
            "-codec:a", "libmp3lame",
            "-b:a", "320k",
            "-metadata", "title=\(title)",
            "-metadata", "artist=\(artist)",
            "-metadata", "album=\(album)",
            "-metadata", "track=\(trackNumber)",
            mp3URL.path
        ]

        let p = Process()
        p.executableURL = BinaryLocator.ffmpegURL
        p.arguments = args
        let errPipe = Pipe()
        p.standardError = errPipe
        try p.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            p.terminationHandler = { _ in cont.resume() }
        }
        if let tmp = coverTmpURL { try? FileManager.default.removeItem(at: tmp) }
        if p.terminationStatus != 0 {
            let errText = String(data: (try? errPipe.fileHandleForReading.readToEnd()) ?? Data(), encoding: .utf8) ?? ""
            throw SpotifyEncoderError.ffmpegFailed(p.terminationStatus, errText)
        }
    }
}
