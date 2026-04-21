import Foundation

struct SearchResult: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let channel: String?
    let durationSeconds: Double?
    let thumbnailURL: URL?
    let viewCount: Int?

    var videoURL: String { "https://www.youtube.com/watch?v=\(id)" }
}
