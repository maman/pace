import Carbon
import XCTest
@testable import Pace

final class PaceCoordinatorTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "coord-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeState(isEnabled: Bool = true, trackpad: Bool = true) -> AppState {
        let state = AppState(defaults: defaults, loginService: MockLoginService())
        state.isEnabled = isEnabled
        state.trackpadSwipeEnabled = trackpad
        return state
    }

    private func makeCoordinator(
        granted: Bool = true
    ) -> (PaceCoordinator, MockEngine, MockHotKeyManager, MockPermission, MockRecorder, MockActivationObserver) {
        let e = MockEngine()
        let h = MockHotKeyManager()
        let p = MockPermission(granted: granted)
        let r = MockRecorder()
        let a = MockActivationObserver()
        let c = PaceCoordinator(engine: e, hotkeyManager: h, permissionChecker: p, recorder: r, activationObserver: a)
        return (c, e, h, p, r, a)
    }

    // MARK: - Launch States

    func testDisabledLaunch() {
        let (coord, engine, hk, perm, _, _) = makeCoordinator()
        let state = makeState(isEnabled: false)
        coord.start(appState: state)

        XCTAssertEqual(engine.startCount, 0)
        XCTAssertTrue(hk.registrations.isEmpty)
        XCTAssertEqual(perm.promptCount, 0)
    }

    func testEnabledLaunchWithAX() {
        let (coord, engine, hk, _, _, _) = makeCoordinator(granted: true)
        let state = makeState()
        coord.start(appState: state)

        XCTAssertEqual(engine.startCount, 1)
        XCTAssertEqual(hk.registrations.count, 2)
    }

    func testEnabledLaunchAXDenied() {
        let (coord, engine, hk, perm, _, _) = makeCoordinator(granted: false)
        let state = makeState()
        coord.start(appState: state)

        XCTAssertEqual(engine.startCount, 0) // No AX
        XCTAssertEqual(hk.registrations.count, 2) // Hotkeys still work
        XCTAssertGreaterThan(perm.promptCount, 0)
    }

    func testTrackpadOffAtLaunch() {
        let (coord, engine, hk, perm, _, _) = makeCoordinator(granted: true)
        let state = makeState(trackpad: false)
        coord.start(appState: state)

        XCTAssertEqual(engine.startCount, 0) // No engine when trackpad off
        XCTAssertEqual(hk.registrations.count, 2) // Hotkeys registered
        XCTAssertEqual(perm.promptCount, 0) // No AX prompt
    }

    // MARK: - Observation

    func testObservationDisable() async {
        let (coord, engine, hk, _, _, _) = makeCoordinator(granted: true)
        let state = makeState()
        coord.start(appState: state)
        XCTAssertTrue(engine.isRunning)

        state.isEnabled = false
        await Task.yield()

        XCTAssertGreaterThan(engine.stopCount, 0)
        XCTAssertGreaterThan(hk.unregisterAllCount, 0)
    }

    func testObservationHotkeyChange() async {
        let (coord, _, hk, _, _, _) = makeCoordinator(granted: true)
        let state = makeState()
        coord.start(appState: state)

        let newCombo = HotkeyCombination(keyCode: 99, modifiers: UInt32(cmdKey), displayKey: "Z", keyEquivalent: "z")
        _ = state.setHotkey(newCombo, for: .left)
        await Task.yield()

        XCTAssertEqual(hk.registrations[.left], newCombo)
    }

    func testPostStopSafety() async {
        let (coord, engine, hk, _, _, _) = makeCoordinator(granted: true)
        let state = makeState()
        coord.start(appState: state)
        let stopEngineCount = engine.stopCount
        let stopHKCount = hk.unregisterAllCount

        coord.stop()
        state.isEnabled = false
        await Task.yield()

        // Should not have extra calls after stop
        XCTAssertEqual(engine.stopCount, stopEngineCount + 1) // Only the stop() call
        XCTAssertEqual(hk.unregisterAllCount, stopHKCount + 1) // Only the stop() call
    }

    // MARK: - Retry AX

    func testRetryAccessibility() {
        let (coord, engine, _, perm, _, _) = makeCoordinator(granted: false)
        let state = makeState()
        coord.start(appState: state)
        XCTAssertEqual(engine.startCount, 0)
        XCTAssertFalse(coord.accessibilityGranted)

        perm.granted = true
        coord.retryAccessibility()

        XCTAssertTrue(coord.accessibilityGranted)
        XCTAssertEqual(engine.startCount, 1)
    }

    // MARK: - Recording

    func testRecordingSuccess() {
        let (coord, _, hk, _, recorder, _) = makeCoordinator(granted: true)
        let state = makeState()
        coord.start(appState: state)
        let prevUnreg = hk.unregisterAllCount

        let result = coord.beginRecording(for: .left)
        XCTAssertTrue(result)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(coord.recordingDirection, .left)
        XCTAssertEqual(hk.unregisterAllCount, prevUnreg + 1)
    }

    func testRecordingFailure() {
        let (coord, _, hk, _, recorder, _) = makeCoordinator(granted: true)
        let state = makeState()
        coord.start(appState: state)
        recorder.shouldSucceed = false
        let prevUnreg = hk.unregisterAllCount

        let result = coord.beginRecording(for: .left)
        XCTAssertFalse(result)
        XCTAssertEqual(hk.unregisterAllCount, prevUnreg) // Not unregistered
    }

    func testRecordingToggle() {
        let (coord, _, _, _, _, _) = makeCoordinator(granted: true)
        let state = makeState()
        coord.start(appState: state)

        _ = coord.beginRecording(for: .left)
        XCTAssertEqual(coord.recordingDirection, .left)

        // Second call for same direction cancels
        _ = coord.beginRecording(for: .left)
        XCTAssertNil(coord.recordingDirection)
    }

    func testRecordingWhileDisabled() {
        let (coord, _, hk, _, _, _) = makeCoordinator(granted: true)
        let state = makeState(isEnabled: false)
        coord.start(appState: state)

        // Recording allowed even when disabled
        let result = coord.beginRecording(for: .left)
        XCTAssertTrue(result)

        // After cancel, hotkeys stay unregistered since isEnabled=false
        coord.cancelRecording()
        XCTAssertTrue(hk.registrations.isEmpty)
    }

    func testStateChangeDuringRecording() async {
        let (coord, _, hk, _, _, _) = makeCoordinator(granted: true)
        let state = makeState()
        coord.start(appState: state)

        _ = coord.beginRecording(for: .left)
        hk.unregisterAllCount = 0

        // State change during recording — syncHotkeys should skip
        state.isEnabled = false
        await Task.yield()

        // Hotkeys were not re-registered (syncHotkeys skips while recording)
        // The unregisterAll from the isEnabled observation may fire but syncHotkeys bails
        XCTAssertNotNil(coord.recordingDirection) // Still recording
    }

    func testStopWhileRecording() {
        let (coord, _, _, _, recorder, _) = makeCoordinator(granted: true)
        let state = makeState()
        coord.start(appState: state)
        _ = coord.beginRecording(for: .left)

        coord.stop()
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(coord.recordingDirection)
    }

    // MARK: - App Activation

    func testAppActivationRefresh() {
        let (coord, _, _, perm, _, actObs) = makeCoordinator(granted: false)
        let state = makeState()
        coord.start(appState: state)
        XCTAssertFalse(coord.accessibilityGranted)

        perm.granted = true
        actObs.simulateActivation()
        XCTAssertTrue(coord.accessibilityGranted)
    }

    func testAppDeactivationCancelsRecording() {
        let (coord, _, _, _, recorder, actObs) = makeCoordinator(granted: true)
        let state = makeState()
        coord.start(appState: state)
        _ = coord.beginRecording(for: .right)
        XCTAssertTrue(recorder.isRecording)

        actObs.simulateDeactivation()
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(coord.recordingDirection)
    }
}
