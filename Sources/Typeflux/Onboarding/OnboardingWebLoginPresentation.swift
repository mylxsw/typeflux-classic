import Foundation

/// What the onboarding account step shows for one web login phase. Pure, so every
/// state of the browser transaction is testable without a window.
struct OnboardingWebLoginPresentation: Equatable {
    enum Action: Equatable {
        /// Opens the browser; `titleKey` distinguishes a first attempt from a retry.
        case start(titleKey: String)
        /// The browser owns the transaction; the app only waits for its callback.
        case waiting
        /// A request is in flight and nothing can be pressed.
        case working(messageKey: String)
    }

    enum Tone: Equatable {
        case neutral
        case error
    }

    struct Status: Equatable {
        let messageKey: String
        let tone: Tone
    }

    let action: Action
    let status: Status?

    init(phase: WebLoginCoordinator.Phase) {
        switch phase {
        case .idle, .succeeded:
            action = .start(titleKey: "auth.web.continue")
            status = nil
        case .creating:
            action = .working(messageKey: "auth.web.waiting")
            status = nil
        case .waiting:
            action = .waiting
            status = nil
        case .exchanging:
            action = .working(messageKey: "auth.web.exchanging")
            status = nil
        case .cancelled:
            action = .start(titleKey: "auth.web.continue")
            status = Status(messageKey: "auth.web.cancelled", tone: .neutral)
        case let .failed(failure):
            action = .start(titleKey: "auth.web.retry")
            status = Status(messageKey: failure.localizationKey, tone: .error)
        }
    }
}
