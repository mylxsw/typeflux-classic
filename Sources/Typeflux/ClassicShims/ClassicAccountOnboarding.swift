import Foundation

@MainActor
enum ClassicAccountOnboarding: AccountOnboardingProvider {
    static weak var activeModel: OnboardingViewModel?
    static var hasActiveSession: Bool { activeModel != nil }
    static var activeLogin: WebLoginCoordinator? { activeModel?.accountLogin }

    static func presentInlineLogin() -> Bool {
        guard let model = activeModel else { return false }
        model.currentStep = .account
        let coordinator = model.accountLogin
        if coordinator.phase == .waiting {
            coordinator.reopen()
        } else if !coordinator.isBusy {
            Task { await coordinator.start() }
        }
        return true
    }
}
