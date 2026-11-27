@testable import Typeflux
import XCTest

final class CloudBillingPromptTests: XCTestCase {
    private let quota = TypefluxCloudBillingError(reason: .quotaExceeded, serverMessage: nil)
    private let subscription = TypefluxCloudBillingError(reason: .subscriptionRequired, serverMessage: nil)

    func testPaidMemberOutOfCreditsCanBuyAddonCredits() {
        let prompt = CloudBillingPrompt(error: quota, hasPaidSubscription: true, billingEnabled: true)

        XCTAssertEqual(prompt.destination, .billing(tab: BillingPlansLink.creditsTab))
        XCTAssertEqual(prompt.title, L("cloud.billing.quotaExceeded.title"))
        XCTAssertEqual(prompt.message, L("cloud.billing.paidQuotaExceeded.body"))
        XCTAssertEqual(prompt.actionTitle, L("cloud.billing.action.buyCredits"))
        XCTAssertEqual(prompt.actionSymbol, "cart")
    }

    func testFreeAccountOutOfCreditsUpgradesPlan() {
        let prompt = CloudBillingPrompt(error: quota, hasPaidSubscription: false, billingEnabled: true)

        XCTAssertEqual(prompt.destination, .billing(tab: nil))
        XCTAssertEqual(prompt.title, L("cloud.billing.freePlanQuotaExceeded.title"))
        XCTAssertEqual(prompt.message, L("cloud.billing.freePlanQuotaExceeded.body"))
        XCTAssertEqual(prompt.actionTitle, L("cloud.billing.action.upgradePlan"))
        XCTAssertEqual(prompt.actionSymbol, "arrow.up.right")
    }

    func testMissingSubscriptionOpensPlans() {
        let prompt = CloudBillingPrompt(error: subscription, hasPaidSubscription: false, billingEnabled: true)

        XCTAssertEqual(prompt.destination, .billing(tab: nil))
        XCTAssertEqual(prompt.actionTitle, L("cloud.billing.action.subscribe"))
    }

    func testDisabledBillingOnlyOpensAccount() {
        for paid in [true, false] {
            let prompt = CloudBillingPrompt(error: quota, hasPaidSubscription: paid, billingEnabled: false)

            XCTAssertEqual(prompt.destination, .account)
            XCTAssertEqual(prompt.title, L("cloud.billing.freeQuotaExceeded.title"))
            XCTAssertEqual(prompt.actionTitle, L("cloud.billing.action.openAccount"))
        }
    }

    func testNewKeysAreLocalizedInEveryLanguage() throws {
        let keys = ["cloud.billing.action.buyCredits", "cloud.billing.paidQuotaExceeded.body"]
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Typeflux/Resources")
        for language in ["en", "zh-Hans", "zh-Hant", "ja", "ko"] {
            let url = root.appendingPathComponent("\(language).lproj/Localizable.strings")
            let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], language)
            for key in keys {
                XCTAssertFalse(table[key]?.isEmpty ?? true, "\(language) is missing \(key)")
            }
        }
    }
}
