import SwiftUI
import AppKit

struct LibraryItemView: View {
    @Environment(LibraryModel.self) private var library
    let item: MediaItem
    enum Style { case grid, list }
    let style: Style
    @State private var sendError: String?

    var body: some View {
        switch style {
        case .grid: gridBody
        case .list: listBody
        }
    }

    private var gridBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(url: item.thumbnailURL)
                .aspectRatio(16/9, contentMode: .fit)
            Text(item.title).font(.headline).lineLimit(2)
            HStack(spacing: 6) {
                Image(systemName: item.site.systemImageName)
                Text(item.formatLabel).font(.caption)
                Spacer()
                if let d = item.duration { Text(formatDuration(d)).font(.caption) }
            }
            .foregroundStyle(.secondary)
            actionBar
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var listBody: some View {
        HStack(spacing: 12) {
            ThumbnailView(url: item.thumbnailURL)
                .frame(width: 160, height: 90)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline).lineLimit(1)
                HStack {
                    Image(systemName: item.site.systemImageName)
                    Text(item.site.displayName)
                    if let d = item.duration { Text("• \(formatDuration(d))") }
                    Text("• \(item.formatLabel)")
                }
                .font(.caption).foregroundStyle(.secondary)
                Text(item.fileURL.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            actionBar
        }
        .padding(8)
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            Button { preview() } label: { Image(systemName: "play.fill") }
                .help("Preview")
            Button { send() } label: { Image(systemName: "text.bubble") }
                .help("Send to Transcription Engine")
            Button { showInFinder() } label: { Image(systemName: "folder") }
                .help("Show in Finder")
            Button(role: .destructive) { library.remove(item) } label: {
                Image(systemName: "trash")
            }
            .help("Delete")
        }
        .buttonStyle(.borderless)
    }

    private func preview() {
        QuickLookPreview.show(url: item.fileURL)
    }

    private func send() {
        let url = item.fileURL
        Task {
            do { try await TranscriptionEngineLauncher.send(fileURL: url) }
            catch {
                let msg = error.localizedDescription
                await MainActor.run { sendError = msg }
            }
        }
    }

    private func showInFinder() {
        NSWorkspace.shared.selectFile(item.fileURL.path, inFileViewerRootedAtPath: item.fileURL.deletingLastPathComponent().path)
    }

    private func formatDuration(_ s: Double) -> String {
        let total = Int(s)
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
