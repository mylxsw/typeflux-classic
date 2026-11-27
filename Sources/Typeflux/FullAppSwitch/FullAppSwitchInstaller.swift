import Foundation

/// A verified Typeflux app waiting in a temporary directory.
struct FullAppStagedApp: Equatable, Sendable {
    let appURL: URL
    let workingDirectory: URL
}

enum FullAppSwitchInstallError: LocalizedError, Equatable {
    case checksumMismatch

    var errorDescription: String? { L("updater.install.signatureVerificationFailed") }
}

protocol FullAppSwitchInstalling: Sendable {
    /// Checks the archive, extracts the app and verifies its signature, Bundle ID and Team ID.
    func stage(archiveURL: URL, package: FullAppPackage) async throws -> FullAppStagedApp
    /// Hands the staged app to the relaunch script; the caller terminates the app next.
    func launchReplacement(_ staged: FullAppStagedApp) throws
    func discard(_ staged: FullAppStagedApp)
}

/// Reuses the `AutoUpdater` extraction, signature check and relaunch script.
struct AutoUpdaterFullAppSwitchInstaller: FullAppSwitchInstalling {
    var currentIdentity: @Sendable () throws -> FullAppSigningIdentity = { try FullAppBundleVerifier.currentIdentity() }
    var candidateIdentity: @Sendable (URL) throws -> FullAppSigningIdentity = { try FullAppBundleVerifier.identity(ofAppAt: $0) }
    var verifyCodeSignature: @Sendable (URL) throws -> Void = { try AutoUpdateArchiveInstaller.verifyCodeSignature(of: $0) }

    func stage(archiveURL: URL, package: FullAppPackage) async throws -> FullAppStagedApp {
        try await Task.detached(priority: .userInitiated) {
            try stageSynchronously(archiveURL: archiveURL, package: package)
        }.value
    }

    func stageSynchronously(archiveURL: URL, package: FullAppPackage) throws -> FullAppStagedApp {
        let fm = FileManager.default
        defer { try? fm.removeItem(at: archiveURL) }
        if let expected = package.sha256 {
            guard try FullAppBundleVerifier.sha256(ofFileAt: archiveURL) == expected else {
                throw FullAppSwitchInstallError.checksumMismatch
            }
        }
        let workingDirectory = fm.temporaryDirectory.appendingPathComponent("typeflux-full-switch-\(UUID().uuidString)")
        try fm.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        do {
            try Task.checkCancellation()
            let appURL = try AutoUpdateArchiveInstaller.extractAppFromZip(archiveURL, into: workingDirectory)
            try verifyCodeSignature(appURL)
            try FullAppBundleVerifier.verify(candidate: candidateIdentity(appURL), current: currentIdentity())
            return FullAppStagedApp(appURL: appURL, workingDirectory: workingDirectory)
        } catch {
            try? fm.removeItem(at: workingDirectory)
            throw error
        }
    }

    func launchReplacement(_ staged: FullAppStagedApp) throws {
        try AutoUpdateArchiveInstaller.launchReplacement(
            newAppURL: staged.appURL,
            cleanupURL: staged.workingDirectory,
            relaunch: true
        )
    }

    func discard(_ staged: FullAppStagedApp) {
        try? FileManager.default.removeItem(at: staged.workingDirectory)
    }
}
