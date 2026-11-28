import AppKit
import Foundation

extension AppCoordinator {
    /// Wires the switch to the full Typeflux app. Both apps share the bundle identifier and data
    /// locations, so nothing is migrated; the switch only waits until no recording is in progress.
    func startFullAppSwitch() {
        let settingsStore = di.settingsStore
        let appState = di.appState
        FullAppSwitchController.shared.prepareForReplacement = { [weak appState] in
            appState.map { AppCoordinator.canReplaceApp(status: $0.status) } ?? true
        }
        FullAppSwitchWindowController.shared.appearanceMode = { [weak settingsStore] in
            settingsStore?.appearanceMode ?? .system
        }
    }

    nonisolated static func canReplaceApp(status: AppStatus) -> Bool {
        switch status {
        case .recording, .processing: false
        case .idle, .failed: true
        }
    }
}
