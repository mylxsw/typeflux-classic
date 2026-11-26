import Foundation
@testable import Typeflux
import XCTest

final class ClassicCompatibilityContractTests: XCTestCase {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/ClassicContract", isDirectory: true)
    private let sampleID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    private let registryKey = "models.registry.v2"
    private let referenceKey = "llm.profile.reference"

    func testImportsAllFourModelSelections() throws {
        let cases: [(String, SettingsStore.RewriteModelSelection?)] = [
            ("defaults", .remote(.openAI, model: "gpt-4o-mini")),
            ("defaults-cloud", .cloud),
            ("defaults-ollama", .ollama(model: "qwen3:8b")),
            ("defaults-endpoint", nil)
        ]
        for (fixture, selection) in cases {
            try withSettings(fixture) { settings, suite, fixtureValues in
                settings.llmProvider = .openAICompatible
                settings.llmRemoteProvider = .gemini
                settings.llmModel = "classic-model"
                let before = try XCTUnwrap(settings.defaults.persistentDomain(forName: suite))
                XCTAssertEqual(settings.importSharedRewriteModelSelection(), selection != nil, fixture)
                XCTAssertEqual(settings.rewriteModelSelection, selection ?? .remote(.gemini, model: "classic-model"))
                let after = try XCTUnwrap(settings.defaults.persistentDomain(forName: suite))
                for (key, value) in fixtureValues {
                    XCTAssertEqual(after[key] as? NSObject, value as? NSObject, key)
                }
                XCTAssertEqual(after["llm.model"] as? String, "classic-model")
                if selection == nil {
                    XCTAssertEqual(after as NSDictionary, before as NSDictionary)
                }
            }
        }
    }

    func testMissingEmptyAndUnresolvableReferencesPreserveClassicPreferences() throws {
        try withSettings("v0.4.0-defaults") { settings, suite, _ in
            for (reference, expected) in [(nil, true), ("", true), ("unknown", false)] as [(String?, Bool)] {
                settings.defaults.set(reference, forKey: referenceKey)
                let before = try XCTUnwrap(settings.defaults.persistentDomain(forName: suite))
                XCTAssertEqual(settings.importSharedRewriteModelSelection(), expected)
                let after = try XCTUnwrap(settings.defaults.persistentDomain(forName: suite))
                XCTAssertEqual(after as NSDictionary, before as NSDictionary)
            }
            settings.defaults.set("cloud:default", forKey: referenceKey)
            XCTAssertTrue(settings.importSharedRewriteModelSelection())
            XCTAssertEqual(settings.rewriteModelSelection, .cloud)
        }
    }

    func testRegistryReadsKnownFieldsAndRejectsUnsupportedProviders() throws {
        try withSettings("defaults") { settings, _, _ in
            let registry = Data("""
            {"version":2,"providers":[
                {"id":"endpoint:test","remote":"openAI","models":[{"reference":"endpoint","id":"test"}]},
                {"id":"custom","remote":"custom","models":[{"reference":"custom","id":"test"}]},
                {"id":"future","remote":"future","models":[{"reference":"future","id":"test"}]},
                {"id":"openAI","remote":"openAI","models":[{"reference":"invalid","id":""}]},
                {"id":"typefluxCloud","remote":"typefluxCloud","models":[null,
                    {"reference":"cloud:catalog","id":"catalog","pricing":{"v3":[1]}}]}
            ]}
            """.utf8)
            settings.defaults.set(registry, forKey: registryKey)
            for reference in ["endpoint", "custom", "future", "invalid", "missing"] {
                settings.defaults.set(reference, forKey: referenceKey)
                XCTAssertFalse(settings.importSharedRewriteModelSelection(), reference)
            }
            settings.defaults.set("cloud:catalog", forKey: referenceKey)
            XCTAssertTrue(settings.importSharedRewriteModelSelection())
            XCTAssertEqual(settings.rewriteModelSelection, .cloud)
            XCTAssertEqual(settings.defaults.data(forKey: registryKey), registry)

            settings.defaults.set(Data("{\"version\":3,\"providers\":[]}".utf8), forKey: registryKey)
            XCTAssertFalse(settings.importSharedRewriteModelSelection())
            settings.defaults.set(Data("invalid JSON".utf8), forKey: registryKey)
            XCTAssertFalse(settings.importSharedRewriteModelSelection())
        }
    }

    func testExportsOnlyMatchingActiveModelsAndPreservesFullVersionData() throws {
        try withSettings("defaults-endpoint") { settings, suite, fixtureValues in
            XCTAssertFalse(settings.importSharedRewriteModelSelection())
            settings.llmRemoteProvider = .typefluxCloud
            var previous = settings.rewriteModelSelection
            settings.setLLMModel("qwen3:8b", for: .gemini)
            settings.exportSharedRewriteModelSelection(ifChangedFrom: previous)
            XCTAssertEqual(settings.defaults.string(forKey: referenceKey), "custom:fixture-endpoint")

            settings.llmRemoteProvider = .openAI
            settings.llmModel = "gpt-4o-mini"
            settings.exportSharedRewriteModelSelection(ifChangedFrom: previous)
            XCTAssertEqual(settings.defaults.string(forKey: referenceKey), "custom:fixture-openai")

            previous = settings.rewriteModelSelection
            settings.llmProvider = .ollama
            settings.ollamaModel = "qwen3:8b"
            settings.exportSharedRewriteModelSelection(ifChangedFrom: previous)
            XCTAssertEqual(settings.defaults.string(forKey: referenceKey), "custom:fixture-ollama")

            previous = settings.rewriteModelSelection
            settings.llmProvider = .openAICompatible
            settings.llmRemoteProvider = .typefluxCloud
            settings.exportSharedRewriteModelSelection(ifChangedFrom: previous)
            XCTAssertEqual(settings.defaults.string(forKey: referenceKey), "cloud:default")

            previous = settings.rewriteModelSelection
            settings.llmRemoteProvider = .gemini
            settings.llmModel = "gpt-4o-mini"
            settings.exportSharedRewriteModelSelection(ifChangedFrom: previous)
            XCTAssertNil(settings.defaults.object(forKey: referenceKey))
            XCTAssertEqual(settings.defaults.string(forKey: "llm.remote.gemini.model"), "gpt-4o-mini")

            let after = try XCTUnwrap(settings.defaults.persistentDomain(forName: suite))
            for (key, value) in fixtureValues where key != referenceKey {
                XCTAssertEqual(after[key] as? NSObject, value as? NSObject, key)
            }
        }
    }

    @MainActor
    func testCloudDefaultsAfterLoginExportOnce() async throws {
        let (store, suite, _) = try Self.makeFixtureSettings("defaults")
        defer { store.defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(store.importSharedRewriteModelSelection())
        let observer = store.observeCloudRewriteModelDefaults()
        defer { NotificationCenter.default.removeObserver(observer) }

        let defaultsApplied = expectation(description: "Cloud defaults applied after login")
        let prompt = AcceptCloudDefaults { defaultsApplied.fulfill() }
        let coordinator = CloudLoginSyncCoordinator(
            settingsStore: store,
            promptPresenter: prompt,
            hasPaidCloudSubscription: { true }
        )
        let auth = AuthState(loadStoredToken: { nil }, loadStoredRefreshToken: { nil }, loadStoredUserProfile: { nil })
        NotificationCenter.default.post(name: .authDidLogin, object: auth)
        await fulfillment(of: [defaultsApplied], timeout: 2)
        XCTAssertEqual(store.defaults.string(forKey: referenceKey), "cloud:default")

        // An STT-only change can emit the same notification without changing the rewrite selection.
        // Classic keeps a Typeflux-only reference when the local rewrite model did not change.
        prompt.onApplied = {}
        store.defaults.set("custom:fixture-endpoint", forKey: referenceKey)
        XCTAssertFalse(store.importSharedRewriteModelSelection())
        store.sttProvider = .appleSpeech
        coordinator.offerCloudDefaultsIfNeeded()
        XCTAssertEqual(store.sttProvider, .typefluxOfficial)
        XCTAssertEqual(store.defaults.string(forKey: referenceKey), "custom:fixture-endpoint")
    }

    func testReadsPersonaAndActivationHotkeyUsingClassicSettingsStore() throws {
        try withSettings("defaults") { settings, _, _ in
            settings.personasJSON = try String(
                contentsOf: Self.fixtures.appendingPathComponent("personas.json"), encoding: .utf8
            )
            settings.activationHotkeyJSON = try String(
                contentsOf: Self.fixtures.appendingPathComponent("hotkey.json"), encoding: .utf8
            )
            let persona = try XCTUnwrap(settings.personas.first { $0.id == sampleID })
            XCTAssertEqual(persona.name, "Classic")
            XCTAssertEqual(persona.prompt, "Polish dictated text.")
            let hotkey = try XCTUnwrap(settings.activationHotkey)
            XCTAssertEqual(hotkey.id, sampleID)
            XCTAssertEqual(hotkey.keyCode, 56)
            XCTAssertEqual(hotkey.modifierFlags, 8_519_680)
            XCTAssertEqual(hotkey.pressCount, 2)
            XCTAssertEqual(hotkey.modifierKeyCodes, [56, 63])
        }

        let vocabulary = try JSONDecoder().decode(
            [VocabularyEntry].self, from: Data(contentsOf: Self.fixtures.appendingPathComponent("vocabulary.json"))
        )
        XCTAssertEqual(vocabulary.first?.term, "Typeflux")
        XCTAssertEqual(vocabulary.first?.occurrenceCount, 3)
    }

    func testReadsHistoryThroughClassicSQLiteStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let filename = "history.sqlite"
        try FileManager.default.copyItem(
            at: Self.fixtures.appendingPathComponent(filename), to: directory.appendingPathComponent(filename)
        )
        let store = SQLiteHistoryStore(baseDir: directory)
        let record = try XCTUnwrap(store.record(id: sampleID))
        XCTAssertEqual(record.transcriptText, "Classic history fixture")
        XCTAssertEqual(record.date, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(record.mode, .dictation)
    }

    private func withSettings(
        _ fixture: String, body: (SettingsStore, String, [String: Any]) throws -> Void
    ) throws {
        let (store, suite, values) = try Self.makeFixtureSettings(fixture)
        defer { store.defaults.removePersistentDomain(forName: suite) }
        try body(store, suite, values)
    }

    static func makeFixtureSettings(_ fixture: String) throws -> (
        store: SettingsStore, suite: String, values: [String: Any]
    ) {
        let file = fixtures.appendingPathComponent(fixture + ".plist")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil)
        let values = try XCTUnwrap(plist as? [String: Any])
        let suite = "ClassicCompatibilityContractTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.setPersistentDomain(values, forName: suite)
        return (SettingsStore(defaults: defaults), suite, values)
    }
}

@MainActor
private final class AcceptCloudDefaults: CloudModelDefaultsPrompting {
    var onApplied: () -> Void

    init(onApplied: @escaping () -> Void) {
        self.onApplied = onApplied
    }

    func confirmSwitchToCloudDefaults() -> Bool { true }
    func showCloudDefaultsApplied() { onApplied() }
    func confirmSwitchToCloudLLMDefault() -> Bool { true }
    func showCloudLLMDefaultApplied() { onApplied() }
}
