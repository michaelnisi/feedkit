import XCTest
@testable import FeedKit

final class FeedKitTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(FeedKit().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
