import AppKit
import Foundation

enum TranscriptionEngineLauncher {
    enum LauncherError: Error { case notFound }

    /// Returns the URL of the highest-numbered Transcription Engine app in /Applications/, or nil.
    static func findApp() -> URL? {
        let fm = FileManager.default
        let apps = (try? fm.contentsOfDirectory(atPath: "/Applications")) ?? []
        let teApps = apps.filter { $0.hasPrefix("Transcription Engine v") && $0.hasSuffix(".app") }
        let sorted = teApps.sorted { a, b in
            func v(_ s: String) -> Int {
                let num = s
                    .replacingOccurrences(of: "Transcription Engine v", with: "")
                    .replacingOccurrences(of: ".app", with: "")
                return Int(num) ?? 0
            }
            return v(a) < v(b)
        }
        guard let newest = sorted.last else { return nil }
        return URL(fileURLWithPath: "/Applications/\(newest)")
    }

    /// Launch TE with the given media file URL as an open-file argument.
    static func send(fileURL: URL) async throws {
        guard let appURL = findApp() else { throw LauncherError.notFound }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try await NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config)
    }
}
