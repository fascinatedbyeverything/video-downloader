import Foundation

enum Updater {
    /// Runs `yt-dlp -U` in background with a 30s timeout. Logs via print. Never throws.
    /// Called on app launch from VideoDownloaderApp.
    static func updateYTDLP() async {
        let process = Process()
        process.executableURL = BinaryLocator.ytdlpURL
        process.arguments = ["-U"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            print("Updater: failed to launch yt-dlp -U: \(error)")
            return
        }

        let deadline = Date().addingTimeInterval(30)
        while process.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if process.isRunning {
            process.terminate()
            print("Updater: yt-dlp -U timed out")
            return
        }
        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""
        print("Updater: yt-dlp -U status=\(process.terminationStatus) output=\(output)")
    }
}
