import Foundation
import OpenCCSwift
import XCTest

final class LocalizationReleaseTests: XCTestCase {
    private typealias Strings = [String: String]

    private struct Allowance {
        let reason: String
        let keys: [String]
        var languages: [String] = ["ja", "ko", "zh-Hans", "zh-Hant"]
        var table = "Localizable.strings"
    }

    private struct Entry: Hashable {
        let table: String
        let language: String
        let key: String

        var path: String { "\(language).lproj/\(table): \(key)" }
    }

    private let languages = ["ja", "ko", "zh-Hans", "zh-Hant"]
    private let nativeScript = #"[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]"#
    private let englishPhrase = #"(?:\b[A-Za-z]{2,}\b[ ,]+){3}\b[A-Za-z]{2,}\b"#

    func testLocalizedTablesMatchEnglishWithoutUntranslatedCopy() throws {
        let allowances = Self.englishAllowances.flatMap { allowance in
            XCTAssertFalse(allowance.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            return allowance.keys.flatMap { key in
                allowance.languages.map { Entry(table: allowance.table, language: $0, key: key) }
            }
        }
        let allowed = Set(allowances)
        XCTAssertEqual(allowed.count, allowances.count, "Duplicate English allowances")
        var identical = Set<Entry>()

        try forEachLocalizedTable { table, language, english, localized in
            let context = "\(language).lproj/\(table)"
            XCTAssertEqual(Set(localized.keys), Set(english.keys), "Mismatched keys in \(context)")
            for (key, value) in localized {
                let entry = Entry(table: table, language: language, key: key)
                if value == english[key] {
                    identical.insert(entry)
                } else if value.range(of: nativeScript, options: .regularExpression) == nil {
                    XCTAssertNil(value.range(of: englishPhrase, options: .regularExpression),
                                 "Possible outdated English copy at \(entry.path)")
                }
            }
        }

        XCTAssertEqual(identical.subtracting(allowed).map(\.path).sorted(), [],
                       "Translate these entries or document why the English value is intentional")
        XCTAssertEqual(allowed.subtracting(identical).map(\.path).sorted(), [],
                       "Remove allowances for entries that no longer match English")
    }

    func testTraditionalChineseHasNoSimplifiedOnlyCharacters() throws {
        let converter = try Presets.Cn2t.converter(from: "cn", to: "tw")
        // These characters also have valid uses in Taiwan, such as 里 in 阿里雲.
        let sharedCharacters: Set<Character> = ["里", "台", "占", "游"]
        var checked = Set<Character>()
        var simplified = Set<Character>()

        try forEachLocalizedTable { table, language, _, localized in
            guard language == "zh-Hant" else { return }
            for (key, value) in localized {
                let characters = Set(value).subtracting(sharedCharacters)
                for character in characters where checked.insert(character).inserted {
                    let text = String(character)
                    if text.range(of: #"\p{Han}"#, options: .regularExpression) != nil,
                       converter.convert(text) != text {
                        simplified.insert(character)
                    }
                }
                let invalid = characters.intersection(simplified).sorted()
                XCTAssertTrue(invalid.isEmpty, "\(language).lproj/\(table): \(key) contains \(String(invalid))")
            }
        }
    }

    private func forEachLocalizedTable(
        _ check: (String, String, Strings, Strings) throws -> Void
    ) throws {
        // InfoPlist.strings is packaged by the app build, outside the SwiftPM resource bundle.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for (directory, requiredTable) in [
            ("Sources/Typeflux/Resources", "Localizable.strings"),
            ("app", "InfoPlist.strings")
        ] {
            let resources = root.appendingPathComponent(directory)
            let englishDirectory = resources.appendingPathComponent("en.lproj")
            let englishTables = try tables(in: englishDirectory)
            XCTAssertTrue(englishTables.contains(requiredTable), "Missing \(directory)/en.lproj/\(requiredTable)")
            let english = try englishTables.reduce(into: [String: Strings]()) { result, name in
                result[name] = try strings(in: englishDirectory, table: name)
            }
            for language in languages {
                let localizedDirectory = resources.appendingPathComponent("\(language).lproj")
                let localizedTables = try tables(in: localizedDirectory)
                XCTAssertEqual(localizedTables, englishTables, "Mismatched tables in \(localizedDirectory.path)")
                for name in englishTables.intersection(localizedTables).sorted() {
                    let baseline = try XCTUnwrap(english[name])
                    try check(name, language, baseline, strings(in: localizedDirectory, table: name))
                }
            }
        }
    }

    private func tables(in directory: URL) throws -> Set<String> {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return Set(urls.filter { $0.pathExtension == "strings" }.map(\.lastPathComponent))
    }

    private func strings(in directory: URL, table: String) throws -> Strings {
        let url = directory.appendingPathComponent(table)
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try XCTUnwrap(plist as? Strings, "Invalid strings table at \(url.path)")
    }

    private static let englishAllowances: [Allowance] = [
        Allowance(
            reason: "Language picker shows each language in its own name.",
            keys: [
                "language.option.english",
                "language.option.traditionalChinese",
                "language.option.japanese",
                "language.option.korean",
            ]
        ),
        Allowance(
            reason: "Language picker shows each language in its own name.",
            keys: [
                "language.option.simplifiedChinese",
            ],
            languages: ["ja", "ko", "zh-Hans"]
        ),
        Allowance(
            reason: "Apple's name for the material.",
            keys: [
                "overlayStyle.liquidGlass",
            ]
        ),
        Allowance(
            reason: "Product name.",
            keys: [
                "window.voiceStudio",
                "sidebar.appName",
                "sidebar.accountCard.cloudAccount",
                "studio.eyebrow.home",
                "about.appName",
                "provider.stt.typefluxOfficial",
                "provider.llm.typefluxCloud",
                "notification.localModelReady.title",
            ]
        ),
        Allowance(
            reason: "Only placeholders, units, symbols or key glyphs; nothing to translate.",
            keys: [
                "sidebar.accountCard.usagePair",
                "auth.account.usageQuotaRemainingPair",
            ]
        ),
        Allowance(
            reason: "Only placeholders, units, symbols or key glyphs; nothing to translate.",
            keys: [
                "settings.servers.option.latency",
            ],
            languages: ["ja", "ko"]
        ),
        Allowance(
            reason: "OK is the standard button label in Japanese.",
            keys: [
                "common.ok",
            ],
            languages: ["ja"]
        ),
        Allowance(
            reason: "Credential field name as shown in the provider console; the surrounding translated copy uses the same term.",
            keys: [
                "common.apiKey",
                "settings.models.doubao.appID",
                "settings.models.doubao.resourceID",
                "settings.models.doubao.accessToken",
            ],
            languages: ["zh-Hans", "zh-Hant"]
        ),
        Allowance(
            reason: "Brand, product, service or model name.",
            keys: [
                "provider.stt.whisperAPI",
                "provider.stt.appleSpeech",
                "provider.stt.groq",
                "provider.stt.soniox",
                "provider.llm.openRouter",
                "downloadSource.modelScope",
                "downloadSource.huggingFace",
                "localSTT.whisperLocal.name",
                "localSTT.whisperLocalLarge.name",
                "localSTT.qwen3ASR.name",
                "vocabulary.source.claude",
                "vocabulary.source.codex",
            ]
        ),
        Allowance(
            reason: "Brand, product, service or model name.",
            keys: [
                "provider.stt.aliCloud",
            ],
            languages: ["ja"]
        ),
        Allowance(
            reason: "Brand, product, service or model name.",
            keys: [
                "provider.stt.googleCloud",
            ],
            languages: ["ja", "ko"]
        ),
        Allowance(
            reason: "Model parameter count or download size.",
            keys: [
                "localSTT.whisperLocal.parameterValue",
                "localSTT.whisperLocal.sizeValue",
                "localSTT.whisperLocalLarge.parameterValue",
                "localSTT.whisperLocalLarge.sizeValue",
                "localSTT.senseVoiceSmall.parameterValue",
                "localSTT.senseVoiceSmall.sizeValue",
                "localSTT.qwen3ASR.parameterValue",
                "localSTT.qwen3ASR.sizeValue",
                "localSTT.funASR.parameterValue",
                "localSTT.funASR.sizeValue",
            ]
        ),
        Allowance(
            reason: "Brand, product, service or model name.",
            keys: [
                "localSTT.senseVoiceSmall.name",
            ],
            languages: ["zh-Hans", "zh-Hant"]
        ),
        Allowance(
            reason: "Technical abbreviation used as-is.",
            keys: [
                "modelDomain.llm.title",
            ],
            languages: ["ja", "ko"]
        ),
        Allowance(
            reason: "Only placeholders, units, symbols or key glyphs; nothing to translate.",
            keys: [
                "history.stats.durationMillisecondsFormat",
            ],
            languages: ["zh-Hans", "zh-Hant"]
        ),
        Allowance(
            reason: "Only placeholders, units, symbols or key glyphs; nothing to translate.",
            keys: [
                "history.stats.durationSecondsFormat",
            ],
            languages: ["ja", "zh-Hans", "zh-Hant"]
        ),
        Allowance(
            reason: "Technical abbreviation used as-is.",
            keys: [
                "history.race.llm",
                "settings.models.badge.api",
            ]
        ),
        Allowance(
            reason: "Intentionally empty shortcut footnotes.",
            keys: [
                "settings.shortcuts.activation.footnote",
                "settings.shortcuts.ask.footnote",
                "settings.shortcuts.persona.footnote",
                "settings.shortcuts.history.footnote",
                "settings.shortcuts.auxiliary.footnote",
            ]
        ),
        Allowance(
            reason: "API method name.",
            keys: [
                "settings.models.googleCloud.streaming",
            ]
        ),
        Allowance(
            reason: "Credential field name as shown in the provider console; the surrounding translated copy uses the same term.",
            keys: [
                "settings.models.googleCloud.projectID",
            ]
        ),
        Allowance(
            reason: "Physical key legends.",
            keys: [
                "onboarding.shortcuts.replacement.fn",
            ]
        ),
        Allowance(
            reason: "Name of the markup format.",
            keys: [
                "agent.jobs.detail.result.view.markdown",
            ]
        ),
        Allowance(
            reason: "Subscription plan name, also kept in the translated sentences that mention it.",
            keys: [
                "auth.account.subscriptionFreePlan",
                "auth.account.subscriptionDefaultPlan",
                "auth.account.subscriptionStatusFree",
            ]
        ),
        Allowance(reason: "Product name shown by macOS.", keys: ["CFBundleDisplayName"], table: "InfoPlist.strings")
    ]
}
