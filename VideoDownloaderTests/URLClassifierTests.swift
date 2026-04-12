import XCTest
@testable import VideoDownloader

final class URLClassifierTests: XCTestCase {
    func testYouTubeVideoURL() {
        let result = URLClassifier.classify("https://www.youtube.com/watch?v=abc123")
        XCTAssertEqual(result, .youtubeVideo)
    }

    func testYouTubeShortURL() {
        let result = URLClassifier.classify("https://youtu.be/abc123")
        XCTAssertEqual(result, .youtubeVideo)
    }

    func testYouTubePlaylistURL() {
        let result = URLClassifier.classify("https://www.youtube.com/playlist?list=PLxxx")
        XCTAssertEqual(result, .youtubePlaylist)
    }

    func testYouTubeWatchWithListURLTreatedAsPlaylist() {
        let result = URLClassifier.classify("https://www.youtube.com/watch?v=abc&list=PLxxx")
        XCTAssertEqual(result, .youtubePlaylist)
    }

    func testVimeoVideoURL() {
        let result = URLClassifier.classify("https://vimeo.com/1121011561")
        XCTAssertEqual(result, .vimeoVideo)
    }

    func testVimeoUnlistedURL() {
        let result = URLClassifier.classify("https://vimeo.com/1121011561/3df1265b59")
        XCTAssertEqual(result, .vimeoVideo)
    }

    func testVimeoShowcaseURL() {
        let result = URLClassifier.classify("https://vimeo.com/showcase/1234567")
        XCTAssertEqual(result, .vimeoShowcase)
    }

    func testUnknownURL() {
        let result = URLClassifier.classify("https://example.com/video")
        XCTAssertEqual(result, .unknown)
    }

    func testInvalidString() {
        let result = URLClassifier.classify("not a url")
        XCTAssertEqual(result, .invalid)
    }
}
