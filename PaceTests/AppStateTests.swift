import Carbon
import XCTest
@testable import Pace

final class AppStateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var mockLogin: MockLoginService!

    override func setUp() {
        super.setUp()
        suiteName = "test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        mockLogin = MockLoginService()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testFreshDefaults() {
        let state = AppState(defaults: defaults, loginService: mockLogin)
        XCTAssertTrue(state.isEnabled)
        XCTAssertTrue(state.trackpadSwipeEnabled)
        XCTAssertEqual(state.leftHotkey, .defaultLeft)
        XCTAssertEqual(state.rightHotkey, .defaultRight)
    }

    func testPersistenceRoundTrip() {
        let state = AppState(defaults: defaults, loginService: mockLogin)
        let newCombo = HotkeyCombination(keyCode: 0, modifiers: UInt32(cmdKey), displayKey: "X", keyEquivalent: "x")
        XCTAssertTrue(state.setHotkey(newCombo, for: .left))

        let state2 = AppState(defaults: defaults, loginService: mockLogin)
        XCTAssertEqual(state2.leftHotkey, newCombo)
    }

    func testDisabledPersists() {
        let state = AppState(defaults: defaults, loginService: mockLogin)
        state.isEnabled = false

        let state2 = AppState(defaults: defaults, loginService: mockLogin)
        XCTAssertFalse(state2.isEnabled)
    }

    func testSetHotkeyRejectsDuplicate() {
        let state = AppState(defaults: defaults, loginService: mockLogin)
        let result = state.setHotkey(state.rightHotkey, for: .left)
        XCTAssertFalse(result)
        XCTAssertEqual(state.leftHotkey, .defaultLeft) // unchanged
    }

    func testSetHotkeyAcceptsUnique() {
        let state = AppState(defaults: defaults, loginService: mockLogin)
        let newCombo = HotkeyCombination(keyCode: 0, modifiers: UInt32(cmdKey), displayKey: "Z", keyEquivalent: "z")
        XCTAssertTrue(state.setHotkey(newCombo, for: .left))
        XCTAssertEqual(state.leftHotkey, newCombo)
    }

    func testNormalizationOnLoad() {
        // Persist identical combos
        let combo = HotkeyCombination(keyCode: 42, modifiers: UInt32(cmdKey), displayKey: "Q", keyEquivalent: "q")
        let data = try! JSONEncoder().encode(combo)
        defaults.set(data, forKey: "pace.hotkey.left")
        defaults.set(data, forKey: "pace.hotkey.right")

        let state = AppState(defaults: defaults, loginService: mockLogin)
        XCTAssertNotEqual(state.leftHotkey, state.rightHotkey)
    }

    func testLoginSuccess() throws {
        let state = AppState(defaults: defaults, loginService: mockLogin)
        try state.setLaunchAtLogin(true)
        XCTAssertTrue(state.launchAtLoginMirror)
        XCTAssertTrue(mockLogin.isEnabled)
    }

    func testLoginFailureReverts() {
        let state = AppState(defaults: defaults, loginService: mockLogin)
        mockLogin.shouldFail = true
        XCTAssertThrowsError(try state.setLaunchAtLogin(true))
        XCTAssertFalse(state.launchAtLoginMirror)
    }

    func testResetViaSetHotkeyWhenCollision() {
        let state = AppState(defaults: defaults, loginService: mockLogin)
        // Set left to defaultRight's combo
        let newCombo = HotkeyCombination(keyCode: 99, modifiers: UInt32(cmdKey), displayKey: "Y", keyEquivalent: "y")
        _ = state.setHotkey(newCombo, for: .left)
        // Now try to set right to the same
        XCTAssertFalse(state.setHotkey(newCombo, for: .right))
    }
}
