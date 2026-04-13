import Foundation
import Observation

@Observable
final class QueueItem: Identifiable, @unchecked Sendable {
    let id: UUID = UUID()
    var url: String
    var title: String
    var durationSeconds: Double?
    var thumbnailURL: URL?
    var site: SiteSource
    var format: DownloadFormat
    var customFormats: [FormatRow]?
    var status: Status = .queued
    var percent: Double = 0
    var speed: String?
    var eta: String?
    var errorMessage: String?
    private(set) var runner: YTDLPRunner?

    enum Status: Equatable {
        case queued
        case running
        case complete
        case failed
        case cancelled
    }

    init(url: String, title: String, site: SiteSource, format: DownloadFormat = .best,
         durationSeconds: Double? = nil, thumbnailURL: URL? = nil) {
        self.url = url
        self.title = title
        self.site = site
        self.format = format
        self.durationSeconds = durationSeconds
        self.thumbnailURL = thumbnailURL
    }

    func attach(runner: YTDLPRunner) { self.runner = runner }
    func cancel() { runner?.cancel() }
}

@Observable
final class QueueModel {
    var items: [QueueItem] = []
    var isDownloading: Bool = false
    var currentIndex: Int? = nil

    /// Called after each successful download so the UI can refresh the library.
    @ObservationIgnored
    var onItemCompleted: (@Sendable @MainActor () async -> Void)?

    func add(_ item: QueueItem) { items.append(item) }
    func remove(id: UUID) { items.removeAll { $0.id == id } }

    @MainActor
    func addFromURL(_ url: String) async throws {
        let classification = URLClassifier.classify(url)
        switch classification {
        case .youtubePlaylist, .vimeoShowcase:
            let entries = try await PlaylistResolver.resolve(url)
            for e in entries {
                let thumb = e.thumbnailURL.flatMap { URL(string: $0) }
                let item = QueueItem(
                    url: e.url,
                    title: e.title,
                    site: classification.siteSource,
                    durationSeconds: e.durationSeconds,
                    thumbnailURL: thumb
                )
                items.append(item)
            }
        case .invalid:
            throw NSError(domain: "QueueModel", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Not a valid URL"])
        default:
            let item = QueueItem(url: url, title: url, site: classification.siteSource)
            items.append(item)
        }
    }

    @MainActor
    func startDownloads(libraryFolder: URL) async {
        guard !isDownloading else { return }
        isDownloading = true
        defer { isDownloading = false; currentIndex = nil }

        for (index, item) in items.enumerated() {
            guard item.status == .queued else { continue }
            currentIndex = index
            await runSingle(item, libraryFolder: libraryFolder)
        }
    }

    @MainActor
    private func runSingle(_ item: QueueItem, libraryFolder: URL) async {
        item.status = .running

        // Pick an output template that won't collide with an existing file.
        // Strategy: probe yt-dlp's predicted filename (with the final extension) and
        // if it already exists, append " v2", " v3", etc. until we find a free slot.
        let outputTemplate: String
        do {
            outputTemplate = try await Self.nextAvailableOutputTemplate(
                for: item.url,
                format: item.format,
                libraryFolder: libraryFolder
            )
        } catch {
            outputTemplate = libraryFolder.appendingPathComponent("%(title)s.%(ext)s").path
        }

        let opts = YTDLPDownloadOptions(
            url: item.url,
            format: item.format,
            outputTemplate: outputTemplate,
            writeThumbnail: true,
            writeInfoJSON: true
        )
        let runner = YTDLPRunner()
        item.attach(runner: runner)

        do {
            let result = try await runner.download(opts) { [item] progress in
                let pct = progress.percent
                let spd = progress.speedDescription
                let eta = progress.etaDescription
                Task { @MainActor in
                    item.percent = pct
                    item.speed = spd
                    item.eta = eta
                }
            }
            if result.exitCode == 0 {
                try await SidecarWriter.writeSidecar(
                    forQueueItem: item,
                    libraryFolder: libraryFolder,
                    ytdlpStdout: result.stdoutText
                )
                item.status = .complete
                await onItemCompleted?()
            } else {
                item.status = .failed
                item.errorMessage = result.stderrText
            }
        } catch {
            item.status = .failed
            item.errorMessage = error.localizedDescription
        }
    }

    /// Probe what filename yt-dlp would write, then pick a template whose output doesn't
    /// collide with an existing file. Returns a template (`%(title)s.%(ext)s` or with a
    /// ` v2`/` v3`/... suffix baked in).
    private static func nextAvailableOutputTemplate(
        for url: String,
        format: DownloadFormat,
        libraryFolder: URL
    ) async throws -> String {
        // Build a probe template with the final extension hardcoded so the predicted
        // filename reflects post-processing (mp4 for merged video, mp3/wav for audio).
        let finalExt: String = {
            switch format.audioPostProcess {
            case .mp3_320: return "mp3"
            case .wav_16_441: return "wav"
            case nil: return "mp4"
            }
        }()
        let probeTemplate = libraryFolder.appendingPathComponent("%(title)s.\(finalExt)").path
        let predictedPath = try await YTDLPRunner.probeFilename(
            url: url,
            outputTemplate: probeTemplate,
            ytdlpFormat: format.ytdlpFormat
        )
        let predicted = URL(fileURLWithPath: predictedPath)
        let fm = FileManager.default

        if !fm.fileExists(atPath: predicted.path) {
            return libraryFolder.appendingPathComponent("%(title)s.%(ext)s").path
        }

        // Collision — try " v2", " v3", ... until a slot opens.
        var version = 2
        while version < 1000 {
            let baseName = predicted.deletingPathExtension().lastPathComponent
            let candidate = libraryFolder.appendingPathComponent("\(baseName) v\(version).\(finalExt)")
            if !fm.fileExists(atPath: candidate.path) {
                return libraryFolder.appendingPathComponent("%(title)s v\(version).%(ext)s").path
            }
            version += 1
        }
        // Fallback (shouldn't happen)
        return libraryFolder.appendingPathComponent("%(title)s.%(ext)s").path
    }
}
