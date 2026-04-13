import SwiftUI

@main
struct VideoDownloaderApp: App {
    @State private var queue = QueueModel()
    @State private var library = LibraryModel()
    @State private var driveMissing = false

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(queue)
                .environment(library)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    do {
                        try BinaryLocator.ensureBinariesInstalled()
                    } catch {
                        print("Failed to install binaries: \(error)")
                    }
                    if !DriveCheck.isLibraryDriveMounted {
                        driveMissing = true
                        return
                    }
                    queue.onItemCompleted = { [weak library] in
                        await library?.scan(folder: DriveCheck.libraryFolder)
                    }
                    Task.detached { await Updater.updateYTDLP() }
                    await library.scan(folder: DriveCheck.libraryFolder)
                }
                .alert("1tb drive not mounted",
                       isPresented: $driveMissing,
                       actions: {
                           Button("Quit") { NSApp.terminate(nil) }
                       },
                       message: {
                           Text("Please connect the drive at /Volumes/1tb  and relaunch.")
                       })
        }
    }
}
