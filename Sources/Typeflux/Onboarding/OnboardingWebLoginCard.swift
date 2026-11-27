import SwiftUI

/// The onboarding account step's sign-in: the Typeflux website handles every
/// credential, so the app only starts, follows and retries the browser transaction.
struct OnboardingWebLoginCard: View {
    @ObservedObject var coordinator: WebLoginCoordinator
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.colorScheme) private var colorScheme
    /// The login that other entries (sidebar, settings) would have started.
    let sharedLogin: WebLoginCoordinator?
    let onSucceeded: () -> Void

    private var presentation: OnboardingWebLoginPresentation {
        OnboardingWebLoginPresentation(phase: coordinator.phase)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                TypefluxLogoBadge(size: 40, symbolSize: 20, backgroundShape: .circle, showsBorder: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L("auth.login.windowTitle"))
                        .font(.studioDisplay(18, weight: .bold))
                        .foregroundStyle(StudioTheme.textPrimary)
                    if let status = presentation.status {
                        Text(L(status.messageKey))
                            .font(.studioBody(12))
                            .foregroundStyle(status.tone == .error ? StudioTheme.danger : StudioTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("onboardingWebLoginStatus")
                    }
                }

                Spacer(minLength: 0)
            }

            actionRow
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.045) : StudioTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.05) : StudioTheme.border, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.18), value: coordinator.phase)
        .onChange(of: coordinator.phase) { phase in
            if phase == .succeeded { onSucceeded() }
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        switch presentation.action {
        case let .start(titleKey):
            Button(action: start) {
                HStack(spacing: 8) {
                    Text(L(titleKey))
                    Image(systemName: "arrow.up.right")
                }
                .font(.studioBody(13, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Capsule(style: .continuous).fill(StudioTheme.accent))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(StudioInteractiveButtonStyle())
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("onboardingWebLoginStart")
        case .waiting:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(L("auth.web.waiting"))
                    .foregroundStyle(StudioTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                Button(L("auth.web.reopen")) { coordinator.reopen() }
                    .buttonStyle(.plain)
                    .foregroundStyle(StudioTheme.accent)
                    .lineLimit(1)
                    .accessibilityIdentifier("onboardingWebLoginReopen")
                Button(L("auth.web.cancel")) { coordinator.cancel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(StudioTheme.textSecondary)
                    .lineLimit(1)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("onboardingWebLoginCancel")
            }
            .font(.studioBody(12, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Capsule(style: .continuous).fill(StudioTheme.textPrimary.opacity(0.05)))
        case let .working(messageKey):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(L(messageKey))
                    .foregroundStyle(StudioTheme.textSecondary)
                    .lineLimit(1)
            }
            .font(.studioBody(12, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Capsule(style: .continuous).fill(StudioTheme.textPrimary.opacity(0.05)))
        }
    }

    private func start() {
        // Only one browser transaction may wait for the shared callback scheme.
        if let sharedLogin, sharedLogin !== coordinator, sharedLogin.isBusy { sharedLogin.cancel() }
        Task { await coordinator.start() }
    }
}
