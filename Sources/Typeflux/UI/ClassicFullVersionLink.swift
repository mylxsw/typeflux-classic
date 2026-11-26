import AppKit
import SwiftUI

/// Entry point that opens the website page comparing Typeflux Classic with the full Typeflux app.
struct ClassicFullVersionLink: View {
    enum Style {
        /// Compact accent link, used inside headers.
        case inline
        /// Full-width settings row with a trailing external-link glyph.
        case row
    }

    let style: Style
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    @ObservedObject private var localization = AppLocalization.shared

    static var title: String {
        L("classic.fullVersion.link")
    }

    static var destination: URL {
        ClassicProductLinks.fullVersionComparisonURL
    }

    var body: some View {
        Button {
            openURL(Self.destination)
        } label: {
            switch style {
            case .inline:
                inlineLabel
            case .row:
                rowLabel
            }
        }
        .buttonStyle(StudioInteractiveButtonStyle())
        .help(Self.destination.absoluteString)
        .accessibilityLabel(Self.title)
    }

    private var inlineLabel: some View {
        HStack(spacing: StudioTheme.Spacing.xxSmall) {
            Text(Self.title)
            Image(systemName: "arrow.up.right")
                .font(.system(size: StudioTheme.Typography.iconXSmall, weight: .semibold))
        }
        .font(.studioBody(StudioTheme.Typography.body, weight: .semibold))
        .foregroundStyle(StudioTheme.accent)
        .contentShape(Rectangle())
    }

    private var rowLabel: some View {
        HStack(alignment: .center, spacing: StudioTheme.Spacing.large) {
            Text(Self.title)
                .font(.studioBody(StudioTheme.Typography.settingTitle, weight: .semibold))
                .foregroundStyle(StudioTheme.textPrimary)
            Spacer(minLength: StudioTheme.Spacing.pageGroup)
            Image(systemName: "arrow.up.right")
                .font(.system(size: StudioTheme.Typography.iconXSmall, weight: .semibold))
                .foregroundStyle(StudioTheme.textTertiary)
        }
        .padding(.vertical, StudioTheme.Spacing.xSmall)
        .contentShape(Rectangle())
    }
}
