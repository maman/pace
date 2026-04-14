import Combine
import Sparkle
import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    @Bindable var coordinator: PaceCoordinator
    let updaterController: SPUStandardUpdaterController

    @StateObject private var updatesViewModel: CheckForUpdatesViewModel

    init(
        appState: AppState,
        coordinator: PaceCoordinator,
        updaterController: SPUStandardUpdaterController
    ) {
        self._appState = Bindable(wrappedValue: appState)
        self._coordinator = Bindable(wrappedValue: coordinator)
        self.updaterController = updaterController
        _updatesViewModel = StateObject(
            wrappedValue: CheckForUpdatesViewModel(updaterController: updaterController)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !coordinator.accessibilityGranted {
                accessibilityBanner
            }

            shortcutTable

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

            Spacer()

            HStack {
                Button("Check for Updates") {
                    updaterController.checkForUpdates(nil)
                }
                .disabled(!updatesViewModel.canCheckForUpdates)

                Spacer()

                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding()
        .padding(.top, 20)
        .frame(minWidth: 460, minHeight: 340)
        .onDisappear {
            if coordinator.recordingDirection != nil {
                coordinator.cancelRecording()
            }
        }
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("Accessibility access required to switch spaces")
                .font(.callout)
            Spacer()
            Button("Open System Settings\u{2026}") {
                coordinator.openAccessibilitySettings()
            }
        }
        .padding(10)
        .background(Color.yellow.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private struct ShortcutRow: Identifiable {
        let id: SpaceDirection
        let action: String
        let combo: HotkeyCombination
    }

    private var rows: [ShortcutRow] {
        [
            ShortcutRow(id: .right, action: "Switch Right", combo: appState.rightHotkey),
            ShortcutRow(id: .left, action: "Switch Left", combo: appState.leftHotkey),
        ]
    }

    private var shortcutTable: some View {
        Table(rows) {
            TableColumn("Action") { row in
                Text(row.action)
            }
            TableColumn("Key") { row in
                let isRecording = coordinator.recordingDirection == row.id
                Text(isRecording ? "Recording\u{2026} (Esc to cancel)" : row.combo.displayString)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(isRecording ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { startRecording(row.id) }
            }
        }
        .frame(minHeight: 120)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func startRecording(_ direction: SpaceDirection) {
        guard coordinator.recordingDirection == nil else { return }
        guard coordinator.accessibilityGranted else {
            coordinator.openAccessibilitySettings()
            return
        }
        _ = coordinator.beginRecording(for: direction)
    }
}
