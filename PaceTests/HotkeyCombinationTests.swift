import Carbon
import XCTest
@testable import Pace

final class HotkeyCombinationTests: XCTestCase {
    func testJSONRoundTrip() throws {
        let combo = HotkeyCombination.defaultLeft
        let data = try JSONEncoder().encode(combo)
        let decoded = try JSONDecoder().decode(HotkeyCombination.self, from: data)
        XCTAssertEqual(combo, decoded)
    }

    func testDisplayStringDefaultLeft() {
        XCTAssertEqual(HotkeyCombination.defaultLeft.displayString, "⌘⌥⌃←")
    }

    func testDisplayStringDefaultRight() {
        XCTAssertEqual(HotkeyCombination.defaultRight.displayString, "⌘⌥⌃→")
    }

    func testDisplayStringCmdShift() {
        let combo = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey),
            displayKey: "A",
            keyEquivalent: "a"
        )
        XCTAssertEqual(combo.displayString, "⌘⇧A")
    }

    func testIsValidEmpty() {
        let combo = HotkeyCombination(keyCode: 0, modifiers: 0, displayKey: "", keyEquivalent: "")
        XCTAssertFalse(combo.isValid)
    }

    func testParseArrowKey() {
        let result = HotkeyCombination.parse(
            keyCode: UInt32(kVK_LeftArrow),
            modifiers: UInt32(cmdKey),
            specialKey: .leftArrow,
            characters: nil
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.displayKey, "←")
    }

    func testParseFunctionKey() {
        let result = HotkeyCombination.parse(
            keyCode: UInt32(kVK_F5),
            modifiers: 0,
            specialKey: nil,
            characters: nil
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.displayKey, "F5")
    }

    func testParseReturnKey() {
        let result = HotkeyCombination.parse(
            keyCode: UInt32(kVK_Return),
            modifiers: 0,
            specialKey: nil,
            characters: nil
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.displayKey, "↩")
    }

    func testParseLetter() {
        let result = HotkeyCombination.parse(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(cmdKey),
            specialKey: nil,
            characters: "a"
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.displayKey, "A")
    }

    func testParseNilCharacters() {
        let result = HotkeyCombination.parse(
            keyCode: 999,
            modifiers: 0,
            specialKey: nil,
            characters: nil
        )
        XCTAssertNil(result)
    }

    func testParseEmptyCharacters() {
        let result = HotkeyCombination.parse(
            keyCode: 999,
            modifiers: 0,
            specialKey: nil,
            characters: ""
        )
        XCTAssertNil(result)
    }
}
