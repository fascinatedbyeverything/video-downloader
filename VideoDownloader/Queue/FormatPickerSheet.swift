import SwiftUI

struct FormatPickerSheet: View {
    let url: String
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var formats: [FormatRow] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selection: FormatRow.ID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pick format").font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
            }
            .padding(12)

            Divider()

            if loading {
                ProgressView("Probing formats…").padding()
            } else if let error {
                Text(error).foregroundStyle(.red).padding()
            } else {
                Table(formats, selection: $selection) {
                    TableColumn("ID") { Text($0.formatID).monospaced() }
                    TableColumn("Ext") { Text($0.container) }
                    TableColumn("Resolution") { Text($0.resolution) }
                    TableColumn("FPS") { Text($0.fps ?? "—") }
                    TableColumn("Size") { Text($0.fileSize ?? "—") }
                    TableColumn("Notes") { Text($0.note ?? "") }
                }
                .frame(minHeight: 300)
            }

            Divider()

            HStack {
                Spacer()
                Button("Apply") {
                    guard let id = selection,
                          let row = formats.first(where: { $0.id == id }) else { return }
                    onSelect(row.formatID)
                }
                .disabled(selection == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 700, height: 480)
        .task { await probe() }
    }

    private func probe() async {
        do {
            let text = try await YTDLPRunner.listFormats(url)
            let rows = FormatProbe.parse(text)
            await MainActor.run {
                self.formats = rows
                self.loading = false
            }
        } catch {
            let message = error.localizedDescription
            await MainActor.run {
                self.error = message
                self.loading = false
            }
        }
    }
}
