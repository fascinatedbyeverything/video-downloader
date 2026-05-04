import SwiftUI

struct SpotifyCaptureView: View {
    let active: SpotifyTabModel.ActiveCapture
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView(value: Double(active.completedTrackIDs.count),
                             total: Double(max(active.metadata.trackCount, 1)))
                    .progressViewStyle(.linear)
                Text("\(active.completedTrackIDs.count) / \(active.metadata.trackCount)")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
                Button("Stop") { onStop() }
            }

            if let nowPlaying = currentTrack {
                HStack {
                    Image(systemName: "waveform").foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text(nowPlaying.title).bold()
                        Text(nowPlaying.artists.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(8)
                .background(Color.green.opacity(0.08))
                .cornerRadius(6)
            }

            List {
                ForEach(active.metadata.tracks) { t in
                    HStack {
                        Image(systemName: status(for: t))
                            .foregroundStyle(active.completedTrackIDs.contains(t.id)
                                              ? Color.green
                                              : Color.secondary)
                        Text(String(format: "%02d", t.trackNumber ?? 0))
                            .frame(width: 28, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Text(t.title)
                        Spacer()
                        Text(t.artists.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var currentTrack: SpotifyTrack? {
        guard active.currentTrackIndex < active.metadata.tracks.count else { return nil }
        return active.metadata.tracks[active.currentTrackIndex]
    }

    private func status(for track: SpotifyTrack) -> String {
        if active.completedTrackIDs.contains(track.id) { return "checkmark.circle.fill" }
        if track.id == currentTrack?.id { return "circle.dotted" }
        return "circle"
    }
}
