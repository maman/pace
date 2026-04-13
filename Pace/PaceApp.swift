import Sparkle
import SwiftUI

@main
struct PaceApp: App {
    @NSApplicationDelegateAdaptor(PaceAppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra("Pace", systemImage: "hare") {
            PaceMenu(
                appState: delegate.appState,
                coordinator: delegate.coordinator,
                updaterController: delegate.updaterController
            )
        }
        Settings {
            ShortcutSettingsView(appState: delegate.appState, coordinator: delegate.coordinator)
        }
    }
}

// MARK: - App Delegate

@MainActor
final class PaceAppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let coordinator = PaceCoordinator()
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        coordinator.start(appState: appState)
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu

        let settingsItem = NSMenuItem(
            title: "Settings\u{2026}",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        let updatesItem = NSMenuItem(
            title: "Check for Updates\u{2026}",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updatesItem.target = updaterController
        appMenu.addItem(updatesItem)

        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Pace",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

// MARK: - Menu Bar Menu

struct PaceMenu: View {
    @Bindable var appState: AppState
    @Bindable var coordinator: PaceCoordinator
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Toggle("Enabled", isOn: $appState.isEnabled)
        Toggle("Trackpad Swipe", isOn: $appState.trackpadSwipeEnabled)

        Divider()

        if coordinator.needsAccessibilityWarning {
            Button("Accessibility Required\u{2026}") {
                coordinator.openAccessibilitySettings()
            }
            Button("Check Again") {
                coordinator.retryAccessibility()
            }
        }

        Text("Switch Left: \(appState.leftHotkey.displayString)")
        Text("Switch Right: \(appState.rightHotkey.displayString)")
        Button("Change Shortcuts\u{2026}") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }

        Divider()

        Toggle("Launch at Login", isOn: Binding(
            get: { appState.launchAtLoginMirror },
            set: { newValue in
                do {
                    try appState.setLaunchAtLogin(newValue)
                } catch {
                    NSSound.beep()
                }
            }
        ))

        Divider()

        CheckForUpdatesView(updaterController: updaterController)

        Divider()

        Button("Quit Pace") {
            NSApp.terminate(nil)
        }
    }
}
