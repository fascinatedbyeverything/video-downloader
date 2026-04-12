import XCTest
@testable import VideoDownloader

final class DownloadFormatTests: XCTestCase {
    func testBestReturnsCorrectYTDLPFormatString() {
        XCTAssertEqual(DownloadFormat.best.ytdlpFormat, "bestvideo+bestaudio/best")
    }

    func testResolution1080pFormatString() {
        XCTAssertEqual(DownloadFormat.p1080.ytdlpFormat, "bestvideo[height<=1080]+bestaudio/best[height<=1080]")
    }

    func testAudioMP3FormatString() {
        XCTAssertEqual(DownloadFormat.audioMP3.ytdlpFormat, "bestaudio")
        XCTAssertTrue(DownloadFormat.audioMP3.isAudioOnly)
    }

    func testCustomFormatPreservesID() {
        let custom = DownloadFormat.custom(formatID: "137+140")
        XCTAssertEqual(custom.ytdlpFormat, "137+140")
    }

    func testDisplayNames() {
        XCTAssertEqual(DownloadFormat.best.displayName, "Best")
        XCTAssertEqual(DownloadFormat.audioMP3.displayName, "Audio — MP3 (320 kbps)")
    }
}
