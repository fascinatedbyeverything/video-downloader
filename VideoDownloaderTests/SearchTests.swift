import XCTest
@testable import VideoDownloader

final class SearchTests: XCTestCase {

    func testParseThreeResults() {
        let json = """
        {"id":"aaaaaaaaaaa","title":"Olympians","channel":"Fuck Buttons","duration":452,"view_count":1234567,"thumbnails":[{"url":"https://i.ytimg.com/vi/aaaaaaaaaaa/hq.jpg"}]}
        {"id":"bbbbbbbbbbb","title":"Surf Solar","uploader":"Fuck Buttons","duration":622,"view_count":90000,"thumbnail":"https://i.ytimg.com/vi/bbbbbbbbbbb/default.jpg"}
        {"id":"ccccccccccc","title":"Bright Tomorrow","duration":338}
        """
        let results = YTDLPSearch.parse(json)
        XCTAssertEqual(results.count, 3)

        XCTAssertEqual(results[0].id, "aaaaaaaaaaa")
        XCTAssertEqual(results[0].title, "Olympians")
        XCTAssertEqual(results[0].channel, "Fuck Buttons")
        XCTAssertEqual(results[0].durationSeconds, 452)
        XCTAssertEqual(results[0].viewCount, 1234567)
        XCTAssertEqual(results[0].thumbnailURL?.absoluteString, "https://i.ytimg.com/vi/aaaaaaaaaaa/hq.jpg")

        // Falls back to `uploader` when `channel` missing
        XCTAssertEqual(results[1].channel, "Fuck Buttons")
        // Falls back to top-level `thumbnail` when `thumbnails[]` missing
        XCTAssertEqual(results[1].thumbnailURL?.absoluteString, "https://i.ytimg.com/vi/bbbbbbbbbbb/default.jpg")

        // Missing optional fields → nil
        XCTAssertNil(results[2].channel)
        XCTAssertNil(results[2].viewCount)
        XCTAssertNil(results[2].thumbnailURL)
    }

    func testSkipsMalformedLines() {
        let json = """
        not json at all
        {"id":"aaaaaaaaaaa","title":"First"}
        {"id":"bbbbb"
        {"id":"ccccccccccc","title":"Third"}
        """
        let results = YTDLPSearch.parse(json)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].id, "aaaaaaaaaaa")
        XCTAssertEqual(results[1].id, "ccccccccccc")
    }

    func testSkipsEntriesWithMissingID() {
        let json = """
        {"title":"No ID"}
        {"id":"","title":"Empty ID"}
        {"id":"aaaaaaaaaaa","title":"Valid"}
        """
        let results = YTDLPSearch.parse(json)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "aaaaaaaaaaa")
    }

    func testTitleFallsBackToID() {
        let json = """
        {"id":"aaaaaaaaaaa"}
        """
        let results = YTDLPSearch.parse(json)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "aaaaaaaaaaa")
    }

    func testVideoURLConstruction() {
        let result = SearchResult(
            id: "dQw4w9WgXcQ",
            title: "Never Gonna Give You Up",
            channel: "Rick Astley",
            durationSeconds: 213,
            thumbnailURL: nil,
            viewCount: nil
        )
        XCTAssertEqual(result.videoURL, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(YTDLPSearch.parse("").count, 0)
        XCTAssertEqual(YTDLPSearch.parse("\n\n\n").count, 0)
    }

    func testPrefersLastThumbnail() {
        // yt-dlp sorts thumbnails low-res → high-res; we want the last (highest-res).
        let json = """
        {"id":"aaaaaaaaaaa","title":"T","thumbnails":[{"url":"https://low.jpg"},{"url":"https://mid.jpg"},{"url":"https://high.jpg"}]}
        """
        let results = YTDLPSearch.parse(json)
        XCTAssertEqual(results[0].thumbnailURL?.absoluteString, "https://high.jpg")
    }
}
