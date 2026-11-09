import XCTest
@testable import AIUsageFeature

final class PullRefreshInteractionTests: XCTestCase {
    func testOnlyReleaseBeyondThresholdRequestsOnce() {
        var value = PullRefreshInteraction()
        value.begin(); value.observe(distance: 79)
        XCTAssertFalse(value.release(enabled: true))
        value.begin(); value.observe(distance: 100)
        XCTAssertTrue(value.release(enabled: true))
        XCTAssertFalse(value.release(enabled: true))
        value.finish(); XCTAssertFalse(value.refreshing)
    }
    func testReverseGestureAndDisabledConnectionDoNotRequest() {
        var value = PullRefreshInteraction()
        value.observe(distance: 100); value.observe(distance: 20)
        XCTAssertFalse(value.release(enabled: true))
        value.observe(distance: 100)
        XCTAssertFalse(value.release(enabled: false))
        XCTAssertEqual(value.distance, 0)
    }
    func testNonFiniteAndExcessiveGeometryAreBounded() {
        var value = PullRefreshInteraction()
        value.observe(distance: .nan); XCTAssertEqual(value.progress, 0)
        value.observe(distance: -20); XCTAssertEqual(value.progress, 0)
        value.observe(distance: 500); XCTAssertEqual(value.progress, 1)
    }
}
