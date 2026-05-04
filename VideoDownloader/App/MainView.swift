import SwiftUI

struct MainView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case search = "Search"
        case queue = "Queue"
        case library = "Library"
        case spotify = "Spotify"
        var id: String { rawValue }
    }
    @State private var selected: Tab = .search

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selected) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch selected {
            case .search: SearchView()
            case .queue: QueueView()
            case .library: LibraryView()
            case .spotify: SpotifyTabView()
            }
        }
    }
}
