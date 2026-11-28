import AppKit
import SwiftUI
@testable import Typeflux
import XCTest

private let samplePackage = FullAppPackage(
    version: "1.2.0",
    downloadURL: URL(string: "https://api.example.com/d/macos/arm64/global?product=typeflux")!,
    sha256: nil,
    fileSize: nil
)

private final class StubFetcher: FullAppReleaseFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<FullAppPackage?, Error>]
    private(set) var calls = 0

    init(_ results: [Result<FullAppPackage?, Error>]) { self.results = results }

    func latestFullAppPackage() async throws -> FullAppPackage? {
        let result = lock.withLock {
            calls += 1
            return results.count > 1 ? results.removeFirst() : results[0]
        }
        return try result.get()
    }
}

private final class StubDownloader: FullAppPackageDownloading, @unchecked Sendable {
    enum Mode { case succeed, fail, hang }
    var mode: Mode
    private(set) var downloads = 0

    init(_ mode: Mode) { self.mode = mode }

    func download(from _: URL, progress: @escaping @Sendable (Double?) -> Void) async throws -> URL {
        downloads += 1
        progress(0.5)
        switch mode {
        case .succeed:
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("full-app-stub-\(UUID().uuidString).zip")
            try Data("zip".utf8).write(to: url)
            return url
        case .fail:
            throw URLError(.notConnectedToInternet)
        case .hang:
            try await Task.sleep(for: .seconds(30))
            throw URLError(.timedOut)
        }
    }
}

private final class StubInstaller: FullAppSwitchInstalling, @unchecked Sendable {
    var stageError: Error?
    var launchError: Error?
    private(set) var staged = 0
    private(set) var launched = 0
    private(set) var discarded = 0

    func stage(archiveURL: URL, package _: FullAppPackage) async throws -> FullAppStagedApp {
        try? FileManager.default.removeItem(at: archiveURL)
        staged += 1
        if let stageError { throw stageError }
        let dir = FileManager.default.temporaryDirectory
        return FullAppStagedApp(appURL: dir.appendingPathComponent("Typeflux.app"), workingDirectory: dir)
    }

    func launchReplacement(_: FullAppStagedApp) throws {
        if let launchError { throw launchError }
        launched += 1
    }

    func discard(_: FullAppStagedApp) { discarded += 1 }
}

@MainActor
final class FullAppSwitchControllerTests: XCTestCase {
    private var terminated = 0
    private var stopCalls = 0

    private func makeController(
        fetcher: StubFetcher = StubFetcher([.success(samplePackage)]),
        downloader: StubDownloader = StubDownloader(.succeed),
        installer: StubInstaller = StubInstaller(),
        stopResult: Bool = true,
        now: @escaping () -> Date = Date.init
    ) -> FullAppSwitchController {
        let controller = FullAppSwitchController(
            fetcher: fetcher, downloader: downloader, installer: installer,
            terminate: { [weak self] in self?.terminated += 1 }, now: now
        )
        controller.prepareForReplacement = { [weak self] in
            self?.stopCalls += 1
            return stopResult
        }
        return controller
    }

    // MARK: Availability

    func testEntriesHiddenWhenServerHasNoFullApp() async {
        let controller = makeController(fetcher: StubFetcher([.success(nil)]))
        XCTAssertFalse(controller.isAvailable)
        let available = await controller.refreshAvailability()
        XCTAssertFalse(available)
        XCTAssertEqual(controller.availability, .unavailable)
        XCTAssertFalse(controller.isAvailable)
    }

    func testEntriesHiddenWhenServerFails() async {
        let controller = makeController(fetcher: StubFetcher([.failure(URLError(.badServerResponse))]))
        let available = await controller.refreshAvailability()
        XCTAssertFalse(available)
        XCTAssertEqual(controller.availability, .unavailable)
    }

    func testAvailabilityIsCachedUntilForcedOrExpired() async {
        var clock = Date(timeIntervalSince1970: 0)
        let fetcher = StubFetcher([.success(samplePackage), .success(nil)])
        let controller = makeController(fetcher: fetcher, now: { clock })

        let first = await controller.refreshAvailability()
        XCTAssertTrue(first)
        XCTAssertEqual(controller.availability, .available(samplePackage))
        let cached = await controller.refreshAvailability()
        XCTAssertTrue(cached)
        XCTAssertEqual(fetcher.calls, 1)

        clock = clock.addingTimeInterval(16 * 60)
        let expired = await controller.refreshAvailability()
        XCTAssertFalse(expired)
        XCTAssertEqual(fetcher.calls, 2)
        XCTAssertFalse(controller.isAvailable)

        _ = await controller.refreshAvailability(force: true)
        XCTAssertEqual(fetcher.calls, 3)
    }

    // MARK: Switch

    func testSuccessfulSwitchChecksIdleInstallsAndTerminates() async {
        let installer = StubInstaller()
        let controller = makeController(installer: installer)
        controller.beginSwitch()
        XCTAssertEqual(controller.phase, .confirming)
        controller.confirm()
        if case .downloading = controller.phase {} else { XCTFail("expected downloading, got \(controller.phase)") }
        await controller.waitForSwitch()

        XCTAssertEqual(installer.staged, 1)
        XCTAssertEqual(stopCalls, 1)
        XCTAssertEqual(installer.launched, 1)
        XCTAssertEqual(terminated, 1)
        XCTAssertEqual(controller.phase, .installing)
    }

    func testIdentityMismatchRejectsInstall() async {
        for error in [FullAppBundleVerificationError.bundleIdentifierMismatch, .teamIdentifierMismatch] {
            let installer = StubInstaller()
            installer.stageError = error
            let controller = makeController(installer: installer)
            controller.beginSwitch()
            controller.confirm()
            await controller.waitForSwitch()

            guard case let .failed(message) = controller.phase else { return XCTFail("expected failure") }
            XCTAssertEqual(message, FullAppSwitchController.message(for: error))
            XCTAssertEqual(stopCalls, 0)
            XCTAssertEqual(installer.launched, 0)
            XCTAssertEqual(terminated, 0)
        }
    }

    func testBusyAppAbortsBeforeReplacingTheApp() async {
        let installer = StubInstaller()
        let controller = makeController(installer: installer, stopResult: false)
        controller.beginSwitch()
        controller.confirm()
        await controller.waitForSwitch()

        XCTAssertEqual(controller.phase, .failed(FullAppSwitchController.message(for: FullAppSwitchFlowError.appBusy)))
        XCTAssertEqual(installer.discarded, 1)
        XCTAssertEqual(installer.launched, 0)
        XCTAssertEqual(terminated, 0)
    }

    func testLaunchFailureIsReported() async {
        let installer = StubInstaller()
        installer.launchError = CocoaError(.fileWriteNoPermission)
        let controller = makeController(installer: installer)
        controller.beginSwitch()
        controller.confirm()
        await controller.waitForSwitch()

        if case .failed = controller.phase {} else { XCTFail("expected failure") }
        XCTAssertEqual(installer.discarded, 1)
        XCTAssertEqual(terminated, 0)
    }

    func testWithdrawnReleaseFailsAndHidesEntries() async {
        let controller = makeController(fetcher: StubFetcher([.success(samplePackage), .success(nil)]))
        _ = await controller.refreshAvailability()
        XCTAssertTrue(controller.isAvailable)
        controller.beginSwitch()
        controller.confirm()
        await controller.waitForSwitch()

        XCTAssertEqual(controller.phase, .failed(FullAppSwitchController.message(for: FullAppSwitchFlowError.unavailable)))
        XCTAssertFalse(controller.isAvailable)
    }

    func testDownloadFailureCanBeRetried() async {
        let downloader = StubDownloader(.fail)
        let controller = makeController(downloader: downloader)
        controller.beginSwitch()
        controller.confirm()
        await controller.waitForSwitch()
        guard case let .failed(message) = controller.phase else { return XCTFail("expected failure") }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(terminated, 0)

        downloader.mode = .succeed
        controller.retry()
        await controller.waitForSwitch()
        XCTAssertEqual(downloader.downloads, 2)
        XCTAssertEqual(terminated, 1)
    }

    func testCancelDuringDownloadReturnsToIdle() async {
        let downloader = StubDownloader(.hang)
        let installer = StubInstaller()
        let controller = makeController(downloader: downloader, installer: installer)
        controller.beginSwitch()
        controller.confirm()
        // Let the run reach the download.
        for _ in 0 ..< 400 where downloader.downloads == 0 { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(downloader.downloads, 1)
        controller.cancel()
        XCTAssertEqual(controller.phase, .idle)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(installer.staged, 0)
        XCTAssertEqual(terminated, 0)
    }

    func testConfirmRequiresAnOpenConfirmation() async {
        let controller = makeController()
        controller.confirm()
        XCTAssertEqual(controller.phase, .idle)
        controller.beginSwitch()
        controller.beginSwitch()
        XCTAssertEqual(controller.phase, .confirming)
        controller.cancel()
        XCTAssertEqual(controller.phase, .idle)
    }

    func testMessageFallsBackForPlainErrors() {
        XCTAssertFalse(FullAppSwitchController.message(for: URLError(.timedOut)).isEmpty)
        XCTAssertFalse(FullAppSwitchController.message(for: NSError(domain: "x", code: 1)).isEmpty)
    }

    // MARK: Entry visibility

    func testEntryIsHiddenWithoutFullApp() async {
        let hidden = makeController(fetcher: StubFetcher([.success(nil)]))
        _ = await hidden.refreshAvailability()
        XCTAssertEqual(entryHeight(hidden), 0)

        let shown = makeController()
        _ = await shown.refreshAvailability()
        XCTAssertGreaterThan(entryHeight(shown), 0)
    }

    private func entryHeight(_ controller: FullAppSwitchController) -> CGFloat {
        let view = NSHostingView(rootView: VStack(spacing: 0) {
            FullAppSwitchEntry(controller: controller) { Color.red.frame(width: 40, height: 40) }
        })
        view.layoutSubtreeIfNeeded()
        return view.fittingSize.height
    }

    // MARK: Coordinator wiring

    func testReplacementWaitsForRecordingAndProcessing() {
        XCTAssertTrue(AppCoordinator.canReplaceApp(status: .idle))
        XCTAssertTrue(AppCoordinator.canReplaceApp(status: .failed(message: "x")))
        XCTAssertFalse(AppCoordinator.canReplaceApp(status: .recording))
        XCTAssertFalse(AppCoordinator.canReplaceApp(status: .processing))
    }
}
