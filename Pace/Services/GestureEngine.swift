import ApplicationServices
import CoreGraphics

// MARK: - Protocol

@MainActor
protocol GestureEngineProtocol: AnyObject {
    var isRunning: Bool { get }
    func start()
    func stop()
    nonisolated func switchSpace(direction: SpaceDirection)
}

// MARK: - Swipe State

struct SwipeState {
    var swipeTracking = false
    var swipeFired = false
    var passthrough = 0

    mutating func reset() {
        swipeTracking = false
        swipeFired = false
        passthrough = 0
    }
}

// MARK: - Callback Action

enum CallbackAction: Equatable {
    case suppress
    case passthrough
    case fireSwitch(Bool) // isRight
}

// MARK: - Pure Callback Logic (port of iss-touchpad/iss.c:183-233)

func processGestureEvent(
    eventType: Int,
    hidType: Int,
    motion: Int,
    phase: Int,
    progress: Double,
    velocityX: Double,
    state: inout SwipeState
) -> CallbackAction {
    // 1. Let our own synthetic events pass through (iss.c:194-198)
    if state.passthrough > 0 && (eventType == 30 || eventType == 29) {
        state.passthrough -= 1
        return .passthrough
    }

    // 2. Only intercept horizontal dock swipes (iss.c:201-203)
    if eventType == 30 && hidType == 23 && motion == 1 {
        switch phase {
        case 1: // Began (iss.c:207-208)
            state.swipeTracking = true
            state.swipeFired = false
            return .suppress

        case 2 where state.swipeTracking: // Changed (iss.c:210-215)
            if !state.swipeFired && progress != 0.0 {
                state.swipeFired = true
                return .fireSwitch(progress > 0)
            }
            return .suppress

        case 4 where state.swipeTracking: // Ended (iss.c:217-223)
            let action: CallbackAction
            if !state.swipeFired && velocityX != 0.0 {
                action = .fireSwitch(velocityX > 0)
            } else {
                action = .suppress
            }
            state.swipeTracking = false
            state.swipeFired = false
            return action

        case 8: // Cancelled (iss.c:224-226)
            state.swipeTracking = false
            state.swipeFired = false
            return .suppress

        default: // Other phases (iss.c:227)
            return state.swipeTracking ? .suppress : .passthrough
        }
    }

    // 3. Suppress companion gesture events during swipe (iss.c:231)
    if eventType == 29 && state.swipeTracking { return .suppress }

    // 4. Pass everything else through (iss.c:232)
    return .passthrough
}

// MARK: - Tap Recovery Helper

func shouldReEnableTap(type: CGEventType) -> Bool {
    type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
}

// MARK: - CGEvent Field Constants (iss.c:44-53)

private let kCGSEventTypeField = CGEventField(rawValue: 55)!
private let kCGEventGestureHIDType = CGEventField(rawValue: 110)!
private let kCGEventGestureScrollY = CGEventField(rawValue: 119)!
private let kCGEventGestureSwipeMotion = CGEventField(rawValue: 123)!
private let kCGEventGestureSwipeProgress = CGEventField(rawValue: 124)!
private let kCGEventGestureSwipeVelocityX = CGEventField(rawValue: 129)!
private let kCGEventGestureSwipeVelocityY = CGEventField(rawValue: 130)!
private let kCGEventGesturePhase = CGEventField(rawValue: 132)!
private let kCGEventScrollGestureFlagBits = CGEventField(rawValue: 135)!
private let kCGEventGestureZoomDeltaX = CGEventField(rawValue: 139)!

// MARK: - Gesture Engine

final class GestureEngine: GestureEngineProtocol {
    static let shared = GestureEngine()

    nonisolated(unsafe) var state = SwipeState()
    nonisolated(unsafe) var tap: CFMachPort?
    nonisolated(unsafe) var runLoopSource: CFRunLoopSource?
    nonisolated(unsafe) var canSwitchFn: (SpaceDirection) -> SwitchCheck = { canSwitch(direction: $0) }

    var isRunning: Bool { tap != nil }

    func start() {
        guard tap == nil else { return }
        state.reset()

        let mask = CGEventMask((1 << 29) | (1 << 30))
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: gestureEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        tap = newTap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
    }

    func stop() {
        guard let t = tap else { return }
        CGEvent.tapEnable(tap: t, enable: false)
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = nil
        }
        CFMachPortInvalidate(t)
        tap = nil
        state.reset()
    }

    nonisolated func switchSpace(direction: SpaceDirection) {
        let check = canSwitchFn(direction)
        switch check {
        case .blocked: return
        case .allowed, .unknown:
            state.passthrough += 4
            postSyntheticSwitch(isRight: direction == .right)
        }
    }

    // MARK: - Synthetic Event Posting (port of iss.c:87-175)

    private nonisolated func makeDockEvent(phase: Int, isRight: Bool) -> CGEvent? {
        guard let ev = CGEvent(source: nil) else { return nil }
        ev.setIntegerValueField(kCGSEventTypeField, value: 30) // DockControl
        ev.setIntegerValueField(kCGEventGestureHIDType, value: 23) // DockSwipe
        ev.setIntegerValueField(kCGEventGesturePhase, value: Int64(phase))
        ev.setIntegerValueField(kCGEventScrollGestureFlagBits, value: isRight ? 1 : 0)
        ev.setIntegerValueField(kCGEventGestureSwipeMotion, value: 1) // Horizontal
        ev.setDoubleValueField(kCGEventGestureScrollY, value: 0)
        ev.setDoubleValueField(kCGEventGestureZoomDeltaX, value: Double(Float(bitPattern: 1)))
        return ev
    }

    private nonisolated func postPair(dock: CGEvent) {
        guard let companion = CGEvent(source: nil) else { return }
        companion.setIntegerValueField(kCGSEventTypeField, value: 29) // Gesture
        dock.post(tap: .cgSessionEventTap)
        companion.post(tap: .cgSessionEventTap)
    }

    private nonisolated func postSyntheticSwitch(isRight: Bool) {
        let sign: Double = isRight ? 1.0 : -1.0

        guard let begin = makeDockEvent(phase: 1, isRight: isRight) else { return }
        guard let end = makeDockEvent(phase: 4, isRight: isRight) else { return }

        end.setDoubleValueField(kCGEventGestureSwipeProgress, value: sign * 2.0)
        end.setDoubleValueField(kCGEventGestureSwipeVelocityX, value: sign * 400.0)
        end.setDoubleValueField(kCGEventGestureSwipeVelocityY, value: 0)

        postPair(dock: begin)
        postPair(dock: end)
    }
}

// MARK: - C Callback (nonisolated, runs on main thread via CFRunLoopGetMain)

private func gestureEventCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let engine = Unmanaged<GestureEngine>.fromOpaque(userInfo!).takeUnretainedValue()

    // Tap recovery (iss.c:186-189)
    if shouldReEnableTap(type: type) {
        if let tap = engine.tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    let eventType = Int(event.getIntegerValueField(kCGSEventTypeField))
    let hidType = Int(event.getIntegerValueField(kCGEventGestureHIDType))
    let motion = Int(event.getIntegerValueField(kCGEventGestureSwipeMotion))
    let phase = Int(event.getIntegerValueField(kCGEventGesturePhase))
    let progress = event.getDoubleValueField(kCGEventGestureSwipeProgress)
    let velocityX = event.getDoubleValueField(kCGEventGestureSwipeVelocityX)

    let action = processGestureEvent(
        eventType: eventType, hidType: hidType, motion: motion,
        phase: phase, progress: progress, velocityX: velocityX,
        state: &engine.state
    )

    switch action {
    case .suppress:
        return nil
    case .passthrough:
        return Unmanaged.passUnretained(event)
    case .fireSwitch(let isRight):
        engine.switchSpace(direction: isRight ? .right : .left)
        return nil
    }
}
