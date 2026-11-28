import AppKit
import SwiftUI
import Testing
@testable import Typeflux

private struct ViewsFixedFetcher: FullAppReleaseFetching {
    var package: FullAppPackage? = FullAppPackage(
        version: "1.2.0", downloadURL: URL(string: "https://example.com/typeflux.zip")!, sha256: nil, fileSize: nil
    )
    func latestFullAppPackage() async throws -> FullAppPackage? { package }
}

private struct ViewsDownloader: FullAppPackageDownloading {
    var hang = false
    func download(from _: URL, progress: @escaping @Sendable (Double?) -> Void) async throws -> URL {
        progress(0.4)
        if hang { try await Task.sleep(for: .seconds(60)) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("full-app-views-\(UUID().uuidString).zip")
        try Data("zip".utf8).write(to: url)
        return url
    }
}

private struct ViewsRejectingInstaller: FullAppSwitchInstalling {
    func stage(archiveURL: URL, package _: FullAppPackage) async throws -> FullAppStagedApp {
        try? FileManager.default.removeItem(at: archiveURL)
        throw FullAppBundleVerificationError.teamIdentifierMismatch
    }
    func launchReplacement(_: FullAppStagedApp) throws {}
    func discard(_: FullAppStagedApp) {}
}

/// Renders every switch phase and the entry wrapper, and drives the panel.
@Suite("Full app switch views", .serialized, .exclusiveUIState)
@MainActor
struct FullAppSwitchViewsTests {
    private func makeController(hang: Bool = false, package: FullAppPackage?? = nil) -> FullAppSwitchController {
        var fetcher = ViewsFixedFetcher()
        if let package { fetcher.package = package }
        return FullAppSwitchController(fetcher: fetcher, downloader: ViewsDownloader(hang: hang),
                                       installer: ViewsRejectingInstaller(), terminate: {})
    }

    private func fittingSize(_ view: some View, dark: Bool = false) -> NSSize {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize
    }

    @Test func everySwitchPhaseRenders() async throws {
        let original = AppLocalization.shared.language
        defer { AppLocalization.shared.setLanguage(original) }
        AppLocalization.shared.setLanguage(.english)
        let confirming = makeController()
        confirming.beginSwitch()
        let confirmSize = fittingSize(FullAppSwitchView(controller: confirming))
        #expect(confirmSize.width == 480)

        let downloading = makeController(hang: true)
        downloading.beginSwitch()
        downloading.confirm()
        for _ in 0 ..< 100 where downloading.phase != .downloading(0.4) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(downloading.phase == .downloading(0.4))
        let downloadSize = fittingSize(FullAppSwitchView(controller: downloading))
        #expect(downloadSize.height > 0)
        downloading.cancel()

        let indeterminate = makeController(hang: true)
        indeterminate.beginSwitch()
        indeterminate.confirm()
        #expect(fittingSize(FullAppSwitchView(controller: indeterminate)).height > 0)
        indeterminate.cancel()

        let failed = makeController()
        failed.beginSwitch()
        failed.confirm()
        await failed.waitForSwitch()
        guard case .failed = failed.phase else {
            Issue.record("expected failure, got \(failed.phase)")
            return
        }
        #expect(fittingSize(FullAppSwitchView(controller: failed)).height > 0)
    }

    @Test func entryWrapperFollowsAvailability() async {
        let available = makeController()
        let unavailable = makeController(package: .some(nil))
        _ = await available.refreshAvailability()
        _ = await unavailable.refreshAvailability()
        let probe = { (controller: FullAppSwitchController) in
            VStack(spacing: 0) {
                FullAppSwitchEntry(controller: controller) { Color.red.frame(width: 20, height: 20) }
            }
            .refreshesFullAppAvailability(controller)
        }
        #expect(fittingSize(probe(available)).height == 20)
        #expect(fittingSize(probe(unavailable)).height == 0)
    }

    @Test func switchWindowOpensAndClosesWithTheFlow() async throws {
        let controller = makeController()
        let windows = FullAppSwitchWindowController(controller: controller)
        windows.appearanceMode = { .dark }
        windows.present()
        #expect(controller.phase == .confirming)
        #expect(windows.isPresented)
        #expect(windows.window?.appearance?.name == .darkAqua)

        // Presenting again keeps the same window.
        let first = windows.window
        windows.present()
        #expect(windows.window === first)

        controller.cancel()
        for _ in 0 ..< 100 where windows.window != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(windows.window == nil)
        #expect(controller.phase == .idle)
    }

    @Test func closingTheSwitchWindowCancelsTheFlow() async throws {
        let controller = makeController(hang: true)
        let windows = FullAppSwitchWindowController(controller: controller)
        windows.present()
        controller.confirm()
        #expect(windows.windowShouldClose(try #require(windows.window)))
        windows.window?.close()
        #expect(controller.phase == .idle)
    }

}
