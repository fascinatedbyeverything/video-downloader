import XCTest

// Swift 6 shim: allow XCTAssertEqual(Double?, Double, accuracy:) in tests
func XCTAssertEqual(
    _ expression1: Double?,
    _ expression2: Double,
    accuracy: Double,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let value = expression1 else {
        XCTFail("XCTAssertEqual failed: first expression is nil", file: file, line: line)
        return
    }
    XCTAssertEqual(value, expression2, accuracy: accuracy, message(), file: file, line: line)
}
