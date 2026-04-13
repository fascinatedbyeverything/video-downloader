import SwiftUI

struct QueueRow: View {
    @Bindable var item: QueueItem
    let onRemove: () -> Void
    @State private var showingCustomPicker = false

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(url: item.thumbnailURL)
                .frame(width: 120, height: 68)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline).lineLimit(2)
                HStack {
                    Image(systemName: item.site.systemImageName)
                    Text(item.site.displayName)
                    if let d = item.durationSeconds {
                        Text("• \(formatDuration(d))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if item.status == .running {
                    ProgressView(value: item.percent, total: 100)
                    HStack {
                        if let s = item.speed { Text(s).font(.caption2) }
                        if let e = item.eta { Text("ETA \(e)").font(.caption2) }
                    }
                }
                if item.status == .complete {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Downloaded — open Library tab").font(.caption2).foregroundStyle(.green)
                    }
                }
                if item.status == .failed, let msg = item.errorMessage {
                    Text(msg).font(.caption2).foregroundStyle(.red).lineLimit(2)
                }
            }

            Spacer()

            Picker("", selection: Binding(
                get: { formatPickerSelection(item.format) },
                set: { handleFormatSelection($0) }
            )) {
                ForEach(DownloadFormat.presets, id: \.self) { preset in
                    Text(preset.displayName).tag(formatPickerSelection(preset))
                }
                Divider()
                Text("Custom…").tag("custom")
            }
            .frame(width: 180)
            .disabled(item.status != .queued)

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .disabled(item.status == .running)
        }
        .sheet(isPresented: $showingCustomPicker) {
            FormatPickerSheet(
                url: item.url,
                onSelect: { id in
                    item.format = .custom(formatID: id)
                    showingCustomPicker = false
                },
                onCancel: { showingCustomPicker = false }
            )
        }
    }

    private func formatPickerSelection(_ f: DownloadFormat) -> String {
        switch f {
        case .custom: return "custom"
        default: return f.displayName
        }
    }

    private func handleFormatSelection(_ sel: String) {
        if sel == "custom" {
            showingCustomPicker = true
            return
        }
        if let match = DownloadFormat.presets.first(where: { $0.displayName == sel }) {
            item.format = match
        }
    }

    private func formatDuration(_ s: Double) -> String {
        let total = Int(s)
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

struct ThumbnailView: View {
    let url: URL?
    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: placeholder
                    }
                }
            } else { placeholder }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.2)
            Image(systemName: "film").foregroundStyle(.secondary)
        }
    }
}
