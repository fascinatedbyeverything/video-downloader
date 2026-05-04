import SwiftUI
import AppKit

struct SpotifyTabView: View {
    @State private var model = SpotifyTabModel()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Paste Spotify playlist URL…", text: $model.pastedURL)
                    .textFieldStyle(.roundedBorder)
                Button("Load") {
                    Task { await model.loadPreview() }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(model.pastedURL.isEmpty)
            }

            Divider()

            switch model.phase {
            case .idle:
                ContentUnavailableView("Paste a Spotify playlist link",
                                       systemImage: "music.note.list",
                                       description: Text("Premium account, Spotify Mac app, real-time capture."))
            case .loadingPreview:
                ProgressView("Loading preview…").controlSize(.large)
            case .preview(let meta):
                SpotifyPreviewView(metadata: meta) { folder in
                    Task { await model.startCapture(outputFolder: folder) }
                }
            case .capturing(let active):
                SpotifyCaptureView(active: active, onStop: { model.stopCapture() })
            case .finished(let folder, let count):
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                    Text("Captured \(count) tracks").font(.title2)
                    HStack {
                        Button("Open in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([folder])
                        }
                        Button("Capture another") { model.phase = .idle }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let msg):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text(msg).multilineTextAlignment(.center).padding(.horizontal)
                    Button("Reset") { model.phase = .idle }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}
