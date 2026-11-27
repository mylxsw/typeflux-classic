import AppKit
import SwiftUI
import Testing
@testable import Typeflux

/// Renders the Classic account surfaces in native AppKit windows for every
/// account kind, login phase, appearance and language. Each case asserts its
/// layout; with `CLASSIC_UI_REVIEW_DIR` set it also writes the PNGs reviewed
/// for GUL-719.
@MainActor
@Suite("Classic account UI review", .serialized, .exclusiveUIState)
struct ClassicAccountUIReviewTests {
    enum Account: String, CaseIterable {
        case signedOut = "signed-out"
        case free
        case subscription
        case prepaid
        case exhausted
    }

    private let rendering = AccountViewRenderingTests()
    private static let schemes: [(String, ColorScheme)] = [("light", .light), ("dark", .dark)]

    // MARK: - Settings window

    @Test func settingsAccountPageForEveryAccountAppearanceAndLanguage() async throws {
        let previous = AppLocalization.shared.language
        defer { AppLocalization.shared.setLanguage(previous) }
        for language in AppLanguage.allCases {
            AppLocalization.shared.setLanguage(language)
            for account in Account.allCases {
                let auth = try await makeAuth(account)
                for (name, scheme) in Self.schemes {
                    let image = try await render(
                        settingsShell(auth: auth),
                        size: NSSize(width: StudioTheme.Layout.settingsWindowWidth, height: 1320),
                        scheme: scheme
                    )
                    try save(image, "settings/\(language.rawValue)/\(account.rawValue)-\(name).png")
                }
            }
        }
    }

    @Test func sidebarAccountCardForEveryAccount() async throws {
        for account in Account.allCases {
            let auth = try await makeAuth(account)
            for (name, scheme) in Self.schemes {
                let card = StudioSidebarAccountCard(
                    presentation: Self.sidebarPresentation(auth),
                    action: {},
                    identityAction: {}
                ) {
                    HStack { Spacer() }
                }
                .padding(StudioTheme.Insets.sidebarOuterHorizontal)
                .frame(width: StudioTheme.sidebarWidth)
                .background(StudioTheme.sidebar)
                let image = try await render(card, size: NSSize(width: StudioTheme.sidebarWidth, height: 220),
                                             scheme: scheme, fitHeight: true)
                try save(image, "sidebar/\(account.rawValue)-\(name).png")
            }
        }
    }

    // MARK: - Billing return

    @Test func billingReturnRefreshesTheAccountPage() async throws {
        let fixture = AccountViewRenderingTests.Fixture()
        fixture.subscription = AccountViewRenderingTests.snapshot(plan: "pro", status: "active", paid: true)
        fixture.credits = CloudCreditSummary(limit: 2000, used: 2000, remaining: 0, unlimited: false,
                                             addon: CloudAddonCredits(balance: 0, usedThisPeriod: 0, remaining: 0))
        let auth = rendering.makeAuth(fixture)
        await auth.refreshAccountSummary()
        #expect(auth.usageCredits?.canSpend == false)
        for (name, scheme) in Self.schemes {
            try save(try await render(settingsShell(auth: auth), size: Self.settingsSize, scheme: scheme),
                     "billing-return/before-\(name).png")
        }

        // The web billing page sends the user back through `typeflux://billing/return`.
        fixture.credits = CloudCreditSummary(limit: 2000, used: 2000, remaining: 0, unlimited: false,
                                             addon: CloudAddonCredits(balance: 500, usedThisPeriod: 0, remaining: 500))
        let returnURL = try #require(URL(string: "typeflux://billing/return"))
        await AppLoginURLRouter.handle(
            [returnURL], login: auth.webLoginCoordinator, isLoggedIn: { true }, showLogin: {},
            handleBilling: { await BillingReturnLink.handle(auth: auth) }
        )
        #expect(auth.usageCredits?.addonRemaining == 500)
        #expect(auth.usageCredits?.canSpend == true)
        for (name, scheme) in Self.schemes {
            try save(try await render(settingsShell(auth: auth), size: Self.settingsSize, scheme: scheme),
                     "billing-return/after-\(name).png")
        }
    }

    // MARK: - Onboarding

    @Test func onboardingAccountStepForEveryLoginPhase() async throws {
        let previous = AppLocalization.shared.language
        defer { AppLocalization.shared.setLanguage(previous) }
        for language in [AppLanguage.english, .simplifiedChinese] {
            AppLocalization.shared.setLanguage(language)
            for phase in LoginStep.allCases {
                let harness = LoginHarness()
                await harness.drive(to: phase)
                #expect(harness.matches(phase), "\(phase)")
                for (name, scheme) in Self.schemes {
                    let image = try await renderOnboarding(login: harness.coordinator, scheme: scheme)
                    try save(image, "onboarding/\(language.rawValue)/\(phase.rawValue)-\(name).png")
                }
                harness.coordinator.cancel()
            }
        }
    }

    @Test func onboardingAccountStepWhenSignedIn() async throws {
        let shared = AuthState.shared
        let previous = (shared.isLoggedIn, shared.userProfile)
        defer { shared.isLoggedIn = previous.0; shared.userProfile = previous.1 }
        shared.userProfile = UserProfile(id: "u", email: "gul719-free@gmail.com", name: "Free Fixture", status: 1,
                                         provider: "password", createdAt: "2026-11-01T00:00:00Z",
                                         updatedAt: "2026-11-01T00:00:00Z")
        shared.isLoggedIn = true
        for (name, scheme) in Self.schemes {
            let image = try await renderOnboarding(login: LoginHarness().coordinator, scheme: scheme)
            try save(image, "onboarding/en/succeeded-signed-in-\(name).png")
        }
    }

    // MARK: - Voice flow credits prompt

    @Test func voiceFlowCreditsPromptForEveryAccount() async throws {
        let quota = TypefluxCloudBillingError(reason: .quotaExceeded, serverMessage: nil)
        let cases: [(String, Bool, Bool)] = [
            ("free", false, true), ("member", true, true), ("billing-disabled", false, false)
        ]
        for (label, paid, billing) in cases {
            let prompt = CloudBillingPrompt(error: quota, hasPaidSubscription: paid, billingEnabled: billing)
            for (name, scheme) in Self.schemes {
                let overlay = OverlayController(appState: AppStateStore())
                overlay.showFailureWithActions(
                    title: prompt.title, message: prompt.message, tone: .billing,
                    actions: [
                        OverlayFailureAction(title: prompt.actionTitle, isRetry: false,
                                             trailingSystemImage: prompt.actionSymbol, handler: {}),
                        OverlayFailureAction(title: L("cloud.billing.action.switchModel"), isRetry: false,
                                             style: .text, handler: {})
                    ]
                )
                try await Task.sleep(for: .milliseconds(250))
                let panel = try #require(NSApp.windows.last { $0 is NSPanel && $0.level == .statusBar })
                panel.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                let content = try #require(panel.contentView)
                content.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                let image = try snapshot(content, backdrop: scheme == .dark ? .black : .white)
                #expect(image.size.height > 40)
                try save(image, "credits-prompt/\(label)-\(name).png")
                overlay.dismissImmediately()
            }
        }
    }

    // MARK: - Fixtures

    private static let settingsSize = NSSize(
        width: StudioTheme.Layout.settingsWindowWidth,
        height: StudioTheme.Layout.settingsWindowHeight
    )

    private func makeAuth(_ account: Account) async throws -> AuthState {
        let fixture = AccountViewRenderingTests.Fixture()
        let start = AccountViewRenderingTests.start
        let end = AccountViewRenderingTests.end
        switch account {
        case .signedOut:
            return rendering.makeAuth(fixture, signedIn: false)
        case .free:
            fixture.subscription = AccountViewRenderingTests.snapshot(plan: "free", status: "free", paid: false)
            fixture.credits = CloudCreditSummary(limit: 600, used: 128.42, remaining: 471.58, unlimited: false)
        case .subscription:
            fixture.subscription = AccountViewRenderingTests.snapshot(plan: "pro", status: "active", paid: true)
            fixture.credits = CloudCreditSummary(limit: 2000, used: 812.5, remaining: 1187.5, unlimited: false,
                                                 addon: CloudAddonCredits(balance: 300, usedThisPeriod: 20,
                                                                          remaining: 280))
        case .prepaid:
            fixture.subscription = BillingSubscriptionSnapshot(
                planCode: "pro", status: "active", currentPeriodStart: start, currentPeriodEnd: "2027-02-01T00:00:00Z",
                cancelAtPeriodEnd: false, entitled: true, active: true, paid: true, periodSource: "aidea",
                billingEnabled: true, billingMode: "prepaid", autoRenew: false
            )
            fixture.credits = CloudCreditSummary(limit: 2000, used: 83.88, remaining: 1916.12, unlimited: false,
                                                 addon: CloudAddonCredits(balance: 190, usedThisPeriod: 0,
                                                                          remaining: 190))
        case .exhausted:
            fixture.subscription = AccountViewRenderingTests.snapshot(plan: "free", status: "free", paid: false)
            fixture.credits = CloudCreditSummary(limit: 600, used: 600, remaining: 0, unlimited: false)
        }
        fixture.breakdown = CloudUsageBreakdown(
            periodStart: start, periodEnd: end, timezone: "UTC",
            days: account == .free ? [.init(date: "2026-10-03", voice: 40, rewrite: 8, ask: 0)] : [
                .init(date: "2026-10-02", voice: 120, rewrite: 30, ask: 12),
                .init(date: "2026-10-08", voice: 260, rewrite: 54, ask: 40),
                .init(date: "2026-10-15", voice: 180, rewrite: 22, ask: 0)
            ],
            voice: 560, rewrite: 106, ask: 52
        )
        let auth = rendering.makeAuth(fixture)
        await auth.refreshSubscription()
        await auth.refreshUsage()
        await auth.refreshUsageBreakdown()
        return auth
    }

    private static func sidebarPresentation(_ auth: AuthState) -> SidebarAccountCardPresentation {
        SidebarAccountCardPresentation.make(
            isLoggedIn: auth.isLoggedIn, subscription: auth.subscription, credits: auth.usageCredits,
            subscriptionError: auth.subscriptionError, usageError: auth.usageError,
            displayName: auth.userProfile?.resolvedDisplayName
        )
    }

    /// The Classic settings window as `SettingsView` composes it on the account page.
    private func settingsShell(auth: AuthState) -> some View {
        StudioShell(
            currentSection: .account, onSelect: { _ in }, onOpenAbout: {}, onSendDirectFeedback: {},
            onSendFeedbackEmail: {}, onOpenGitHubIssue: {}, onAccountAction: {},
            searchText: .constant(""), searchPlaceholder: "", isLoggedIn: auth.isLoggedIn,
            sidebarAccountPresentation: Self.sidebarPresentation(auth)
        ) { _ in
            VStack(alignment: .leading, spacing: StudioTheme.Spacing.heroSection) {
                StudioHeroHeader(
                    eyebrow: StudioSection.account.eyebrow,
                    title: StudioSection.account.heading,
                    subtitle: StudioSection.account.subheading
                )
                AccountView(authState: auth) {}
            }
        }
        .environment(\.locale, AppLocalization.shared.locale)
    }

    private func renderOnboarding(login: WebLoginCoordinator, scheme: ColorScheme) async throws -> NSImage {
        let suite = "gul719-onboarding-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OnboardingViewModel(settingsStore: SettingsStore(defaults: defaults), onComplete: {})
        model.currentStep = .account
        model.accountLogin = login
        let view = OnboardingView(viewModel: model, appearanceMode: scheme == .dark ? .dark : .light)
        return try await render(
            view,
            size: NSSize(width: OnboardingWindowController.windowWidth,
                         height: OnboardingWindowController.windowHeight),
            scheme: scheme
        )
    }

    // MARK: - Rendering

    private func render(_ view: some View, size: NSSize, scheme: ColorScheme,
                        fitHeight: Bool = false) async throws -> NSImage {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: AnyView(view.environment(\.colorScheme, scheme)))
        hosting.appearance = appearance
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = hosting
        defer { window.close() }
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        if fitHeight {
            let height = max(hosting.fittingSize.height, 40)
            window.setContentSize(NSSize(width: size.width, height: height))
            hosting.frame = NSRect(x: 0, y: 0, width: size.width, height: height)
        }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(60))
        // Window-sized roots fill their window; only content-sized views report a fitting height.
        #expect(!fitHeight || hosting.fittingSize.height > 40)
        #expect(hosting.bounds.width == size.width)
        return try snapshot(hosting, backdrop: nil)
    }

    private func snapshot(_ view: NSView, backdrop: NSColor?) throws -> NSImage {
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        guard let backdrop else { return image }
        let composed = NSImage(size: view.bounds.size)
        composed.lockFocus()
        backdrop.setFill()
        NSRect(origin: .zero, size: view.bounds.size).fill()
        image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        composed.unlockFocus()
        return composed
    }

    private func save(_ image: NSImage, _ relativePath: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["CLASSIC_UI_REVIEW_DIR"] else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }
}

/// Every phase the onboarding account step can show.
enum LoginStep: String, CaseIterable {
    case idle, creating, waiting, exchanging, cancelled, timeout, failed
}

/// A real `WebLoginCoordinator` with a scripted service and browser, driven
/// through the same transitions the website and the system URL callback cause.
@MainActor
final class LoginHarness {
    private final class API: WebLoginAPI {
        var create: () async throws -> WebLoginTransaction
        var exchange: () async throws -> LoginResponse = {
            try await Task.sleep(for: .seconds(600))
            throw CancellationError()
        }

        init(create: @escaping () async throws -> WebLoginTransaction) { self.create = create }
        func create(proof _: WebLoginProof) async throws -> WebLoginTransaction { try await create() }
        func exchange(code _: String, verifier _: String) async throws -> LoginResponse { try await exchange() }
    }

    private final class Browser: WebLoginBrowserSession {
        func start() -> Bool { true }
        func cancel() {}
    }

    static let opaque = String(repeating: "a", count: 43)
    static let proof = WebLoginProof(state: String(repeating: "s", count: 43), verifier: String(repeating: "v", count: 43))
    private let configuration = WebLoginConfiguration.resolve(
        environment: ["TYPEFLUX_WEB_AUTH_CHANNEL": "production"], info: [:]
    )
    private var expiresIn: TimeInterval = 600
    private lazy var api = API { [unowned self] in
        .init(transactionID: Self.opaque,
              loginURL: "https://typeflux.app/login?transaction=\(Self.opaque)",
              expiresAt: Date().timeIntervalSince1970 + expiresIn)
    }

    lazy var coordinator = WebLoginCoordinator(
        configuration: configuration, api: api, store: WebLoginMemoryStore(),
        browserFactory: { _, _, _ in Browser() }, makeProof: { Self.proof },
        authGeneration: { 0 }, accept: { _, _ in }
    )

    func drive(to step: LoginStep) async {
        switch step {
        case .idle:
            break
        case .creating:
            api.create = {
                try await Task.sleep(for: .seconds(600))
                throw CancellationError()
            }
            Task { await coordinator.start() }
            await waitUntil { coordinator.phase == .creating }
        case .waiting:
            await coordinator.start()
        case .exchanging:
            await coordinator.start()
            let callback = URL(string: "ai.gulu.app.typeflux://auth/callback?code=\(Self.opaque)&state=\(Self.proof.state)")!
            Task { await coordinator.receive(callback) }
            await waitUntil { coordinator.phase == .exchanging }
        case .cancelled:
            await coordinator.start()
            coordinator.cancel()
        case .timeout:
            // The transaction outlives its expiry without a browser callback.
            expiresIn = 1
            await coordinator.start()
            await waitUntil(seconds: 4) { coordinator.phase == .failed(.expired) }
        case .failed:
            api.create = { throw WebLoginFailure.networkUnavailable }
            await coordinator.start()
        }
    }

    func matches(_ step: LoginStep) -> Bool {
        switch step {
        case .idle: coordinator.phase == .idle
        case .creating: coordinator.phase == .creating
        case .waiting: coordinator.phase == .waiting
        case .exchanging: coordinator.phase == .exchanging
        case .cancelled: coordinator.phase == .cancelled
        case .timeout: coordinator.phase == .failed(.expired)
        case .failed: coordinator.phase == .failed(.networkUnavailable)
        }
    }

    private func waitUntil(seconds: Double = 2, _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
