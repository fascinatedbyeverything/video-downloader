import XCTest
@testable import VideoDownloader

final class FormatProbeTests: XCTestCase {
    let sample = """
    [info] Available formats for abc123:
    ID  EXT   RESOLUTION FPS │  FILESIZE   TBR PROTO │ VCODEC           VBR ACODEC      ABR ASR  MORE INFO
    ───────────────────────────────────────────────────────────────────────────────────────────────────
    139 m4a   audio only     │    2.32MiB   49k https │ audio only           mp4a.40.5   49k 22k  low, m4a_dash
    251 webm  audio only     │    5.24MiB  128k https │ audio only           opus       128k 48k  medium, webm_dash
    137 mp4   1920x1080   30 │  110.20MiB 2500k https │ avc1.640028    2500k video only              1080p
    399 mp4   1920x1080   30 │   98.84MiB 2237k https │ av01.0.08M.08  2237k video only              1080p
    """

    func testParsesAudioOnlyRows() throws {
        let formats = FormatProbe.parse(sample)
        let audio = formats.filter { $0.resolution == "audio only" }
        XCTAssertEqual(audio.count, 2)
        XCTAssertTrue(audio.contains(where: { $0.formatID == "251" && $0.container == "webm" }))
    }

    func testParsesVideoRows() throws {
        let formats = FormatProbe.parse(sample)
        let videos = formats.filter { $0.resolution.contains("x") }
        XCTAssertEqual(videos.count, 2)
        XCTAssertTrue(videos.contains(where: { $0.formatID == "399" }))
    }

    func testExtractsFileSizeWhenPresent() throws {
        let formats = FormatProbe.parse(sample)
        let f137 = formats.first { $0.formatID == "137" }
        XCTAssertNotNil(f137?.fileSize)
        XCTAssertTrue(f137!.fileSize!.contains("MiB"))
    }
}
