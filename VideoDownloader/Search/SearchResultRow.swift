import SwiftUI

struct SearchResultRow: View {
    let result: SearchResult
    @Environment(QueueModel.self) private var queue
    @State private var showingFormatPicker = false
    @State private var lastAction: String?

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(url: result.thumbnailURL)
                .frame(width: 120, height: 68)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title).font(.headline).lineLimit(2)
                HStack(spacing: 6) {
                    if let channel = result.channel, !channel.isEmpty {
                        Text(channel)
                    }
                    if let d = result.durationSeconds {
                        Text("· \(formatDuration(d))")
                    }
                    if let v = result.viewCount {
                        Text("· \(formatViews(v)) views")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let lastAction {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(lastAction).foregroundStyle(.green)
                    }
                    .font(.caption2)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Button("Download MP3") { downloadMP3() }
                    .buttonStyle(.borderedProminent)

                Menu {
                    Button("Download as…") { showingFormatPicker = true }
                    Button("Add to Queue (paused)") { addToQueuePaused() }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingFormatPicker) {
            FormatPickerSheet(
                url: result.videoURL,
                onSelect: { formatID in
                    download(format: .custom(formatID: formatID))
                    showingFormatPicker = false
                },
                onCancel: { showingFormatPicker = false }
            )
        }
    }

    private func downloadMP3() {
        download(format: .audioMP3)
    }

    private func download(format: DownloadFormat) {
        let item = makeQueueItem(format: format)
        queue.add(item)
        lastAction = "Added — downloading (\(format.displayName))"
        Task {
            await queue.startDownloads(libraryFolder: DriveCheck.libraryFolder)
        }
    }

    private func addToQueuePaused() {
        let item = makeQueueItem(format: .audioMP3)
        queue.add(item)
        lastAction = "Added to Queue (paused)"
    }

    private func makeQueueItem(format: DownloadFormat) -> QueueItem {
        QueueItem(
            url: result.videoURL,
            title: result.title,
            site: .youtube,
            format: format,
            durationSeconds: result.durationSeconds,
            thumbnailURL: result.thumbnailURL
        )
    }

    private func formatDuration(_ s: Double) -> String {
        let total = Int(s)
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    private func formatViews(_ n: Int) -> String {
        switch n {
        case 1_000_000...:
            let m = Double(n) / 1_000_000
            return String(format: "%.1fM", m)
        case 1_000...:
            let k = Double(n) / 1_000
            return String(format: "%.1fK", k)
        default:
            return "\(n)"
        }
    }
}
