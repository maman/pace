import AppKit
import Carbon
import Observation

@Observable @MainActor
final class PaceCoordinator {
    private let engine: GestureEngineProtocol
    private let hotkeyManager: HotKeyManagerProtocol
    private let permissionChecker: PermissionChecking
    private let recorder: EventRecorderProtocol
    private let activationObserver: ActivationObserving
    private var appState: AppState?
    private var isStarted = false
    private var previousNeedsEngine = false
    private var activationTokens: [Any] = []

    private(set) var recordingDirection: SpaceDirection?
    private(set) var accessibilityGranted = false
    private var watchdogTimer: Timer?

    #if DEBUG
    private var debugSimulateAXLoss = false
    #endif

    static let watchdogInterval: TimeInterval = 1.0

    var needsAccessibilityWarning: Bool {
        (appState?.isEnabled ?? false) && !accessibilityGranted
    }

    init(
        engine: (any GestureEngineProtocol)? = nil,
        hotkeyManager: (any HotKeyManagerProtocol)? = nil,
        permissionChecker: (any PermissionChecking)? = nil,
        recorder: (any EventRecorderProtocol)? = nil,
        activationObserver: (any ActivationObserving)? = nil
    ) {
        self.engine = engine ?? GestureEngine.shared
        self.hotkeyManager = hotkeyManager ?? HotKeyManager.shared
        self.permissionChecker = permissionChecker ?? PermissionHelper()
        self.recorder = recorder ?? GlobalEventTapRecorder.shared
        self.activationObserver = activationObserver ?? WorkspaceActivationObserver()
    }

    private var needsEngine: Bool {
        appState?.isEnabled ?? false
    }

    // MARK: - Lifecycle

    func start(appState: AppState) {
        self.appState = appState
        isStarted = true
        previousNeedsEngine = needsEngine
        refreshAccessibility()
        engine.onInvoluntaryTearDown = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                self.handleEngineTearDown()
            }
        }
        if needsEngine {
            permissionChecker.promptAccessibility()
            refreshAccessibility()
        }
        syncHotkeys()
        syncEngine()
        observeStateChanges()
        activationTokens = activationObserver.observe(
            onActivate: { [weak self] in
                self?.refreshAccessibility()
                self?.syncEngine()
            },
            onDeactivate: { [weak self] in
                if self?.recordingDirection != nil {
                    self?.cancelRecording()
                }
            }
        )
        startWatchdog()
    }

    func stop() {
        isStarted = false
        appState = nil
        stopWatchdog()
        recorder.stopRecording()
        recordingDirection = nil
        engine.stop()
        engine.onInvoluntaryTearDown = nil
        hotkeyManager.unregisterAll()
        activationObserver.removeObservers(activationTokens)
        activationTokens = []
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        stopWatchdog()
        watchdogTimer = Timer.scheduledTimer(
            withTimeInterval: Self.watchdogInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.performHealthCheck() }
        }
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    func performHealthCheck() {
        guard isStarted else { return }
        let wasGranted = accessibilityGranted
        refreshAccessibility()
        if wasGranted && !accessibilityGranted {
            handlePermissionLost()
        } else if !wasGranted && accessibilityGranted {
            syncEngine()
        }
    }

    private func handlePermissionLost() {
        if recordingDirection != nil { cancelRecording() }
        syncEngine()
    }

    #if DEBUG
    func simulateAccessibilityLoss(_ on: Bool) {
        debugSimulateAXLoss = on
        performHealthCheck()
    }
    #endif

    // MARK: - State Observation

    private func refreshAccessibility() {
        #if DEBUG
        if debugSimulateAXLoss {
            accessibilityGranted = false
            return
        }
        #endif
        accessibilityGranted = permissionChecker.isAccessibilityGranted()
    }

    private func observeStateChanges() {
        guard isStarted, let appState else { return }
        withObservationTracking {
            _ = appState.isEnabled
            _ = appState.leftHotkey
            _ = appState.rightHotkey
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                let now = self.needsEngine
                if now && !self.previousNeedsEngine {
                    self.permissionChecker.promptAccessibility()
                    self.refreshAccessibility()
                }
                self.previousNeedsEngine = now
                self.syncHotkeys()
                self.syncEngine()
                self.observeStateChanges()
            }
        }
    }

    // MARK: - Sync

    func syncHotkeys() {
        guard recordingDirection == nil else { return }
        guard let appState, appState.isEnabled else {
            hotkeyManager.unregisterAll()
            return
        }
        hotkeyManager.register(direction: .left, combination: appState.leftHotkey) { [weak self] in
            self?.engine.switchSpace(direction: .left)
        }
        hotkeyManager.register(direction: .right, combination: appState.rightHotkey) { [weak self] in
            self?.engine.switchSpace(direction: .right)
        }
    }

    private func syncEngine() {
        guard let appState else { return }
        if appState.isEnabled && accessibilityGranted {
            engine.start()
        } else {
            engine.stop()
        }
    }

    // MARK: - Permission

    func openAccessibilitySettings() {
        permissionChecker.openAccessibilitySettings()
    }

    func retryAccessibility() {
        refreshAccessibility()
        syncEngine()
    }

    private func handleEngineTearDown() {
        refreshAccessibility()
        syncHotkeys()
        syncEngine()
    }

    private func handleRecorderTearDown() {
        refreshAccessibility()
        cancelRecording()
    }

    // MARK: - Recording

    func beginRecording(for direction: SpaceDirection) -> Bool {
        if recordingDirection == direction {
            cancelRecording()
            return true
        }
        if recordingDirection != nil { return false }
        guard accessibilityGranted else { return false }

        let started = recorder.startRecording(
            onKeyPress: { [weak self] event in self?.handleRecordedKeyPress(event) },
            onMouseClick: { [weak self] in self?.cancelRecording() },
            onInvoluntaryTearDown: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleRecorderTearDown()
                }
            }
        )
        guard started else { return false }

        hotkeyManager.unregisterAll()
        recordingDirection = direction
        return true
    }

    func cancelRecording() {
        recorder.stopRecording()
        recordingDirection = nil
        syncHotkeys()
    }

    func handleRecordedKeyPress(_ event: NSEvent) {
        guard let direction = recordingDirection, let appState else {
            cancelRecording()
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return
        }
        guard let combo = HotkeyCombination.from(event: event), combo.isValid else {
            NSSound.beep()
            return
        }
        if !appState.setHotkey(combo, for: direction) {
            NSSound.beep()
            cancelRecording()
            return
        }
        cancelRecording()
    }
}
