import Combine
import Sparkle
import SwiftUI

@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updaterController: SPUStandardUpdaterController) {
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @StateObject private var viewModel: CheckForUpdatesViewModel
    private let updaterController: SPUStandardUpdaterController

    init(updaterController: SPUStandardUpdaterController) {
        self.updaterController = updaterController
        _viewModel = StateObject(wrappedValue:
            CheckForUpdatesViewModel(updaterController: updaterController))
    }

    var body: some View {
        Button("Check for Updates\u{2026}") {
            updaterController.checkForUpdates(nil)
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}
