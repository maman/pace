import AppKit
import CoreGraphics

@MainActor
protocol EventRecorderProtocol: AnyObject {
    func startRecording(
        onKeyPress: @escaping (NSEvent) -> Void,
        onMouseClick: @escaping () -> Void,
        onInvoluntaryTearDown: @escaping () -> Void
    ) -> Bool
    func stopRecording()
}

final class GlobalEventTapRecorder: EventRecorderProtocol {
    static let shared = GlobalEventTapRecorder()

    nonisolated(unsafe) var eventTap: CFMachPort?
    nonisolated(unsafe) var runLoopSource: CFRunLoopSource?
    nonisolated(unsafe) var onKeyPress: ((NSEvent) -> Void)?
    nonisolated(unsafe) var onMouseClick: (() -> Void)?
    nonisolated(unsafe) var onInvoluntaryTearDown: (() -> Void)?

    private init() {}

    func startRecording(
        onKeyPress: @escaping (NSEvent) -> Void,
        onMouseClick: @escaping () -> Void,
        onInvoluntaryTearDown: @escaping () -> Void
    ) -> Bool {
        stopRecording()

        self.onKeyPress = onKeyPress
        self.onMouseClick = onMouseClick
        self.onInvoluntaryTearDown = onInvoluntaryTearDown

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: recorderCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            self.onKeyPress = nil
            self.onMouseClick = nil
            self.onInvoluntaryTearDown = nil
            return false
        }

        self.eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stopRecording() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            self.eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            self.runLoopSource = nil
        }
        onKeyPress = nil
        onMouseClick = nil
        onInvoluntaryTearDown = nil
    }

    nonisolated func tearDownFromCallback() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
                self.runLoopSource = nil
            }
            CFMachPortInvalidate(tap)
            self.eventTap = nil
        }
    }
}

// MARK: - C Callback

private func recorderCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let recorder = Unmanaged<GlobalEventTapRecorder>.fromOpaque(userInfo).takeUnretainedValue()

    // Tap recovery
    if shouldReEnableTap(type: type) {
        if let tap = recorder.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
    if shouldTearDownTap(type: type) {
        let handler = recorder.onInvoluntaryTearDown
        recorder.tearDownFromCallback()
        handler?()
        return nil
    }

    // Mouse click → cancel recording
    if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
        if let handler = recorder.onMouseClick {
            Task { @MainActor in handler() }
        }
        return nil
    }

    // Key press → record
    if type == .keyDown, let nsEvent = NSEvent(cgEvent: event) {
        if let handler = recorder.onKeyPress {
            Task { @MainActor in handler(nsEvent) }
        }
        return nil
    }

    return Unmanaged.passUnretained(event)
}
