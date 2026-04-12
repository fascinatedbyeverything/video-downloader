import XCTest
@testable import VideoDownloader

final class SidecarJSONTests: XCTestCase {
    func testRoundTripDownloadedItem() throws {
        let original = SidecarJSON(
            schemaVersion: 1,
            title: "Test Video",
            url: "https://www.youtube.com/watch?v=abc",
            site: .youtube,
            uploader: "Test Channel",
            duration: 3612,
            format: "bestvideo+bestaudio",
            formatLabel: "Best",
            fileSize: 141557760,
            fileName: "Test Video.mp4",
            thumbnailFile: "Test Video.jpg",
            dateAdded: Date(timeIntervalSince1970: 1744000000),
            description: "A test description",
            mediaFilePath: nil,
            importedFromPath: nil
        )
        let data = try JSONEncoder.pretty.encode(original)
        let decoded = try JSONDecoder.iso.decode(SidecarJSON.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testImportInPlaceStoresMediaFilePath() throws {
        let item = SidecarJSON(
            schemaVersion: 1,
            title: "Imported Clip",
            url: nil,
            site: .import,
            uploader: nil,
            duration: 120,
            format: "import",
            formatLabel: "Imported",
            fileSize: 12345,
            fileName: "Imported Clip.mp4",
            thumbnailFile: "Imported Clip.jpg",
            dateAdded: Date(timeIntervalSince1970: 1744000000),
            description: nil,
            mediaFilePath: "/Users/chrisholmes/Movies/Imported Clip.mp4",
            importedFromPath: "/Users/chrisholmes/Movies/Imported Clip.mp4"
        )
        let data = try JSONEncoder.pretty.encode(item)
        let decoded = try JSONDecoder.iso.decode(SidecarJSON.self, from: data)
        XCTAssertEqual(decoded.mediaFilePath, "/Users/chrisholmes/Movies/Imported Clip.mp4")
        XCTAssertEqual(decoded.site, .import)
        XCTAssertNil(decoded.url)
    }
}
