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

    func add(_ item: QueueItem) { items.append(item) }
    func remove(id: UUID) { items.removeAll { $0.id == id } }

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
        let outputTemplate = libraryFolder.appendingPathComponent("%(title)s.%(ext)s").path
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
            } else {
                item.status = .failed
                item.errorMessage = result.stderrText
            }
        } catch {
            item.status = .failed
            item.errorMessage = error.localizedDescription
        }
    }
}
