import AppKit
import Combine
import SwiftUI

/// Shows the confirmation, progress and failure states of `FullAppSwitchController` in a floating
/// panel that matches the update alert.
@MainActor
final class FullAppSwitchWindowController: NSWindowController, NSWindowDelegate {
    static let shared = FullAppSwitchWindowController(controller: .shared)

    /// Set by the app coordinator so the panel follows the chosen appearance.
    var appearanceMode: () -> AppearanceMode = { .system }

    private let controller: FullAppSwitchController
    private var phaseObserver: AnyCancellable?

    init(controller: FullAppSwitchController) {
        self.controller = controller
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    var isPresented: Bool { window?.isVisible == true }

    /// Opens the confirmation, or brings a running switch to the front.
    func present() {
        controller.beginSwitch()
        if window == nil {
            let panel = Self.makePanel(appearanceMode: appearanceMode())
            let hosting = NSHostingController(rootView: AnyView(
                FullAppSwitchView(controller: controller).environment(\.locale, AppLocalization.shared.locale)
            ))
            hosting.sizingOptions = [.preferredContentSize]
            panel.contentViewController = hosting
            panel.setContentSize(hosting.view.fittingSize)
            panel.center()
            panel.delegate = self
            window = panel
            phaseObserver = controller.$phase.dropFirst().sink { [weak self] phase in
                // Published fires before the value changes; act on the next turn.
                DispatchQueue.main.async { self?.phaseDidChange(phase) }
            }
        }
        guard let window else { return }
        DockVisibilityController.shared.windowDidShow(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func makePanel(appearanceMode: AppearanceMode) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 240),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.appearance = AppAppearance.nsAppearance(for: appearanceMode)
        return panel
    }

    private func phaseDidChange(_ phase: FullAppSwitchController.Phase) {
        guard let window else { return }
        if phase == .idle {
            window.close()
        } else if let hosting = window.contentViewController {
            window.setContentSize(hosting.view.fittingSize)
        }
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        controller.phase != .installing
    }

    func windowWillClose(_: Notification) {
        if let window { DockVisibilityController.shared.windowDidHide(window) }
        phaseObserver = nil
        window = nil
        controller.cancel()
    }
}
