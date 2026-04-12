import ApplicationServices
import CoreGraphics
import Darwin

// MARK: - Types

struct SpaceInfo: Equatable {
    var currentIndex: UInt32 = 0
    var spaceCount: UInt32 = 0
}

enum SwitchCheck {
    case allowed
    case blocked
    case unknown
}

// MARK: - Injected CGS Function Table

struct CGSFunctions {
    var mainConnectionID: (() -> Int32)? = nil
    var getActiveSpace: ((Int32) -> UInt64)? = nil
    var copyManagedDisplaySpaces: ((Int32, CFString?) -> CFArray?)? = nil
    var copyActiveMenuBarDisplayIdentifier: ((Int32) -> CFString?)? = nil

    var isAvailable: Bool {
        mainConnectionID != nil && getActiveSpace != nil && copyManagedDisplaySpaces != nil
    }

    static let live: CGSFunctions = {
        let h = dlopen(nil, RTLD_NOW)
        func resolve<T>(_ name: String) -> T? {
            guard let sym = dlsym(h, name) else { return nil }
            return unsafeBitCast(sym, to: T.self)
        }
        return CGSFunctions(
            mainConnectionID: resolve("CGSMainConnectionID") as (@convention(c) () -> Int32)?,
            getActiveSpace: resolve("CGSGetActiveSpace") as (@convention(c) (Int32) -> UInt64)?,
            copyManagedDisplaySpaces: resolve("CGSCopyManagedDisplaySpaces") as (@convention(c) (Int32, CFString?) -> CFArray?)?,
            copyActiveMenuBarDisplayIdentifier: resolve("CGSCopyActiveMenuBarDisplayIdentifier") as (@convention(c) (Int32) -> CFString?)?
        )
    }()
}

// MARK: - Display Locating

protocol DisplayLocating {
    func cursorDisplayIdentifier() -> CFString?
}

struct LiveDisplayLocator: DisplayLocating {
    func cursorDisplayIdentifier() -> CFString? {
        guard let tempEvent = CGEvent(source: nil) else { return nil }
        let cursorLocation = tempEvent.location
        var cursorDisplay: CGDirectDisplayID = 0
        var displayCount: UInt32 = 0
        guard CGGetDisplaysWithPoint(cursorLocation, 1, &cursorDisplay, &displayCount) == .success,
              displayCount > 0
        else { return nil }
        guard let displayUUID = CGDisplayCreateUUIDFromDisplayID(cursorDisplay)?.takeRetainedValue() else { return nil }
        let identifier = CFUUIDCreateString(nil, displayUUID) as CFString?
        return identifier
    }
}

// MARK: - Pure Query Functions

func extractSpaceInfo(
    from displayDict: CFDictionary,
    activeSpace: UInt64,
    hasActiveSpace: Bool
) -> SpaceInfo? {
    let dict = displayDict as NSDictionary

    // Read per-display active space from "Current Space"/"id64"
    var displayActiveSpace: UInt64 = 0
    if let currentSpaceDict = dict["Current Space"] as? NSDictionary,
       let idNumber = currentSpaceDict["id64"] as? NSNumber {
        displayActiveSpace = idNumber.uint64Value
    }

    let targetActiveSpace = displayActiveSpace != 0 ? displayActiveSpace : activeSpace
    let hasTargetActiveSpace = displayActiveSpace != 0 || hasActiveSpace

    guard let spacesArray = dict["Spaces"] as? [NSDictionary] else {
        return nil
    }

    var totalSpaces: UInt32 = 0
    var activeIndex: UInt32 = 0
    var foundActive = false

    for spaceDict in spacesArray {
        guard let idNumber = spaceDict["id64"] as? NSNumber else { continue }
        let candidate = idNumber.uint64Value
        if !foundActive && hasTargetActiveSpace && candidate == targetActiveSpace {
            activeIndex = totalSpaces
            foundActive = true
        }
        totalSpaces += 1
    }

    if totalSpaces == 0 || (hasTargetActiveSpace && !foundActive) {
        return nil
    }

    return SpaceInfo(
        currentIndex: foundActive ? activeIndex : 0,
        spaceCount: totalSpaces
    )
}

func selectTargetDisplay(from displays: CFArray, matching identifier: CFString?) -> CFDictionary? {
    let array = displays as NSArray
    guard array.count > 0 else { return nil }

    var fallback: CFDictionary?
    for item in array {
        guard let displayDict = item as? NSDictionary else { continue }

        if fallback == nil {
            fallback = displayDict as CFDictionary
        }

        if let identifier,
           let displayId = displayDict["Display Identifier"] as? String,
           displayId == identifier as String {
            return displayDict as CFDictionary
        }
    }

    return fallback
}

func loadSpaceInfo(
    useCursorDisplay: Bool,
    cgs: CGSFunctions = .live,
    displayLocator: DisplayLocating = LiveDisplayLocator()
) -> SpaceInfo? {
    guard cgs.isAvailable else { return nil }

    let cid = cgs.mainConnectionID!()
    guard cid != 0 else { return nil }

    let activeSpace = cgs.getActiveSpace!(cid)
    guard activeSpace != 0 else { return nil }

    // Get display identifier
    var displayIdentifier: CFString?
    if useCursorDisplay {
        displayIdentifier = displayLocator.cursorDisplayIdentifier()
    } else {
        displayIdentifier = cgs.copyActiveMenuBarDisplayIdentifier?(cid)
    }

    // Get managed display spaces
    var displays = cgs.copyManagedDisplaySpaces!(cid, displayIdentifier)
    if displays == nil && displayIdentifier != nil {
        displays = cgs.copyManagedDisplaySpaces!(cid, nil)
    }
    guard let displays else { return nil }

    guard let targetDisplay = selectTargetDisplay(from: displays, matching: displayIdentifier) else {
        return nil
    }

    return extractSpaceInfo(from: targetDisplay, activeSpace: activeSpace, hasActiveSpace: true)
}

func shouldBlockSwitch(info: SpaceInfo, direction: SpaceDirection) -> Bool {
    if info.spaceCount == 0 { return true }
    switch direction {
    case .left: return info.currentIndex == 0
    case .right: return info.currentIndex + 1 >= info.spaceCount
    }
}

func canSwitch(
    direction: SpaceDirection,
    cgs: CGSFunctions = .live,
    displayLocator: DisplayLocating = LiveDisplayLocator()
) -> SwitchCheck {
    guard cgs.isAvailable else { return .unknown }
    guard let info = loadSpaceInfo(useCursorDisplay: true, cgs: cgs, displayLocator: displayLocator) else {
        return .unknown
    }
    return shouldBlockSwitch(info: info, direction: direction) ? .blocked : .allowed
}
