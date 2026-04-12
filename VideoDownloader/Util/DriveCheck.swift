import Foundation

enum DriveCheck {
    static let libraryFolder = URL(fileURLWithPath:
        "/Volumes/1tb /claude code projects /youtube-downloads")

    static var isLibraryDriveMounted: Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: libraryFolder.path, isDirectory: &isDir
        )
        return exists && isDir.boolValue
    }
}
