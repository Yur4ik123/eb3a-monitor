import XCTest
@testable import EB3AKit

final class BackoffTests: XCTestCase {
    func testBackoffSequence() {
        XCTAssertEqual((0..<8).map(Backoff.delay(attempt:)), [1, 2, 4, 8, 16, 30, 30, 30])
    }
}
