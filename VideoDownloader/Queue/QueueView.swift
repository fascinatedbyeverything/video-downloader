import SwiftUI

struct QueueView: View {
    @Environment(QueueModel.self) private var queue
    @State private var urlInput: String = ""
    @State private var isAdding = false
    @State private var addError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Paste YouTube / Vimeo URL (video or playlist)", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add() }
                Button("Add to Queue", action: add)
                    .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
            }
            .padding(8)

            if let addError {
                Text(addError).foregroundStyle(.red).font(.caption).padding(.horizontal, 8)
            }

            Divider()

            List {
                ForEach(queue.items) { item in
                    QueueRow(item: item, onRemove: { queue.remove(id: item.id) })
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Spacer()
                Button("Download All") {
                    Task { await queue.startDownloads(libraryFolder: DriveCheck.libraryFolder) }
                }
                .disabled(queue.items.allSatisfy { $0.status != .queued } || queue.isDownloading)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(8)
        }
    }

    private func add() {
        let input = urlInput.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }
        isAdding = true
        addError = nil
        Task {
            do {
                try await queue.addFromURL(input)
                urlInput = ""
            } catch {
                addError = error.localizedDescription
            }
            isAdding = false
        }
    }
}
