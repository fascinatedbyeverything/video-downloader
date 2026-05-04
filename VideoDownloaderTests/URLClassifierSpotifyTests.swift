import XCTest
@testable import VideoDownloader

final class URLClassifierSpotifyTests: XCTestCase {
    func test_classify_spotifyPlaylistHTTPS() {
        XCTAssertEqual(URLClassifier.classify("https://open.spotify.com/playlist/0sooekw4rFNXqCeOOVGtqY"),
                       .spotifyPlaylist)
    }

    func test_classify_spotifyPlaylistWithQuery() {
        XCTAssertEqual(URLClassifier.classify("https://open.spotify.com/playlist/0sooekw4rFNXqCeOOVGtqY?si=0fd0e99f38ca4702"),
                       .spotifyPlaylist)
    }

    func test_classify_spotifyURIPlaylist() {
        XCTAssertEqual(URLClassifier.classify("spotify:playlist:0sooekw4rFNXqCeOOVGtqY"),
                       .spotifyPlaylist)
    }

    func test_classify_spotifyTrackHTTPS() {
        XCTAssertEqual(URLClassifier.classify("https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh"),
                       .spotifyTrack)
    }

    func test_classify_spotifyURITrack() {
        XCTAssertEqual(URLClassifier.classify("spotify:track:4iV5W9uYEdYUVa79Axb7Rh"),
                       .spotifyTrack)
    }

    func test_siteSource_isSpotifyForBoth() {
        XCTAssertEqual(URLClassification.spotifyPlaylist.siteSource, .spotify)
        XCTAssertEqual(URLClassification.spotifyTrack.siteSource, .spotify)
    }

    func test_youtubeVimeoStillWork() {
        XCTAssertEqual(URLClassifier.classify("https://www.youtube.com/watch?v=abc"), .youtubeVideo)
        XCTAssertEqual(URLClassifier.classify("https://vimeo.com/123456"), .vimeoVideo)
    }
}
