import Foundation
import Observation

@Observable
final class LibraryModel {
    var items: [MediaItem] = []
    var searchQuery: String = ""
    var sort: Sort = .dateAddedDesc
    var viewMode: ViewMode = .grid

    enum Sort: String, CaseIterable {
        case dateAddedDesc = "Newest"
        case dateAddedAsc = "Oldest"
        case titleAsc = "Title A–Z"
        case durationDesc = "Longest"
        case fileSizeDesc = "Largest"
    }

    enum ViewMode: String, CaseIterable {
        case grid, list
    }

    var filteredItems: [MediaItem] {
        var list = items
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.title.lowercased().contains(q) ||
                ($0.url ?? "").lowercased().contains(q)
            }
        }
        switch sort {
        case .dateAddedDesc: list.sort { $0.dateAdded > $1.dateAdded }
        case .dateAddedAsc: list.sort { $0.dateAdded < $1.dateAdded }
        case .titleAsc: list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .durationDesc: list.sort { ($0.duration ?? 0) > ($1.duration ?? 0) }
        case .fileSizeDesc: list.sort { ($0.fileSize ?? 0) > ($1.fileSize ?? 0) }
        }
        return list
    }

    @MainActor
    func scan(folder: URL) async {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            items = []
            return
        }
        let sidecars = contents.filter { $0.lastPathComponent.hasSuffix(".\(SidecarJSON.fileExtension)") }
        var result: [MediaItem] = []
        for url in sidecars {
            guard let side = try? SidecarJSON.read(from: url) else { continue }
            result.append(MediaItem.fromSidecar(side, sidecarURL: url, libraryFolder: folder))
        }
        self.items = result
    }

    @MainActor
    func remove(_ item: MediaItem) {
        items.removeAll { $0.id == item.id }
        let fm = FileManager.default
        try? fm.trashItem(at: item.sidecarURL, resultingItemURL: nil)
        try? fm.trashItem(at: item.fileURL, resultingItemURL: nil)
        if let thumb = item.thumbnailURL {
            try? fm.trashItem(at: thumb, resultingItemURL: nil)
        }
    }
}
