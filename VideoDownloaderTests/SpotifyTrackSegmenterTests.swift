import XCTest
@testable import VideoDownloader

final class SpotifyTrackSegmenterTests: XCTestCase {
    func test_segmenter_emitsSegmentOnTrackChange() {
        var emitted: [SpotifySegmentResult] = []
        let seg = SpotifyTrackSegmenter { result in emitted.append(result) }

        seg.onPlaybackEvent(makeEvent(id: "A", state: .playing))
        seg.feed(samples: Array(repeating: Float(0.5), count: 4096), at: Date())

        seg.onPlaybackEvent(makeEvent(id: "B", state: .playing))
        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted[0].trackID, "A")
        XCTAssertEqual(emitted[0].samples.count, 4096)

        seg.feed(samples: Array(repeating: Float(0.25), count: 2048), at: Date())
        seg.onPlaybackEvent(makeEvent(id: "B", state: .stopped))
        XCTAssertEqual(emitted.count, 2)
        XCTAssertEqual(emitted[1].trackID, "B")
        XCTAssertEqual(emitted[1].samples.count, 2048)
    }

    func test_segmenter_dropsAudioBeforeFirstEvent() {
        var emitted: [SpotifySegmentResult] = []
        let seg = SpotifyTrackSegmenter { result in emitted.append(result) }

        seg.feed(samples: Array(repeating: Float(0.1), count: 1024), at: Date())
        seg.onPlaybackEvent(makeEvent(id: "A", state: .playing))
        seg.feed(samples: Array(repeating: Float(0.5), count: 1024), at: Date())
        seg.onPlaybackEvent(makeEvent(id: "B", state: .playing))

        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted[0].samples.count, 1024)
    }

    func test_flush_emitsTrailingSegment() {
        var emitted: [SpotifySegmentResult] = []
        let seg = SpotifyTrackSegmenter { result in emitted.append(result) }
        seg.onPlaybackEvent(makeEvent(id: "A", state: .playing))
        seg.feed(samples: Array(repeating: Float(0.5), count: 2048), at: Date())
        seg.flush()
        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted[0].trackID, "A")
    }

    private func makeEvent(id: String, state: SpotifyPlayerState) -> SpotifyNotificationPayload {
        SpotifyNotificationPayload(
            trackID: id, name: "n-\(id)", artist: "a", album: "b",
            durationMs: 180_000, playerState: state, timestamp: Date()
        )
    }
}
