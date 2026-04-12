import Foundation

enum SiteSource: String, Codable, CaseIterable {
    case youtube
    case vimeo
    case `import`  // imported from disk, not downloaded
    case other     // catch-all for yt-dlp supported sites we don't specialize

    var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .vimeo: return "Vimeo"
        case .import: return "Imported"
        case .other: return "Other"
        }
    }

    var systemImageName: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .vimeo: return "v.circle.fill"
        case .import: return "square.and.arrow.down.fill"
        case .other: return "film"
        }
    }
}
