@testable import Typeflux
import XCTest

final class FullAppBundleVerifierTests: XCTestCase {
    private let current = FullAppSigningIdentity(bundleIdentifier: "ai.gulu.app.typeflux", teamIdentifier: "TEAM123",
                                                 leafCertificateSHA256: "leaf")

    func testMatchingBundleAndTeamIsAccepted() {
        let candidate = FullAppSigningIdentity(bundleIdentifier: "ai.gulu.app.typeflux", teamIdentifier: "TEAM123",
                                               leafCertificateSHA256: "other-leaf")
        XCTAssertNoThrow(try FullAppBundleVerifier.verify(candidate: candidate, current: current))
    }

    func testDifferentBundleIdentifierIsRejected() {
        let candidate = FullAppSigningIdentity(bundleIdentifier: "com.example.fake", teamIdentifier: "TEAM123",
                                               leafCertificateSHA256: "leaf")
        XCTAssertThrowsError(try FullAppBundleVerifier.verify(candidate: candidate, current: current)) {
            XCTAssertEqual($0 as? FullAppBundleVerificationError, .bundleIdentifierMismatch)
        }
        let missing = FullAppSigningIdentity(bundleIdentifier: nil, teamIdentifier: "TEAM123", leafCertificateSHA256: nil)
        XCTAssertThrowsError(try FullAppBundleVerifier.verify(candidate: missing, current: current))
    }

    func testDifferentTeamIsRejected() {
        for team in ["OTHER", nil] {
            let candidate = FullAppSigningIdentity(bundleIdentifier: "ai.gulu.app.typeflux", teamIdentifier: team,
                                                   leafCertificateSHA256: "leaf")
            XCTAssertThrowsError(try FullAppBundleVerifier.verify(candidate: candidate, current: current)) {
                XCTAssertEqual($0 as? FullAppBundleVerificationError, .teamIdentifierMismatch)
            }
        }
    }

    func testTeamlessBuildRequiresTheSameCertificate() {
        let dev = FullAppSigningIdentity(bundleIdentifier: "ai.gulu.app.typeflux", teamIdentifier: nil,
                                         leafCertificateSHA256: "dev-leaf")
        XCTAssertNoThrow(try FullAppBundleVerifier.verify(candidate: dev, current: dev))

        let otherCertificate = FullAppSigningIdentity(bundleIdentifier: "ai.gulu.app.typeflux", teamIdentifier: nil,
                                                      leafCertificateSHA256: "attacker")
        XCTAssertThrowsError(try FullAppBundleVerifier.verify(candidate: otherCertificate, current: dev))

        let adHoc = FullAppSigningIdentity(bundleIdentifier: "ai.gulu.app.typeflux", teamIdentifier: nil,
                                           leafCertificateSHA256: nil)
        XCTAssertThrowsError(try FullAppBundleVerifier.verify(candidate: adHoc, current: adHoc))

        let teamSigned = FullAppSigningIdentity(bundleIdentifier: "ai.gulu.app.typeflux", teamIdentifier: "TEAM123",
                                                leafCertificateSHA256: "dev-leaf")
        XCTAssertThrowsError(try FullAppBundleVerifier.verify(candidate: teamSigned, current: dev))
    }

    func testErrorsHaveDescriptions() {
        XCTAssertNotNil(FullAppBundleVerificationError.bundleIdentifierMismatch.errorDescription)
        XCTAssertNotNil(FullAppBundleVerificationError.signatureUnreadable.errorDescription)
    }

    func testSHA256OfFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("full-app-sha-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try FullAppBundleVerifier.sha256(ofFileAt: url),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testReadsIdentityOfASignedApp() throws {
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: calculator.path))
        let identity = try FullAppBundleVerifier.identity(ofAppAt: calculator)
        XCTAssertEqual(identity.bundleIdentifier, "com.apple.calculator")
        XCTAssertNotNil(identity.leafCertificateSHA256)
        XCTAssertEqual(identity.leafCertificateSHA256?.count, 64)
    }

    func testReadsCurrentProcessIdentityWhenSigned() {
        // The test runner may be ad-hoc signed; either outcome must be a clean result, not a crash.
        if let identity = try? FullAppBundleVerifier.currentIdentity() {
            XCTAssertEqual(identity.bundleIdentifier, Bundle.main.bundleIdentifier)
        }
    }

    func testMissingAppIsUnreadable() {
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).app")
        XCTAssertThrowsError(try FullAppBundleVerifier.identity(ofAppAt: missing)) {
            XCTAssertEqual($0 as? FullAppBundleVerificationError, .signatureUnreadable)
        }
    }

    func testUnsignedDirectoryIdentityIsUnreadableOrTeamless() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("Unsigned-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: app) }
        if let identity = try? FullAppBundleVerifier.identity(ofAppAt: app) {
            XCTAssertNil(identity.teamIdentifier)
            XCTAssertNil(identity.leafCertificateSHA256)
        }
    }
}
