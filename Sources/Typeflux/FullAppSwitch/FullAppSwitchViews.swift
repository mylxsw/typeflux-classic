import AppKit
import SwiftUI

private enum FullAppDialogMetrics {
    static let padding: CGFloat = 24
    static let spacing: CGFloat = 18
    static let iconSize: CGFloat = 52
    static let width: CGFloat = 480
}

private struct FullAppSwitchIcon: View {
    var body: some View {
        if let icon = NSApp.applicationIconImage {
            Image(nsImage: icon).resizable().interpolation(.high)
                .frame(width: FullAppDialogMetrics.iconSize, height: FullAppDialogMetrics.iconSize)
        }
    }
}

// MARK: - Switch flow

/// Confirmation, progress and failure states of `FullAppSwitchController`.
struct FullAppSwitchView: View {
    @ObservedObject var controller: FullAppSwitchController

    var body: some View {
        VStack(alignment: .leading, spacing: FullAppDialogMetrics.spacing) {
            content
        }
        .padding(FullAppDialogMetrics.padding)
        .frame(width: FullAppDialogMetrics.width, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fullApp.switch")
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .idle, .confirming:
            header(L("fullAppSwitch.confirm.title"))
            HStack(spacing: StudioTheme.Spacing.small) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: StudioTheme.Typography.iconRegular, weight: .semibold))
                    .foregroundStyle(StudioTheme.success)
                Text(L("fullAppSwitch.confirm.dataKept"))
                    .font(.studioBody(StudioTheme.Typography.body))
                    .foregroundStyle(StudioTheme.textPrimary)
            }
            buttons {
                StudioButton(title: L("common.cancel"), systemImage: nil, variant: .secondary) { controller.cancel() }
                    .keyboardShortcut(.cancelAction)
                StudioButton(title: L("fullAppSwitch.confirm.action"), systemImage: nil, variant: .primary) {
                    controller.confirm()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("fullApp.switch.confirm")
            }
        case let .downloading(fraction):
            header(L("fullAppSwitch.downloading"))
            progress(fraction)
            buttons {
                StudioButton(title: L("common.cancel"), systemImage: nil, variant: .secondary) { controller.cancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("fullApp.switch.cancel")
            }
        case .installing:
            header(L("fullAppSwitch.installing"))
            ProgressView().progressViewStyle(.linear)
        case let .failed(message):
            header(L("fullAppSwitch.failed"))
            Text(message)
                .font(.studioBody(StudioTheme.Typography.body))
                .foregroundStyle(StudioTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("fullApp.switch.error")
            buttons {
                StudioButton(title: L("common.cancel"), systemImage: nil, variant: .secondary) { controller.cancel() }
                    .keyboardShortcut(.cancelAction)
                StudioButton(title: L("common.retry"), systemImage: nil, variant: .primary) { controller.retry() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("fullApp.switch.retry")
            }
        }
    }

    private func header(_ title: String) -> some View {
        HStack(spacing: StudioTheme.Spacing.medium) {
            FullAppSwitchIcon()
            Text(title)
                .font(.studioBody(StudioTheme.Typography.subsectionTitle, weight: .semibold))
                .foregroundStyle(StudioTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func progress(_ fraction: Double?) -> some View {
        HStack(spacing: StudioTheme.Spacing.smallMedium) {
            if let fraction {
                ProgressView(value: fraction).progressViewStyle(.linear)
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: StudioTheme.Typography.bodySmall).monospacedDigit())
                    .foregroundStyle(StudioTheme.textSecondary)
                    .frame(width: 40, alignment: .trailing)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
        .accessibilityIdentifier("fullApp.switch.progress")
    }

    private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: StudioTheme.Spacing.small) {
            Spacer()
            content()
        }
    }
}

// MARK: - Entry rows

/// Wraps the switch entry point. The content, including any row chrome, only exists while a
/// published full Typeflux release is available, so a hidden entry leaves no gap in its container.
struct FullAppSwitchEntry<Content: View>: View {
    @ObservedObject var controller: FullAppSwitchController
    @ViewBuilder let content: () -> Content

    var body: some View {
        if controller.isAvailable {
            content()
        }
    }
}

extension View {
    /// Re-checks full app availability (cached for a while) when the containing page appears.
    @MainActor
    func refreshesFullAppAvailability(_ controller: FullAppSwitchController? = nil) -> some View {
        let controller = controller ?? .shared
        return task { await controller.refreshAvailability() }
    }
}
