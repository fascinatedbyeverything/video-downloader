import AppKit
import QuickLookUI

final class QuickLookPreview: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate, @unchecked Sendable {
    nonisolated(unsafe) static let shared = QuickLookPreview()

    private let lock = NSLock()
    private var _currentURL: URL?
    private var currentURL: URL? {
        get { lock.withLock { _currentURL } }
        set { lock.withLock { _currentURL = newValue } }
    }

    @MainActor
    static func show(url: URL) {
        shared.currentURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = shared
        panel.delegate = shared
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        currentURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        currentURL as QLPreviewItem?
    }
}
