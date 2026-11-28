import AppKit
import Foundation

/// Drives the switch from Typeflux Classic to the full Typeflux app: availability for the About
/// entry, then confirm → download → verify → check the app is idle → replace the app and relaunch.
@MainActor
final class FullAppSwitchController: ObservableObject {
    static let shared = FullAppSwitchController()

    enum Availability: Equatable {
        case unknown
        case unavailable
        case available(FullAppPackage)
    }

    enum Phase: Equatable {
        case idle
        case confirming
        /// Fraction of the download, or nil while the size is unknown.
        case downloading(Double?)
        case installing
        case failed(String)
    }

    @Published private(set) var availability: Availability = .unknown
    @Published private(set) var phase: Phase = .idle

    var isAvailable: Bool {
        if case .available = availability { return true }
        return false
    }

    /// Checks that no work is running before the bundle is replaced.
    /// Returns false when the app is busy (for example a recording in progress).
    var prepareForReplacement: @MainActor () async -> Bool = { true }

    private let fetcher: any FullAppReleaseFetching
    private let downloader: any FullAppPackageDownloading
    private let installer: any FullAppSwitchInstalling
    private let terminate: @MainActor () -> Void
    private let now: () -> Date
    private let availabilityLifetime: TimeInterval
    private var lastAvailabilityCheck: Date?
    private var availabilityTask: Task<Bool, Never>?
    private var switchTask: Task<Void, Never>?
    /// Identifies the current run so a cancelled run never changes the phase of a newer one.
    private var runID = UUID()

    init(
        fetcher: any FullAppReleaseFetching = CloudFullAppReleaseFetcher(),
        downloader: any FullAppPackageDownloading = URLSessionFullAppPackageDownloader(),
        installer: any FullAppSwitchInstalling = AutoUpdaterFullAppSwitchInstaller(),
        terminate: @escaping @MainActor () -> Void = { NSApp.terminate(nil) },
        now: @escaping () -> Date = Date.init,
        availabilityLifetime: TimeInterval = 15 * 60
    ) {
        self.fetcher = fetcher
        self.downloader = downloader
        self.installer = installer
        self.terminate = terminate
        self.now = now
        self.availabilityLifetime = availabilityLifetime
    }

    // MARK: - Availability

    /// Any error or a missing package hides the switch entry.
    @discardableResult
    func refreshAvailability(force: Bool = false) async -> Bool {
        if let availabilityTask { return await availabilityTask.value }
        if !force, let lastAvailabilityCheck, now().timeIntervalSince(lastAvailabilityCheck) < availabilityLifetime {
            return isAvailable
        }
        let fetcher = fetcher
        let task = Task<Bool, Never> { @MainActor [weak self] in
            let package = try? await fetcher.latestFullAppPackage()
            guard let self else { return false }
            self.apply(package: package)
            return package != nil
        }
        availabilityTask = task
        let result = await task.value
        availabilityTask = nil
        return result
    }

    private func apply(package: FullAppPackage?) {
        lastAvailabilityCheck = now()
        let next: Availability = package.map { .available($0) } ?? .unavailable
        if availability != next { availability = next }
    }

    // MARK: - Switch

    /// Opens the confirmation. Ignored while a switch is already running.
    func beginSwitch() {
        guard phase == .idle || isFailed else { return }
        phase = .confirming
    }

    func confirm() {
        guard phase == .confirming || isFailed else { return }
        let id = UUID()
        runID = id
        phase = .downloading(nil)
        switchTask = Task { @MainActor [weak self] in
            await self?.runSwitch(id: id)
            if self?.runID == id { self?.switchTask = nil }
        }
    }

    func retry() {
        confirm()
    }

    /// Closes the flow. A running download is cancelled; installation cannot be cancelled.
    func cancel() {
        guard phase != .installing else { return }
        switchTask?.cancel()
        switchTask = nil
        runID = UUID()
        phase = .idle
    }

    /// Waits for the running switch; used by tests.
    func waitForSwitch() async {
        await switchTask?.value
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func runSwitch(id: UUID) async {
        var staged: FullAppStagedApp?
        do {
            // Ask again so a version withdrawn on the server is never installed.
            guard let package = try await fetcher.latestFullAppPackage() else {
                apply(package: nil)
                throw FullAppSwitchFlowError.unavailable
            }
            apply(package: package)
            try Task.checkCancellation()
            let archive = try await downloader.download(from: package.downloadURL) { [weak self] fraction in
                Task { @MainActor [weak self] in
                    guard let self, self.runID == id, case .downloading = self.phase else { return }
                    self.phase = .downloading(fraction)
                }
            }
            if Task.isCancelled || runID != id {
                try? FileManager.default.removeItem(at: archive)
                throw CancellationError()
            }
            phase = .installing
            let stagedApp = try await installer.stage(archiveURL: archive, package: package)
            staged = stagedApp
            guard runID == id else { throw CancellationError() }
            guard await prepareForReplacement() else { throw FullAppSwitchFlowError.appBusy }
            try installer.launchReplacement(stagedApp)
            terminate()
        } catch is CancellationError {
            if let staged { installer.discard(staged) }
            if runID == id, phase != .idle { phase = .idle }
        } catch {
            if let staged { installer.discard(staged) }
            guard runID == id, phase != .idle else { return }
            phase = .failed(Self.message(for: error))
        }
    }

    static func message(for error: Error) -> String {
        // Network failures, from the release check or from the transfer, share one message.
        // The executor describes them in untranslated technical English.
        if error is CloudRequestExecutorError || (error as NSError).domain == NSURLErrorDomain {
            return L("fullAppSwitch.error.download")
        }
        if let error = error as? LocalizedError, let description = error.errorDescription, !description.isEmpty {
            return description
        }
        return error.localizedDescription
    }
}

enum FullAppSwitchFlowError: LocalizedError, Equatable {
    case unavailable
    case appBusy

    var errorDescription: String? {
        switch self {
        case .unavailable: L("fullAppSwitch.error.unavailable")
        case .appBusy: L("fullAppSwitch.error.busy")
        }
    }
}
