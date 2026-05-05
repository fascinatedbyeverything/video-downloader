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
    @AppStorage("useChromeCookies") private var useChromeCookies: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selected) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.top, 8)

            HStack(spacing: 6) {
                Toggle(isOn: $useChromeCookies) {
                    Text("Use Chrome cookies")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Send the user's logged-in Chrome session to yt-dlp. Required for private playlists — e.g. Spotify-imported YouTube Music playlists default to private.")
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

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
