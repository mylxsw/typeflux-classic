import Foundation

/// Outbound links that are specific to the Typeflux Classic distribution.
enum ClassicProductLinks {
    /// Website page comparing Typeflux Classic with the full Typeflux app.
    static let fullVersionComparisonURL = URL(string: "https://typeflux.app/compare")!

    /// Source repository of Typeflux Classic.
    static let projectURL = TypefluxProduct.repositoryURL

    /// New-issue page of the Typeflux Classic repository.
    static let newIssueURL = TypefluxProduct.repositoryURL.appendingPathComponent("issues/new")
}
