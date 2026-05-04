import XCTest
@testable import VideoDownloader

final class SpotifyMetadataScraperTests: XCTestCase {
    private func loadFixture() throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "spotify_playlist_public", withExtension: "html") else {
            throw NSError(domain: "fixture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "fixture not bundled — check project.yml Fixtures resource"])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func test_parse_returnsPlaylistMetadata() throws {
        let html = try loadFixture()
        let result = try SpotifyMetadataScraper.parse(html: html, playlistID: "0sooekw4rFNXqCeOOVGtqY")
        XCTAssertEqual(result.id, "0sooekw4rFNXqCeOOVGtqY")
        XCTAssertEqual(result.uri, "spotify:playlist:0sooekw4rFNXqCeOOVGtqY")
        XCTAssertFalse(result.name.isEmpty)
        XCTAssertGreaterThan(result.trackCount, 0)
    }

    func test_parse_eachTrackHasRequiredFields() throws {
        let html = try loadFixture()
        let result = try SpotifyMetadataScraper.parse(html: html, playlistID: "0sooekw4rFNXqCeOOVGtqY")
        for track in result.tracks {
            XCTAssertFalse(track.id.isEmpty, "track id empty for \(track.title)")
            XCTAssertFalse(track.title.isEmpty, "track title empty")
            XCTAssertFalse(track.artists.isEmpty, "no artists for \(track.title)")
        }
    }

    func test_parse_emptyHTMLThrows() {
        XCTAssertThrowsError(try SpotifyMetadataScraper.parse(html: "", playlistID: "x"))
    }
}
