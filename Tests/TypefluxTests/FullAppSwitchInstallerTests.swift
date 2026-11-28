@testable import Typeflux
import XCTest

final class FullAppSwitchInstallerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("full-app-installer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Builds a zip that contains an (unsigned) app bundle, as the release server ships it.
    private func makeArchive() throws -> URL {
        let app = root.appendingPathComponent("payload/Typeflux.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("<plist version=\"1.0\"><dict></dict></plist>".utf8).write(to: app.appendingPathComponent("Info.plist"))
        let zip = root.appendingPathComponent("typeflux.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", root.appendingPathComponent("payload/Typeflux.app").path, zip.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return zip
    }

    private func installer(candidate: FullAppSigningIdentity) -> AutoUpdaterFullAppSwitchInstaller {
        AutoUpdaterFullAppSwitchInstaller(
            currentIdentity: { FullAppSigningIdentity(bundleIdentifier: "ai.gulu.app.typeflux", teamIdentifier: "TEAM",
                                                      leafCertificateSHA256: nil) },
            candidateIdentity: { _ in candidate },
            verifyCodeSignature: { _ in }
        )
    }

    func testStagesMatchingApp() async throws {
        let zip = try makeArchive()
        let sut = installer(candidate: FullAppSigningIdentity(bundleIdentifier: "ai.gulu.app.typeflux",
                                                               teamIdentifier: "TEAM", leafCertificateSHA256: nil))
        let checksum = try FullAppBundleVerifier.sha256(ofFileAt: zip)
        let package = FullAppPackage(version: "1.2.0", downloadURL: zip, sha256: checksum, fileSize: nil)
        let staged = try await sut.stage(archiveURL: zip, package: package)

        XCTAssertEqual(staged.appURL.lastPathComponent, "Typeflux.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.appURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: zip.path))
        sut.discard(staged)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.workingDirectory.path))
    }

    func testRejectsForeignBundleAndTeam() throws {
        let candidates = [
            FullAppSigningIdentity(bundleIdentifier: "com.example.other", teamIdentifier: "TEAM", leafCertificateSHA256: nil),
            FullAppSigningIdentity(bundleIdentifier: "ai.gulu.app.typeflux", teamIdentifier: "OTHER", leafCertificateSHA256: nil),
        ]
        let expected: [FullAppBundleVerificationError] = [.bundleIdentifierMismatch, .teamIdentifierMismatch]
        for (candidate, error) in zip(candidates, expected) {
            let zipURL = try makeArchive()
            let package = FullAppPackage(version: "1.2.0", downloadURL: zipURL, sha256: nil, fileSize: nil)
            XCTAssertThrowsError(try installer(candidate: candidate).stageSynchronously(archiveURL: zipURL, package: package)) {
                XCTAssertEqual($0 as? FullAppBundleVerificationError, error)
            }
            try? FileManager.default.removeItem(at: root.appendingPathComponent("payload"))
        }
    }

    func testRejectsChecksumMismatch() throws {
        let zip = try makeArchive()
        let sut = installer(candidate: FullAppSigningIdentity(bundleIdentifier: "ai.gulu.app.typeflux",
                                                               teamIdentifier: "TEAM", leafCertificateSHA256: nil))
        let package = FullAppPackage(version: "1.2.0", downloadURL: zip, sha256: String(repeating: "0", count: 64), fileSize: nil)
        XCTAssertThrowsError(try sut.stageSynchronously(archiveURL: zip, package: package)) {
            XCTAssertEqual($0 as? FullAppSwitchInstallError, .checksumMismatch)
        }
        XCTAssertNotNil(FullAppSwitchInstallError.checksumMismatch.errorDescription)
    }
}
