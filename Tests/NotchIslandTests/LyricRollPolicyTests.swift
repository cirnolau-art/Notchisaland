import XCTest
@testable import NotchIsland

final class LyricRollPolicyTests: XCTestCase {
    func testCurrentLineIsSharpOpaqueAndCentered() {
        let state = LyricRollPolicy.state(distance: 0, direction: .forward, step: 28)

        XCTAssertEqual(state.alpha, 1, accuracy: 0.001)
        XCTAssertEqual(state.blurRadius, 0, accuracy: 0.001)
        XCTAssertEqual(state.offset, 0, accuracy: 0.001)
    }

    func testFutureLinesRemainSharpAndFadeSlightlyAsTheyMoveAway() {
        let next = LyricRollPolicy.state(distance: 1, direction: .forward, step: 28)
        let farther = LyricRollPolicy.state(distance: 2, direction: .forward, step: 28)

        XCTAssertLessThan(next.alpha, 1)
        XCTAssertLessThan(farther.alpha, next.alpha)
        XCTAssertEqual(next.blurRadius, 0)
        XCTAssertEqual(farther.blurRadius, 0)
        XCTAssertGreaterThan(next.offset, 0)
        XCTAssertGreaterThan(farther.offset, next.offset)
    }

    func testPastLinesUseTheOppositeTravelDirection() {
        let future = LyricRollPolicy.state(distance: 1, direction: .forward, step: 28)
        let past = LyricRollPolicy.state(distance: 1, direction: .backward, step: 28)

        XCTAssertEqual(past.alpha, future.alpha, accuracy: 0.001)
        XCTAssertEqual(past.blurRadius, future.blurRadius, accuracy: 0.001)
        XCTAssertEqual(past.offset, -future.offset, accuracy: 0.001)
    }

    func testAppleMusicUsesShortContinuousTransitionAndEfficientSkipsIt() {
        XCTAssertEqual(LyricRollPolicy.transitionDuration(style: .appleMusic), 0.29, accuracy: 0.02)
        XCTAssertEqual(LyricRollPolicy.transitionDuration(style: .efficient), 0, accuracy: 0.001)
    }
}
