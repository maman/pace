import XCTest
@testable import Pace

final class SpaceQueryTests: XCTestCase {

    // MARK: - shouldBlockSwitch

    func testBlockLeftAtFirstSpace() {
        let info = SpaceInfo(currentIndex: 0, spaceCount: 3)
        XCTAssertTrue(shouldBlockSwitch(info: info, direction: .left))
    }

    func testBlockRightAtLastSpace() {
        let info = SpaceInfo(currentIndex: 2, spaceCount: 3)
        XCTAssertTrue(shouldBlockSwitch(info: info, direction: .right))
    }

    func testAllowMiddleSpace() {
        let info = SpaceInfo(currentIndex: 1, spaceCount: 3)
        XCTAssertFalse(shouldBlockSwitch(info: info, direction: .left))
        XCTAssertFalse(shouldBlockSwitch(info: info, direction: .right))
    }

    func testBlockZeroSpaces() {
        let info = SpaceInfo(currentIndex: 0, spaceCount: 0)
        XCTAssertTrue(shouldBlockSwitch(info: info, direction: .left))
        XCTAssertTrue(shouldBlockSwitch(info: info, direction: .right))
    }

    // MARK: - selectTargetDisplay

    func testSelectMatchingDisplay() {
        let id1 = "display-1" as CFString
        let id2 = "display-2" as CFString
        let d1 = ["Display Identifier": id1, "Spaces": [] as CFArray] as CFDictionary
        let d2 = ["Display Identifier": id2, "Spaces": [] as CFArray] as CFDictionary
        let displays = [d1, d2] as CFArray

        let result = selectTargetDisplay(from: displays, matching: id2)
        XCTAssertNotNil(result)
        let resultId = CFDictionaryGetValue(result!, Unmanaged.passUnretained(("Display Identifier" as CFString)).toOpaque())
        XCTAssertNotNil(resultId)
    }

    func testSelectFallbackToFirst() {
        let id1 = "display-1" as CFString
        let d1 = ["Display Identifier": id1] as CFDictionary
        let displays = [d1] as CFArray

        let result = selectTargetDisplay(from: displays, matching: "nonexistent" as CFString)
        XCTAssertNotNil(result) // Falls back to first
    }

    func testSelectNilIdentifier() {
        let d1 = ["Display Identifier": "d1" as CFString] as CFDictionary
        let displays = [d1] as CFArray

        let result = selectTargetDisplay(from: displays, matching: nil)
        XCTAssertNotNil(result) // Falls back to first
    }

    func testSelectEmptyArray() {
        let displays = [] as CFArray
        let result = selectTargetDisplay(from: displays, matching: nil)
        XCTAssertNil(result)
    }

    // MARK: - canSwitch with injected CGS

    func testCanSwitchSymbolsMissing() {
        let cgs = CGSFunctions() // All nil
        let result = canSwitch(direction: .right, cgs: cgs)
        XCTAssertEqual(result, .unknown)
    }

    // MARK: - extractSpaceInfo

    func testExtractValidThreeSpaces() {
        let spaces: [[String: Any]] = [
            ["id64": NSNumber(value: 100 as Int64)],
            ["id64": NSNumber(value: 200 as Int64)],
            ["id64": NSNumber(value: 300 as Int64)],
        ]
        let display: [String: Any] = [
            "Spaces": spaces as CFArray,
            "Current Space": ["id64": NSNumber(value: 200 as Int64)] as CFDictionary,
        ]

        let result = extractSpaceInfo(from: display as CFDictionary, activeSpace: 0, hasActiveSpace: false)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.currentIndex, 1)
        XCTAssertEqual(result?.spaceCount, 3)
    }

    func testExtractMissingSpacesKey() {
        let display: [String: Any] = ["Other": "value"]
        let result = extractSpaceInfo(from: display as CFDictionary, activeSpace: 0, hasActiveSpace: false)
        XCTAssertNil(result)
    }

    func testExtractEmptySpacesArray() {
        let display: [String: Any] = ["Spaces": [] as CFArray]
        let result = extractSpaceInfo(from: display as CFDictionary, activeSpace: 100, hasActiveSpace: true)
        XCTAssertNil(result)
    }

    func testExtractActiveSpaceNotFound() {
        let spaces: [[String: Any]] = [
            ["id64": NSNumber(value: 100 as Int64)],
        ]
        let display: [String: Any] = ["Spaces": spaces as CFArray]
        let result = extractSpaceInfo(from: display as CFDictionary, activeSpace: 999, hasActiveSpace: true)
        XCTAssertNil(result)
    }
}
