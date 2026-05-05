import XCTest
@testable import VideoDownloader

final class YTDLPRunnerArgsTests: XCTestCase {

    private let cookiesKey = "useChromeCookies"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: cookiesKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: cookiesKey)
        super.tearDown()
    }

    private func makeOptions() -> YTDLPDownloadOptions {
        YTDLPDownloadOptions(
            url: "https://www.youtube.com/watch?v=test",
            format: .audioMP3,
            outputTemplate: "/tmp/%(title)s.%(ext)s",
            writeThumbnail: false,
            writeInfoJSON: false
        )
    }

    func testCookiesFlagAbsentByDefault() {
        let args = YTDLPRunner().buildArguments(makeOptions())
        XCTAssertFalse(args.contains("--cookies-from-browser"))
    }

    func testCookiesFlagAbsentWhenToggleOff() {
        UserDefaults.standard.set(false, forKey: cookiesKey)
        let args = YTDLPRunner().buildArguments(makeOptions())
        XCTAssertFalse(args.contains("--cookies-from-browser"))
    }

    func testCookiesFlagPresentWhenToggleOn() {
        UserDefaults.standard.set(true, forKey: cookiesKey)
        let args = YTDLPRunner().buildArguments(makeOptions())
        guard let i = args.firstIndex(of: "--cookies-from-browser") else {
            XCTFail("expected --cookies-from-browser flag in args: \(args)")
            return
        }
        XCTAssertEqual(args[args.index(after: i)], "chrome")
    }

    func testUrlIsAlwaysLastArg() {
        // sanity: cookies flag should not be appended after the URL
        UserDefaults.standard.set(true, forKey: cookiesKey)
        let args = YTDLPRunner().buildArguments(makeOptions())
        XCTAssertEqual(args.last, "https://www.youtube.com/watch?v=test")
    }
}
