import Sparkle
import SwiftUI

@main
struct PaceApp: App {
    @NSApplicationDelegateAdaptor(PaceAppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra("Pace", systemImage: "hare") {
            PaceMenu(appState: delegate.appState)
        }
        Window("Pace", id: "pace-settings") {
            SettingsView(
                appState: delegate.appState,
                coordinator: delegate.coordinator,
                updaterController: delegate.updaterController
            )
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 340)
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
        if let w = NSApp.windows.first(where: { $0.identifier?.rawValue == "pace-settings" }) {
            w.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Menu Bar Menu

struct PaceMenu: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Enable", isOn: $appState.isEnabled)
        Button("Settings\u{2026}") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "pace-settings")
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}
