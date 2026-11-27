import AppKit
import SwiftUI
import Testing
@testable import Typeflux

@MainActor
@Suite(.serialized, .exclusiveUIState)
struct ClassicAccountIntegrationTests {
    @Test func singleProcessOwnsHostAndSettings() {
        #expect(!FeatureProcess.enabled)
        #expect(FeatureProcess.role == .host)
        #expect(FeatureProcess.owns(.host))
        #expect(FeatureProcess.owns(.settings))
        #expect(!ClassicAccountOnboarding.hasActiveSession)
        #expect(ClassicAccountOnboarding.activeLogin == nil)
        #expect(!ClassicAccountOnboarding.presentInlineLogin())
    }

    @Test func registryCloudSelectionWinsOverLegacySettings() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.llmRemoteProvider = .openAI
        defaults.set("test:cloud", forKey: "llm.profile.reference")
        let registry = #"{"version":2,"providers":[{"remote":"typefluxCloud","models":[{"reference":"test:cloud"}]}]}"#
        defaults.set(Data(registry.utf8), forKey: "models.registry.v2")
        #expect(settings.usesCloudRewriteForAccountDefaults)
        defaults.set("missing", forKey: "llm.profile.reference")
        #expect(!settings.usesCloudRewriteForAccountDefaults)
    }

    @Test func accountPageStatesRenderInBothAppearances() async throws {
        let helper = AccountViewRenderingTests()
        for state in ["free", "pro", "signed-out", "loading", "error"] {
            let fixture = AccountViewRenderingTests.Fixture()
            let paid = state == "pro"
            fixture.subscription = AccountViewRenderingTests.snapshot(
                plan: paid ? "pro" : "free", status: paid ? "active" : "free", paid: paid
            )
            fixture.credits = AccountViewRenderingTests.credits(18.25)
            let auth = helper.makeAuth(fixture, signedIn: !["signed-out", "loading"].contains(state))
            await auth.refreshSubscription()
            await auth.refreshUsage()
            auth.isLoading = state == "loading"
            for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                let view = AccountView(authState: auth) {}
                    .padding(24)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme)
                let host = try await helper.host(view, width: 900)
                if state == "error" {
                    auth.usageError = "The local test server is unavailable."
                    await Task.yield()
                }
                host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                host.frame.size.height = host.fittingSize.height
                #expect(host.bounds.height > 100)
                if let directory = ProcessInfo.processInfo.environment["CLASSIC_ACCOUNT_SNAPSHOTS"] {
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let png = try #require(bitmap.representation(using: .png, properties: [:]))
                    let file = URL(fileURLWithPath: directory).appendingPathComponent("\(state)-\(name).png")
                    try png.write(to: file)
                }
            }
        }
    }
}
