import SwiftUI

struct ShortcutSettingsView: View {
    @Bindable var appState: AppState
    @Bindable var coordinator: PaceCoordinator
    @State private var statusMessage = ""
    @State private var statusIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcuts").font(.headline)

            shortcutRow(
                direction: .left,
                label: "Switch Left:",
                combo: appState.leftHotkey,
                defaultCombo: .defaultLeft
            )
            shortcutRow(
                direction: .right,
                label: "Switch Right:",
                combo: appState.rightHotkey,
                defaultCombo: .defaultRight
            )

            if coordinator.recordingDirection != nil {
                Text("Press desired key combination. Esc to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? .red : .secondary)
            }
        }
        .padding()
        .frame(minWidth: 380)
        .onDisappear {
            if coordinator.recordingDirection != nil {
                coordinator.cancelRecording()
                statusMessage = ""
            }
        }
    }

    @ViewBuilder
    private func shortcutRow(
        direction: SpaceDirection,
        label: String,
        combo: HotkeyCombination,
        defaultCombo: HotkeyCombination
    ) -> some View {
        HStack {
            Text(label)
                .frame(width: 100, alignment: .leading)
            Text(combo.displayString)
                .font(.system(.body, design: .monospaced))
            Spacer()
            Button(coordinator.recordingDirection == direction ? "Press shortcut\u{2026}" : "Record") {
                recordTapped(for: direction)
            }
            .disabled(coordinator.recordingDirection != nil && coordinator.recordingDirection != direction)

            Button("Reset") {
                if !appState.setHotkey(defaultCombo, for: direction) {
                    NSSound.beep()
                    statusMessage = "Shortcut conflict"
                    statusIsError = true
                }
            }
            .disabled(coordinator.recordingDirection != nil)
        }
    }

    private func recordTapped(for direction: SpaceDirection) {
        guard coordinator.accessibilityGranted else {
            coordinator.openAccessibilitySettings()
            return
        }
        if !coordinator.beginRecording(for: direction) {
            if coordinator.recordingDirection == nil {
                statusMessage = "Failed to start recording"
                statusIsError = true
            }
            return
        }
        statusMessage = ""
        statusIsError = false
    }
}
