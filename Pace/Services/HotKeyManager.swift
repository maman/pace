import AppKit
import Carbon

@MainActor
protocol HotKeyManagerProtocol: AnyObject {
    func register(direction: SpaceDirection, combination: HotkeyCombination, handler: @escaping () -> Void)
    func unregister(direction: SpaceDirection)
    func unregisterAll()
}

final class HotKeyManager: HotKeyManagerProtocol {
    static let shared = HotKeyManager()

    private struct Registration {
        let id: UInt32
        var reference: EventHotKeyRef?
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var registrations: [SpaceDirection: Registration] = [:]
    private var currentId: UInt32 = 1

    private init() {
        installEventHandler()
    }

    func register(direction: SpaceDirection, combination: HotkeyCombination, handler: @escaping () -> Void) {
        unregister(direction: direction)

        let id = currentId
        currentId &+= 1

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: 0x5041, id: id) // "PA" for Pace
        let status = RegisterEventHotKey(
            combination.keyCode, combination.modifiers, hotKeyID,
            GetEventDispatcherTarget(), 0, &hotKeyRef
        )

        guard status == noErr else { return }

        handlers[id] = handler
        registrations[direction] = Registration(id: id, reference: hotKeyRef)
    }

    func unregister(direction: SpaceDirection) {
        guard let registration = registrations.removeValue(forKey: direction) else { return }
        handlers.removeValue(forKey: registration.id)
        if let reference = registration.reference {
            UnregisterEventHotKey(reference)
        }
    }

    func unregisterAll() {
        for (_, registration) in registrations {
            if let reference = registration.reference {
                UnregisterEventHotKey(reference)
            }
        }
        registrations.removeAll()
        handlers.removeAll()
    }

    // Carbon callback hardcodes HotKeyManager.shared — @convention(c) cannot capture context.
    // Protocol abstraction exists solely for PaceCoordinator test mocking.
    // Bounces to @MainActor since handlers may touch @MainActor state.
    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, event, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                Task { @MainActor in
                    HotKeyManager.shared.handlers[hotKeyID.id]?()
                }

                return noErr
            },
            1, &eventSpec, nil, nil
        )
    }
}
