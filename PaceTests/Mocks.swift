import AppKit
@testable import Pace

final class MockEngine: GestureEngineProtocol {
    var isRunning = false
    var startCount = 0
    var stopCount = 0
    var onInvoluntaryTearDown: (() -> Void)?

    func start() { startCount += 1; isRunning = true }
    func stop() { stopCount += 1; isRunning = false }
    nonisolated func switchSpace(direction: SpaceDirection) {}
}

final class MockHotKeyManager: HotKeyManagerProtocol {
    var registrations: [SpaceDirection: HotkeyCombination] = [:]
    var unregisterAllCount = 0

    func register(direction: SpaceDirection, combination: HotkeyCombination, handler: @escaping () -> Void) {
        registrations[direction] = combination
    }
    func unregister(direction: SpaceDirection) {
        registrations.removeValue(forKey: direction)
    }
    func unregisterAll() {
        registrations.removeAll()
        unregisterAllCount += 1
    }
}

final class MockPermission: PermissionChecking {
    var granted: Bool
    var promptCount = 0

    init(granted: Bool) { self.granted = granted }

    func promptAccessibility() { promptCount += 1 }
    func isAccessibilityGranted() -> Bool { granted }
    func openAccessibilitySettings() {}
}

final class MockRecorder: EventRecorderProtocol {
    var shouldSucceed = true
    var isRecording = false
    var capturedOnKeyPress: ((NSEvent) -> Void)?
    var capturedOnMouseClick: (() -> Void)?
    var capturedOnInvoluntaryTearDown: (() -> Void)?

    func startRecording(
        onKeyPress: @escaping (NSEvent) -> Void,
        onMouseClick: @escaping () -> Void,
        onInvoluntaryTearDown: @escaping () -> Void
    ) -> Bool {
        guard shouldSucceed else { return false }
        isRecording = true
        capturedOnKeyPress = onKeyPress
        capturedOnMouseClick = onMouseClick
        capturedOnInvoluntaryTearDown = onInvoluntaryTearDown
        return true
    }

    func stopRecording() {
        isRecording = false
        capturedOnKeyPress = nil
        capturedOnMouseClick = nil
        capturedOnInvoluntaryTearDown = nil
    }

    func simulateKeyPress(_ event: NSEvent) { capturedOnKeyPress?(event) }
    func simulateMouseClick() { capturedOnMouseClick?() }
    func simulateInvoluntaryTearDown() { capturedOnInvoluntaryTearDown?() }
}

final class MockLoginService: LoginServiceProtocol {
    var isEnabled = false
    var shouldFail = false

    func register() throws {
        if shouldFail { throw NSError(domain: "test", code: 1) }
        isEnabled = true
    }

    func unregister() throws {
        if shouldFail { throw NSError(domain: "test", code: 1) }
        isEnabled = false
    }
}

final class MockActivationObserver: ActivationObserving {
    var onActivate: (() -> Void)?
    var onDeactivate: (() -> Void)?

    func observe(onActivate: @escaping () -> Void, onDeactivate: @escaping () -> Void) -> [Any] {
        self.onActivate = onActivate
        self.onDeactivate = onDeactivate
        return ["token"]
    }

    func removeObservers(_ tokens: [Any]) {
        onActivate = nil
        onDeactivate = nil
    }

    func simulateActivation() { onActivate?() }
    func simulateDeactivation() { onDeactivate?() }
}
