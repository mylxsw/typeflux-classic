import AppKit
import Testing
@testable import Typeflux

@Suite("Release acceptance wording", .serialized, .exclusiveUIState)
@MainActor
struct ReleaseAcceptanceWordingTests {
    private static let expected: [(AppLanguage, String, String)] = [
        (AppLanguage.english, "Typeflux Classic Settings", " parameters"),
        (AppLanguage.simplifiedChinese, "Typeflux Classic 设置", " 参数"),
        (AppLanguage.traditionalChinese, "Typeflux Classic 設定", " 參數"),
        (AppLanguage.japanese, "Typeflux Classic 設定", " パラメータ"),
        (AppLanguage.korean, "Typeflux Classic 설정", " 파라미터"),
    ]

    @Test func settingsMenuItemNamesTheApp() {
        withEachLanguage { _, settings, _ in
            // Never the wording macOS uses for its own System Settings.
            #expect(L("menu.settings") == settings)
        }
    }

    @Test func localModelParameterCountIsLocalized() {
        withEachLanguage { _, _, unit in
            for model in LocalSTTModel.allCases {
                let specs = model.specs
                #expect(specs.parameterCountText == specs.parameterValue + unit)
            }
        }
    }

    @Test func applicationMenuNamesClassicInEveryLanguage() throws {
        _ = NSApplication.shared
        let previousMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMenu }
        try withEachLanguage { _, _, _ in
            AppMenuController.install()
            let menu = try #require(NSApp.mainMenu?.items.first?.submenu)
            for key in ["appMenu.about", "appMenu.hide", "appMenu.quit"] {
                #expect(menu.items.contains { $0.title == L(key, "Typeflux Classic") }, "\(key)")
            }
        }
    }

    private func withEachLanguage(_ body: (AppLanguage, String, String) throws -> Void) rethrows {
        let previous = AppLocalization.shared.language
        defer { AppLocalization.shared.setLanguage(previous) }
        for (language, settings, unit) in Self.expected {
            AppLocalization.shared.setLanguage(language)
            try body(language, settings, unit)
        }
    }
}
