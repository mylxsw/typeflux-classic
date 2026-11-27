@testable import Typeflux
import XCTest

final class OnboardingWebLoginPresentationTests: XCTestCase {
    func testIdleStartsBrowserLogin() {
        let presentation = OnboardingWebLoginPresentation(phase: .idle)

        XCTAssertEqual(presentation.action, .start(titleKey: "auth.web.continue"))
        XCTAssertNil(presentation.status)
    }

    func testCreatingShowsProgressWithoutActions() {
        let presentation = OnboardingWebLoginPresentation(phase: .creating)

        XCTAssertEqual(presentation.action, .working(messageKey: "auth.web.waiting"))
        XCTAssertNil(presentation.status)
    }

    func testWaitingOffersReopenAndCancel() {
        XCTAssertEqual(OnboardingWebLoginPresentation(phase: .waiting).action, .waiting)
    }

    func testExchangingShowsCompletion() {
        let presentation = OnboardingWebLoginPresentation(phase: .exchanging)

        XCTAssertEqual(presentation.action, .working(messageKey: "auth.web.exchanging"))
    }

    func testCancelledCanStartAgain() {
        let presentation = OnboardingWebLoginPresentation(phase: .cancelled)

        XCTAssertEqual(presentation.action, .start(titleKey: "auth.web.continue"))
        XCTAssertEqual(presentation.status, .init(messageKey: "auth.web.cancelled", tone: .neutral))
    }

    func testTimeoutOffersRetry() {
        let presentation = OnboardingWebLoginPresentation(phase: .failed(.expired))

        XCTAssertEqual(presentation.action, .start(titleKey: "auth.web.retry"))
        XCTAssertEqual(presentation.status, .init(messageKey: "auth.web.expired", tone: .error))
    }

    func testFailureShowsItsMessageAndRetry() {
        let presentation = OnboardingWebLoginPresentation(phase: .failed(.networkUnavailable))

        XCTAssertEqual(presentation.action, .start(titleKey: "auth.web.retry"))
        XCTAssertEqual(presentation.status, .init(messageKey: "auth.web.networkUnavailable", tone: .error))
    }

    func testSucceededFallsBackToStartWhenSignedOutAgain() {
        let presentation = OnboardingWebLoginPresentation(phase: .succeeded)

        XCTAssertEqual(presentation.action, .start(titleKey: "auth.web.continue"))
        XCTAssertNil(presentation.status)
    }
}
