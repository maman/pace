import XCTest
@testable import Pace

final class GestureEngineTests: XCTestCase {

    // MARK: - processGestureEvent

    func testBeganSetsTracking() {
        var state = SwipeState()
        let action = processGestureEvent(eventType: 30, hidType: 23, motion: 1, phase: 1, progress: 0, velocityX: 0, state: &state)
        XCTAssertEqual(action, .suppress)
        XCTAssertTrue(state.swipeTracking)
        XCTAssertFalse(state.swipeFired)
    }

    func testChangedFiresOnProgress() {
        var state = SwipeState()
        state.swipeTracking = true
        let action = processGestureEvent(eventType: 30, hidType: 23, motion: 1, phase: 2, progress: 0.5, velocityX: 0, state: &state)
        XCTAssertEqual(action, .fireSwitch(true))
        XCTAssertTrue(state.swipeFired)
    }

    func testChangedSuppressesAfterFired() {
        var state = SwipeState()
        state.swipeTracking = true
        state.swipeFired = true
        let action = processGestureEvent(eventType: 30, hidType: 23, motion: 1, phase: 2, progress: 1.0, velocityX: 0, state: &state)
        XCTAssertEqual(action, .suppress)
    }

    func testEndedFiresOnVelocity() {
        var state = SwipeState()
        state.swipeTracking = true
        let action = processGestureEvent(eventType: 30, hidType: 23, motion: 1, phase: 4, progress: 0, velocityX: 200, state: &state)
        XCTAssertEqual(action, .fireSwitch(true))
        XCTAssertFalse(state.swipeTracking)
    }

    func testEndedLeftOnNegativeVelocity() {
        var state = SwipeState()
        state.swipeTracking = true
        let action = processGestureEvent(eventType: 30, hidType: 23, motion: 1, phase: 4, progress: 0, velocityX: -200, state: &state)
        XCTAssertEqual(action, .fireSwitch(false))
    }

    func testEndedSuppressesWhenAlreadyFired() {
        var state = SwipeState()
        state.swipeTracking = true
        state.swipeFired = true
        let action = processGestureEvent(eventType: 30, hidType: 23, motion: 1, phase: 4, progress: 0, velocityX: 0, state: &state)
        XCTAssertEqual(action, .suppress)
    }

    func testCancelledResetsState() {
        var state = SwipeState()
        state.swipeTracking = true
        state.swipeFired = true
        let action = processGestureEvent(eventType: 30, hidType: 23, motion: 1, phase: 8, progress: 0, velocityX: 0, state: &state)
        XCTAssertEqual(action, .suppress)
        XCTAssertFalse(state.swipeTracking)
        XCTAssertFalse(state.swipeFired)
    }

    func testPassthroughDecrement() {
        var state = SwipeState()
        state.passthrough = 2
        let action = processGestureEvent(eventType: 30, hidType: 23, motion: 1, phase: 1, progress: 0, velocityX: 0, state: &state)
        XCTAssertEqual(action, .passthrough)
        XCTAssertEqual(state.passthrough, 1)
    }

    func testCompanionSuppressed() {
        var state = SwipeState()
        state.swipeTracking = true
        let action = processGestureEvent(eventType: 29, hidType: 0, motion: 0, phase: 0, progress: 0, velocityX: 0, state: &state)
        XCTAssertEqual(action, .suppress)
    }

    func testNonDockEventPassthrough() {
        var state = SwipeState()
        let action = processGestureEvent(eventType: 30, hidType: 99, motion: 1, phase: 1, progress: 0, velocityX: 0, state: &state)
        XCTAssertEqual(action, .passthrough)
    }

    func testVerticalSwipePassthrough() {
        var state = SwipeState()
        let action = processGestureEvent(eventType: 30, hidType: 23, motion: 2, phase: 1, progress: 0, velocityX: 0, state: &state)
        XCTAssertEqual(action, .passthrough)
    }

    // MARK: - State Reset

    func testSwipeStateReset() {
        var state = SwipeState()
        state.swipeTracking = true
        state.swipeFired = true
        state.passthrough = 5
        state.reset()
        XCTAssertFalse(state.swipeTracking)
        XCTAssertFalse(state.swipeFired)
        XCTAssertEqual(state.passthrough, 0)
    }

    // MARK: - Switch Blocking

    func testSwitchBlockedNoPassthrough() {
        let engine = GestureEngine()
        engine.canSwitchFn = { _ in .blocked }
        engine.switchSpace(direction: .right)
        XCTAssertEqual(engine.state.passthrough, 0)
    }

    func testSwitchUnknownPostsAnyway() {
        let engine = GestureEngine()
        engine.canSwitchFn = { _ in .unknown }
        engine.switchSpace(direction: .left)
        XCTAssertEqual(engine.state.passthrough, 4)
    }

    // MARK: - Tap Recovery

    func testShouldReEnableOnTimeout() {
        XCTAssertTrue(shouldReEnableTap(type: .tapDisabledByTimeout))
    }

    func testShouldReEnableOnUserInput() {
        XCTAssertTrue(shouldReEnableTap(type: .tapDisabledByUserInput))
    }

    func testShouldNotReEnableOnKeyDown() {
        XCTAssertFalse(shouldReEnableTap(type: .keyDown))
    }
}
