import Foundation

struct MediaItem: Identifiable, Equatable, Hashable {
    let id: UUID
    var title: String
    var url: String?
    var site: SiteSource
    var uploader: String?
    var duration: Double?
    var formatLabel: String
    var fileSize: Int64?
    var fileURL: URL
    var sidecarURL: URL
    var thumbnailURL: URL?
    var dateAdded: Date
    var description: String?

    /// Build a MediaItem from a sidecar found during library scan.
    static func fromSidecar(
        _ sidecar: SidecarJSON,
        sidecarURL: URL,
        libraryFolder: URL
    ) -> MediaItem {
        let mediaURL: URL
        if let externalPath = sidecar.mediaFilePath {
            mediaURL = URL(fileURLWithPath: externalPath)
        } else {
            mediaURL = libraryFolder.appendingPathComponent(sidecar.fileName)
        }
        let thumbURL = sidecar.thumbnailFile.map { libraryFolder.appendingPathComponent($0) }
        return MediaItem(
            id: UUID(),
            title: sidecar.title,
            url: sidecar.url,
            site: sidecar.site,
            uploader: sidecar.uploader,
            duration: sidecar.duration,
            formatLabel: sidecar.formatLabel,
            fileSize: sidecar.fileSize,
            fileURL: mediaURL,
            sidecarURL: sidecarURL,
            thumbnailURL: thumbURL,
            dateAdded: sidecar.dateAdded,
            description: sidecar.description
        )
    }
}
