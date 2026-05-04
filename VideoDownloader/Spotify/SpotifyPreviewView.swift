import SwiftUI
import AppKit

struct SpotifyPreviewView: View {
    let metadata: SpotifyPlaylistMetadata
    let onStart: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let cover = metadata.coverURL {
                    AsyncImage(url: cover) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.secondary.opacity(0.2)
                    }
                    .frame(width: 96, height: 96)
                    .cornerRadius(6)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 96, height: 96)
                        .overlay(Image(systemName: "music.note.list").foregroundStyle(.secondary))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata.name).font(.title2).bold()
                    Text("\(metadata.trackCount) tracks · \(formatDuration(metadata.totalDurationMs))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Real-time capture (≈ same wall-clock time as the playlist).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Start Capture…") {
                    pickFolder { url in onStart(url) }
                }
                .buttonStyle(.borderedProminent)
            }

            List(metadata.tracks) { t in
                HStack {
                    Text(String(format: "%02d", t.trackNumber ?? 0))
                        .frame(width: 28, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(t.title)
                        Text(t.artists.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(formatDuration(t.durationMs))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 200)
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        let total = ms / 1000
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    private func pickFolder(_ done: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Capture Here"
        panel.message = "Choose a folder to save WAV + MP3 files"
        if panel.runModal() == .OK, let url = panel.url { done(url) }
    }
}
