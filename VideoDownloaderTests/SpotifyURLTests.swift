import XCTest
@testable import VideoDownloader

final class SpotifyURLTests: XCTestCase {
    func test_playlistURI_fromHTTPS() {
        let r = SpotifyURL.parse("https://open.spotify.com/playlist/0sooekw4rFNXqCeOOVGtqY?si=abc")
        XCTAssertEqual(r?.uri, "spotify:playlist:0sooekw4rFNXqCeOOVGtqY")
        XCTAssertEqual(r?.kind, .playlist)
        XCTAssertEqual(r?.id, "0sooekw4rFNXqCeOOVGtqY")
    }

    func test_playlistURI_fromSpotifyScheme() {
        let r = SpotifyURL.parse("spotify:playlist:0sooekw4rFNXqCeOOVGtqY")
        XCTAssertEqual(r?.uri, "spotify:playlist:0sooekw4rFNXqCeOOVGtqY")
    }

    func test_trackURI_fromHTTPS() {
        let r = SpotifyURL.parse("https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh")
        XCTAssertEqual(r?.uri, "spotify:track:4iV5W9uYEdYUVa79Axb7Rh")
        XCTAssertEqual(r?.kind, .track)
    }

    func test_publicWebURL_forPlaylist() {
        let r = SpotifyURL.parse("spotify:playlist:0sooekw4rFNXqCeOOVGtqY")
        XCTAssertEqual(r?.publicWebURL, "https://open.spotify.com/playlist/0sooekw4rFNXqCeOOVGtqY")
    }

    func test_garbageReturnsNil() {
        XCTAssertNil(SpotifyURL.parse("https://example.com/foo"))
        XCTAssertNil(SpotifyURL.parse(""))
        XCTAssertNil(SpotifyURL.parse("not a url"))
    }
}
