import Foundation
@testable import Typeflux
import XCTest

final class ClassicProductBrandingTests: XCTestCase {
    private static let productName = "Typeflux Classic"

    /// Keys whose value is exactly the product name.
    private static let exactProductNameKeys = [
        "about.appName",
        "sidebar.appName",
        "window.voiceStudio",
        "studio.eyebrow.home",
        "notification.localModelReady.title"
    ]

    /// Keys for menu bar, About, onboarding and updater copy that must mention the product name.
    private static let productNameMentionKeys = [
        "menu.openVoiceStudio",
        "menu.about",
        "window.about",
        "sidebar.aboutAccessibility",
        "onboarding.window.title",
        "updater.available.title",
        "updater.latest.message"
    ]

    /// Copy that names the shared cloud service rather than this app keeps the plain "Typeflux" brand.
    private static let sharedServiceKeyPattern = try! NSRegularExpression(
        pattern: "typefluxOfficial|typefluxCloud",
        options: [.caseInsensitive]
    )

    /// A bare "Typeflux" that is not a path, an identifier, or a shared service / account name.
    private static let bareProductNamePattern = try! NSRegularExpression(
        pattern: #"(?<![/\w])Typeflux(?![_A-Za-z/])"#
            + #"(?!\s*(Classic|Cloud|Official|website|のウェブサイト|웹사이트|官网|官網|account|账号|账户|帳號|帳戶|アカウント|계정|云端|雲端|クラウド|클라우드|官方|公式|공식|'s built-in))"#
    )

    func testProductNameIsTypefluxClassicInEveryLanguage() throws {
        for language in AppLanguage.allCases {
            let table = try localizedTable(for: language)
            for key in Self.exactProductNameKeys {
                XCTAssertEqual(table[key], Self.productName, "\(key) in \(language.rawValue)")
            }
            for key in Self.productNameMentionKeys {
                let value = try XCTUnwrap(table[key], "Missing \(key) in \(language.rawValue)")
                XCTAssertTrue(value.contains(Self.productName), "\(key) in \(language.rawValue): \(value)")
            }
        }
    }

    /// Copy that deliberately names the full Typeflux app, which Classic shares settings with.
    private static let fullTypefluxReferenceKeys: Set<String> = [
        "classic.fullVersion.link",
        "settings.models.sharedRewriteUnavailable"
    ]

    func testNoBareTypefluxProductNameRemainsInUserVisibleCopy() throws {
        for language in AppLanguage.allCases {
            let table = try localizedTable(for: language)
            for (key, value) in table where !matches(Self.sharedServiceKeyPattern, key) {
                guard !Self.fullTypefluxReferenceKeys.contains(key), !key.hasPrefix(Self.fullAppSwitchKeyPrefix) else { continue }
                XCTAssertFalse(
                    matches(Self.bareProductNamePattern, value),
                    "Bare product name in \(key) for \(language.rawValue): \(value)"
                )
            }
        }
    }

    /// The switch to the full app names its target, the full Typeflux, and never Classic.
    private static let fullAppSwitchKeyPrefix = "fullAppSwitch."

    func testFullAppSwitchCopyNamesFullTypefluxInEveryLanguage() throws {
        for language in AppLanguage.allCases {
            let table = try localizedTable(for: language)
            let switchCopy = table.filter { $0.key.hasPrefix(Self.fullAppSwitchKeyPrefix) }
            XCTAssertFalse(switchCopy.isEmpty, "Missing switch copy in \(language.rawValue)")
            for (key, value) in switchCopy {
                XCTAssertFalse(value.contains("Classic"), "\(key) in \(language.rawValue): \(value)")
            }
            let action = try XCTUnwrap(table["fullAppSwitch.action.switch"], "Missing action in \(language.rawValue)")
            XCTAssertTrue(action.contains("Typeflux"), action)
        }
    }

    func testFullVersionLinkTitleNamesFullTypefluxInEveryLanguage() throws {
        for language in AppLanguage.allCases {
            let table = try localizedTable(for: language)
            let value = try XCTUnwrap(table["classic.fullVersion.link"], "Missing link title in \(language.rawValue)")
            XCTAssertTrue(value.contains("Typeflux"), value)
            XCTAssertFalse(value.contains("Classic"), value)
        }
    }

    func testFullVersionLinkOpensComparisonPage() {
        XCTAssertEqual(ClassicFullVersionLink.destination, ClassicProductLinks.fullVersionComparisonURL)
        XCTAssertEqual(ClassicProductLinks.fullVersionComparisonURL.scheme, "https")
        XCTAssertEqual(ClassicProductLinks.fullVersionComparisonURL.host, "typeflux.app")
        XCTAssertEqual(ClassicProductLinks.fullVersionComparisonURL.path, "/compare")
    }

    func testFullVersionLinkTitleFollowsAppLanguage() {
        let localization = AppLocalization.shared
        let original = localization.language
        defer { localization.setLanguage(original) }

        localization.setLanguage(.simplifiedChinese)
        XCTAssertEqual(ClassicFullVersionLink.title, "了解完整版 Typeflux")

        localization.setLanguage(.english)
        XCTAssertEqual(ClassicFullVersionLink.title, "Learn about the full Typeflux")
    }

    func testClassicRepositoryLinks() {
        XCTAssertEqual(ClassicProductLinks.projectURL.absoluteString, "https://github.com/mylxsw/typeflux-classic")
        XCTAssertEqual(
            ClassicProductLinks.newIssueURL.absoluteString,
            "https://github.com/mylxsw/typeflux-classic/issues/new"
        )
    }

    func testAppInfoPlistKeepsBundleNameMatchingTheAppFileName() throws {
        let plist = try infoPlist(at: "app/Info.plist")

        // macOS only applies a localized CFBundleDisplayName when the unlocalized value matches the
        // "Typeflux.app" file name, so the Info.plist value stays "Typeflux".
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "Typeflux")
        XCTAssertEqual(plist["CFBundleName"] as? String, "Typeflux")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "Typeflux")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "ai.gulu.app.typeflux")
        XCTAssertEqual(plist["CFBundleDevelopmentRegion"] as? String, "en")
        try assertUsageDescriptionsNameClassic(
            plist,
            keys: ["NSMicrophoneUsageDescription", "NSAppleEventsUsageDescription", "NSSpeechRecognitionUsageDescription"]
        )
    }

    func testAppBundleLocalizesDisplayNameForEveryLanguage() throws {
        let localizations = ["en", "zh-Hans", "zh-Hant", "ja", "ko"]
        XCTAssertEqual(
            Set(localizations),
            Set(AppLanguage.allCases.compactMap { $0.bundleLocalizationCandidates.first }),
            "App bundle localizations must cover every supported app language"
        )

        for localization in localizations {
            let strings = try infoPlist(at: "app/\(localization).lproj/InfoPlist.strings")
            XCTAssertEqual(strings["CFBundleDisplayName"] as? String, Self.productName, localization)
            // The menu bar takes the application menu title from CFBundleName.
            XCTAssertEqual(strings["CFBundleName"] as? String, Self.productName, localization)
        }
    }

    func testEmbeddedInfoPlistUsageDescriptionsNameClassic() throws {
        let plist = try infoPlist(at: "Sources/Typeflux/Resources/Info.plist")
        try assertUsageDescriptionsNameClassic(
            plist,
            keys: ["NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription"]
        )
    }

    // MARK: - Helpers

    private func assertUsageDescriptionsNameClassic(_ plist: [String: Any], keys: [String]) throws {
        for key in keys {
            let value = try XCTUnwrap(plist[key] as? String, "Missing \(key)")
            XCTAssertTrue(value.hasPrefix(Self.productName + " "), "\(key): \(value)")
        }
    }

    private func matches(_ regex: NSRegularExpression, _ value: String) -> Bool {
        regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    private func localizedTable(for language: AppLanguage) throws -> [String: String] {
        let path = try XCTUnwrap(
            language.bundleLocalizationCandidates.compactMap {
                Bundle.module.path(forResource: $0, ofType: "lproj")
            }.first,
            "Missing bundle path for \(language.rawValue)"
        )
        let url = URL(fileURLWithPath: path).appendingPathComponent("Localizable.strings")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String]
        )
    }

    private func infoPlist(at relativePath: String) throws -> [String: Any] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )
    }
}
