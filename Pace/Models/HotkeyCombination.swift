import AppKit
import Carbon

enum SpaceDirection: Hashable {
    case left, right
}

struct HotkeyCombination: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32
    var displayKey: String
    var keyEquivalent: String

    var displayString: String {
        Self.symbols(for: modifiers) + displayKey
    }

    var isValid: Bool {
        !displayKey.isEmpty
    }

    static let defaultLeft = HotkeyCombination(
        keyCode: UInt32(kVK_LeftArrow),
        modifiers: UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey),
        displayKey: "←",
        keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
    )

    static let defaultRight = HotkeyCombination(
        keyCode: UInt32(kVK_RightArrow),
        modifiers: UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey),
        displayKey: "→",
        keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
    )

    // MARK: - Pure Parse Helpers

    static func arrowSymbol(for key: NSEvent.SpecialKey) -> String? {
        switch key {
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        default: return nil
        }
    }

    static func specialKeyInfo(for keyCode: Int) -> (displayKey: String, keyEquivalent: String)? {
        switch keyCode {
        case kVK_Return:
            return ("↩", String(Character(UnicodeScalar(NSCarriageReturnCharacter)!)))
        case kVK_ANSI_KeypadEnter:
            return ("⌅", String(Character(UnicodeScalar(NSEnterCharacter)!)))
        case kVK_Tab:
            return ("⇥", String(Character(UnicodeScalar(NSTabCharacter)!)))
        case kVK_Delete:
            return ("⌫", String(Character(UnicodeScalar(NSBackspaceCharacter)!)))
        case kVK_ForwardDelete:
            return ("⌦", String(Character(UnicodeScalar(NSDeleteCharacter)!)))
        case kVK_Space:
            return ("Space", " ")
        case kVK_F1:
            return ("F1", String(Character(UnicodeScalar(NSF1FunctionKey)!)))
        case kVK_F2:
            return ("F2", String(Character(UnicodeScalar(NSF2FunctionKey)!)))
        case kVK_F3:
            return ("F3", String(Character(UnicodeScalar(NSF3FunctionKey)!)))
        case kVK_F4:
            return ("F4", String(Character(UnicodeScalar(NSF4FunctionKey)!)))
        case kVK_F5:
            return ("F5", String(Character(UnicodeScalar(NSF5FunctionKey)!)))
        case kVK_F6:
            return ("F6", String(Character(UnicodeScalar(NSF6FunctionKey)!)))
        case kVK_F7:
            return ("F7", String(Character(UnicodeScalar(NSF7FunctionKey)!)))
        case kVK_F8:
            return ("F8", String(Character(UnicodeScalar(NSF8FunctionKey)!)))
        case kVK_F9:
            return ("F9", String(Character(UnicodeScalar(NSF9FunctionKey)!)))
        case kVK_F10:
            return ("F10", String(Character(UnicodeScalar(NSF10FunctionKey)!)))
        case kVK_F11:
            return ("F11", String(Character(UnicodeScalar(NSF11FunctionKey)!)))
        case kVK_F12:
            return ("F12", String(Character(UnicodeScalar(NSF12FunctionKey)!)))
        case kVK_Home:
            return ("↖", String(Character(UnicodeScalar(NSHomeFunctionKey)!)))
        case kVK_End:
            return ("↘", String(Character(UnicodeScalar(NSEndFunctionKey)!)))
        case kVK_PageUp:
            return ("⇞", String(Character(UnicodeScalar(NSPageUpFunctionKey)!)))
        case kVK_PageDown:
            return ("⇟", String(Character(UnicodeScalar(NSPageDownFunctionKey)!)))
        default:
            return nil
        }
    }

    static func parse(
        keyCode: UInt32,
        modifiers: UInt32,
        specialKey: NSEvent.SpecialKey?,
        characters: String?
    ) -> HotkeyCombination? {
        if let sk = specialKey, let sym = arrowSymbol(for: sk) {
            return HotkeyCombination(
                keyCode: keyCode, modifiers: modifiers,
                displayKey: sym, keyEquivalent: arrowKeyEquivalent(sk)
            )
        }
        if let (dk, ke) = specialKeyInfo(for: Int(keyCode)) {
            return HotkeyCombination(
                keyCode: keyCode, modifiers: modifiers,
                displayKey: dk, keyEquivalent: ke
            )
        }
        guard let chars = characters, let first = chars.first,
              first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol
        else {
            return nil
        }
        return HotkeyCombination(
            keyCode: keyCode, modifiers: modifiers,
            displayKey: String(first).uppercased(),
            keyEquivalent: String(first).lowercased()
        )
    }

    static func from(event: NSEvent) -> HotkeyCombination? {
        parse(
            keyCode: UInt32(event.keyCode),
            modifiers: event.modifierFlags.carbonMask,
            specialKey: event.specialKey,
            characters: event.charactersIgnoringModifiers
        )
    }

    // MARK: - Private Helpers

    // Order: ⌘⌥⌃⇧ (matches ref HotkeyConfiguration.swift:227-234)
    private static func symbols(for modifiers: UInt32) -> String {
        var r = ""
        if modifiers & UInt32(cmdKey) != 0 { r += "⌘" }
        if modifiers & UInt32(optionKey) != 0 { r += "⌥" }
        if modifiers & UInt32(controlKey) != 0 { r += "⌃" }
        if modifiers & UInt32(shiftKey) != 0 { r += "⇧" }
        return r
    }

    private static func arrowKeyEquivalent(_ key: NSEvent.SpecialKey) -> String {
        switch key {
        case .leftArrow: return String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        case .rightArrow: return String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        case .upArrow: return String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        case .downArrow: return String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        default: return ""
        }
    }
}

extension NSEvent.ModifierFlags {
    var carbonMask: UInt32 {
        var mask: UInt32 = 0
        if contains(.command) { mask |= UInt32(cmdKey) }
        if contains(.option) { mask |= UInt32(optionKey) }
        if contains(.control) { mask |= UInt32(controlKey) }
        if contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }
}
