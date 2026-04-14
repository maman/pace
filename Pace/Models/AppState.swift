import Foundation
import Observation
import ServiceManagement

protocol LoginServiceProtocol {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

struct SMLoginService: LoginServiceProtocol {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

@Observable
final class AppState {
    private let defaults: UserDefaults
    private let loginService: LoginServiceProtocol

    init(defaults: UserDefaults = .standard, loginService: LoginServiceProtocol = SMLoginService()) {
        self.defaults = defaults
        self.loginService = loginService

        isEnabled = defaults.object(forKey: "pace.enabled") as? Bool ?? true

        let loadedLeft = Self.loadHotkey(defaults, "pace.hotkey.left")
        let loadedRight = Self.loadHotkey(defaults, "pace.hotkey.right")

        // Normalization: fix invalid or colliding persisted values
        var left = (loadedLeft?.isValid == true) ? loadedLeft! : .defaultLeft
        var right = (loadedRight?.isValid == true) ? loadedRight! : .defaultRight
        if left == right {
            right = .defaultRight
            if left == right { left = .defaultLeft }
        }
        leftHotkey = left
        rightHotkey = right

        if leftHotkey != loadedLeft { Self.saveHotkey(defaults, leftHotkey, "pace.hotkey.left") }
        if rightHotkey != loadedRight { Self.saveHotkey(defaults, rightHotkey, "pace.hotkey.right") }

        launchAtLoginMirror = loginService.isEnabled
    }

    // MARK: - Persisted Properties

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: "pace.enabled") }
    }

    private(set) var leftHotkey: HotkeyCombination {
        didSet { Self.saveHotkey(defaults, leftHotkey, "pace.hotkey.left") }
    }

    private(set) var rightHotkey: HotkeyCombination {
        didSet { Self.saveHotkey(defaults, rightHotkey, "pace.hotkey.right") }
    }

    // MARK: - Launch at Login

    var launchAtLoginMirror: Bool = false

    func setLaunchAtLogin(_ enabled: Bool) throws {
        do {
            if enabled {
                try loginService.register()
            } else {
                try loginService.unregister()
            }
        } catch {
            launchAtLoginMirror = loginService.isEnabled
            throw error
        }
        launchAtLoginMirror = loginService.isEnabled
    }

    // MARK: - Hotkey Write API

    @discardableResult
    func setHotkey(_ combo: HotkeyCombination, for direction: SpaceDirection) -> Bool {
        guard !isDuplicateShortcut(combo, for: direction) else { return false }
        switch direction {
        case .left: leftHotkey = combo
        case .right: rightHotkey = combo
        }
        return true
    }

    func isDuplicateShortcut(_ combo: HotkeyCombination, for direction: SpaceDirection) -> Bool {
        switch direction {
        case .left: return combo == rightHotkey
        case .right: return combo == leftHotkey
        }
    }

    // MARK: - JSON Persistence

    private static func loadHotkey(_ d: UserDefaults, _ key: String) -> HotkeyCombination? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeyCombination.self, from: data)
    }

    private static func saveHotkey(_ d: UserDefaults, _ h: HotkeyCombination, _ key: String) {
        if let data = try? JSONEncoder().encode(h) {
            d.set(data, forKey: key)
        }
    }
}
