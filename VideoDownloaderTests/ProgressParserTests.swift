import XCTest
@testable import VideoDownloader

final class ProgressParserTests: XCTestCase {
    func testParseStandardDownloadLine() {
        let line = "[download]  45.2% of   98.84MiB at    4.90MiB/s ETA 01:45"
        let progress = ProgressParser.parse(line)
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress?.percent, 45.2, accuracy: 0.01)
        XCTAssertEqual(progress?.speedDescription, "4.90MiB/s")
        XCTAssertEqual(progress?.etaDescription, "01:45")
    }

    func testParseUnknownSpeed() {
        let line = "[download]   9.8% of   98.84MiB at  Unknown B/s ETA Unknown"
        let progress = ProgressParser.parse(line)
        XCTAssertEqual(progress?.percent, 9.8, accuracy: 0.01)
        XCTAssertNil(progress?.speedDescription)
        XCTAssertNil(progress?.etaDescription)
    }

    func testParseCompleteLine() {
        let line = "[download] 100% of   98.84MiB in 00:00:06 at 16.00MiB/s"
        let progress = ProgressParser.parse(line)
        XCTAssertEqual(progress?.percent, 100.0, accuracy: 0.01)
    }

    func testIgnoresUnrelatedLines() {
        XCTAssertNil(ProgressParser.parse("[youtube] Extracting URL: https://..."))
        XCTAssertNil(ProgressParser.parse("[Merger] Merging formats into ..."))
    }
}
