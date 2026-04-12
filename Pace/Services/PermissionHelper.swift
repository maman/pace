import AppKit
import ApplicationServices

@MainActor
protocol PermissionChecking: AnyObject {
    func promptAccessibility()
    func isAccessibilityGranted() -> Bool
    func openAccessibilitySettings()
}

final class PermissionHelper: PermissionChecking {
    func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Activation Observing

@MainActor
protocol ActivationObserving: AnyObject {
    func observe(onActivate: @escaping () -> Void, onDeactivate: @escaping () -> Void) -> [Any]
    func removeObservers(_ tokens: [Any])
}

final class WorkspaceActivationObserver: ActivationObserving {
    func observe(onActivate: @escaping () -> Void, onDeactivate: @escaping () -> Void) -> [Any] {
        let nc = NSWorkspace.shared.notificationCenter
        let pid = ProcessInfo.processInfo.processIdentifier

        let activateToken = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier == pid else { return }
            Task { @MainActor in onActivate() }
        }

        let deactivateToken = nc.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil, queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier == pid else { return }
            Task { @MainActor in onDeactivate() }
        }

        return [activateToken, deactivateToken]
    }

    func removeObservers(_ tokens: [Any]) {
        let nc = NSWorkspace.shared.notificationCenter
        for token in tokens {
            nc.removeObserver(token)
        }
    }
}
