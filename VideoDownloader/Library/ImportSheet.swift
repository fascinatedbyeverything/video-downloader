import SwiftUI
import UniformTypeIdentifiers

struct ImportSheet: View {
    let onCompletion: () -> Void
    @State private var urls: [URL] = []
    @State private var copyIntoLibrary: Bool = false
    @State private var isImporting = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Files").font(.title2).bold()
            Button("Choose Files…") { chooseFiles() }

            List(urls, id: \.self) { Text($0.lastPathComponent) }
                .frame(minHeight: 120)

            Toggle("Copy into library folder", isOn: $copyIntoLibrary)

            if let errorText {
                Text(errorText).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCompletion).keyboardShortcut(.cancelAction)
                Button(isImporting ? "Importing…" : "Import") { doImport() }
                    .disabled(urls.isEmpty || isImporting)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 520)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .audio, .mpeg4Movie, .quickTimeMovie, .mp3, .wav]
        if panel.runModal() == .OK { urls = panel.urls }
    }

    private func doImport() {
        isImporting = true
        errorText = nil
        let capturedURLs = urls
        let capturedCopy = copyIntoLibrary
        Task {
            do {
                try await ImportRunner.importFiles(capturedURLs,
                    copyIntoLibrary: capturedCopy,
                    libraryFolder: DriveCheck.libraryFolder)
                await MainActor.run { onCompletion() }
            } catch {
                let msg = error.localizedDescription
                await MainActor.run {
                    errorText = msg
                    isImporting = false
                }
            }
        }
    }
}
