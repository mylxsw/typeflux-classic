import Foundation

/// The voice-flow overlay shown when Typeflux Cloud refuses a request for billing.
/// Wraps the shared `TypefluxCloudBillingError` copy and adds Classic's purchase
/// entry: a paid member who ran out of credits can buy an add-on pack directly.
struct CloudBillingPrompt: Equatable {
    enum Destination: Equatable {
        /// The Classic account page (usage, plan, receipts).
        case account
        /// The web billing page on the given tab; nil opens the plans.
        case billing(tab: String?)
    }

    let title: String
    let message: String
    let actionTitle: String
    let actionSymbol: String
    let destination: Destination

    init(error: TypefluxCloudBillingError, hasPaidSubscription: Bool, billingEnabled: Bool) {
        if error.reason == .quotaExceeded, hasPaidSubscription, billingEnabled {
            title = error.title(hasPaidSubscription: true, billingEnabled: true)
            message = L("cloud.billing.paidQuotaExceeded.body")
            actionTitle = L("cloud.billing.action.buyCredits")
            actionSymbol = "cart"
            destination = .billing(tab: BillingPlansLink.creditsTab)
            return
        }

        title = error.title(hasPaidSubscription: hasPaidSubscription, billingEnabled: billingEnabled)
        message = error.message(hasPaidSubscription: hasPaidSubscription, billingEnabled: billingEnabled)
        actionTitle = error.primaryActionTitle(hasPaidSubscription: hasPaidSubscription, billingEnabled: billingEnabled)
        actionSymbol = "arrow.up.right"
        switch error.primaryAction(hasPaidSubscription: hasPaidSubscription, billingEnabled: billingEnabled) {
        case .openAccount:
            destination = .account
        case .openPlans:
            destination = .billing(tab: nil)
        }
    }
}
