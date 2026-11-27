import Foundation

extension TypefluxOfficialTranscriber {
    /// The workflow snapshots the account generation at microphone start.
    @TaskLocal static var recordingSession: Int?

    @MainActor
    static func currentSessionCredential() async -> TypefluxCloudSessionCredential? {
        let session = recordingSession ?? AuthState.shared.sessionGeneration
        guard AuthState.shared.sessionGeneration == session,
              let credential = await AuthState.shared.validSessionCredential(),
              credential.session == session,
              AuthState.shared.sessionGeneration == session
        else { return nil }
        return credential
    }

    static func recordingCredential(
        from credentialProvider: @Sendable () async -> TypefluxCloudSessionCredential?
    ) async throws -> TypefluxCloudSessionCredential {
        try Task.checkCancellation()
        guard let credential = await credentialProvider(), !credential.accessToken.isEmpty else {
            throw TypefluxOfficialASRError.notLoggedIn
        }
        try Task.checkCancellation()
        if let recordingSession, credential.session != recordingSession {
            throw TypefluxOfficialASRError.sessionChanged
        }
        return credential
    }

    /// Returns a currently valid credential of the session that started the
    /// recording. A token refresh within that session is allowed; a recording
    /// whose session was logged out or replaced stops instead of continuing
    /// on (and billing) another account.
    @discardableResult
    static func requireRecordingSession(
        _ recording: TypefluxCloudSessionCredential,
        credentialProvider: @Sendable () async -> TypefluxCloudSessionCredential?
    ) async throws -> TypefluxCloudSessionCredential {
        guard let current = await credentialProvider(), !current.accessToken.isEmpty else {
            throw TypefluxOfficialASRError.notLoggedIn
        }
        guard current.session == recording.session else {
            throw TypefluxOfficialASRError.sessionChanged
        }
        return current
    }

    /// Uses the current token of the original session, which may have refreshed
    /// since recording started. A replacement grant is issued on demand.
    static func fetchRecordingRoute(
        for recording: TypefluxCloudSessionCredential,
        credentialProvider: @Sendable () async -> TypefluxCloudSessionCredential?,
        routingClient: any TypefluxOfficialASRRoutingClient,
        scenario: TypefluxCloudScenario,
        replacingGrant: Bool = false
    ) async throws -> TypefluxOfficialASRRouteDecision {
        let current = try await requireRecordingSession(recording, credentialProvider: credentialProvider)
        try Task.checkCancellation()
        if replacingGrant {
            return try await routingClient.issueRoute(accessToken: current.accessToken, scenario: scenario)
        }
        return try await routingClient.fetchRoute(accessToken: current.accessToken, scenario: scenario)
    }

    /// Hands out one-time grants for a recording that started with
    /// `recording`, checking its session before every grant is used.
    static func makeGrantSequence(
        initial route: TypefluxOfficialASRRouteDecision,
        recording: TypefluxCloudSessionCredential,
        credentialProvider: @escaping @Sendable () async -> TypefluxCloudSessionCredential?,
        routingClient: any TypefluxOfficialASRRoutingClient,
        scenario: TypefluxCloudScenario
    ) -> TypefluxOfficialASRGrantSequence {
        TypefluxOfficialASRGrantSequence(
            initial: route,
            verifySession: {
                try await requireRecordingSession(recording, credentialProvider: credentialProvider)
            },
            fetch: {
                try await fetchRecordingRoute(
                    for: recording,
                    credentialProvider: credentialProvider,
                    routingClient: routingClient,
                    scenario: scenario,
                    replacingGrant: true
                )
            }
        )
    }

    /// Runs an ASR session against the highest-priority cloud endpoint and
    /// retries against the next endpoint when an attempt fails before any
    /// audio was sent. Each attempt must take its own one-time grant (see
    /// `TypefluxOfficialASRGrantSequence`). Once audio has been sent
    /// (`TypefluxOfficialASRAdmittedStreamError`) the failure is final:
    /// mid-session migration is not supported because replaying the audio
    /// elsewhere could duplicate the transcript and its billing. A cancelled
    /// recording stops without another grant or attempt.
    static func runWithASRServerFailover<T>(
        preferredServers: [URL],
        serverRegistry: any TypefluxASRServerProviding = TypefluxASRServerRegistry.shared,
        transportDiagnostics: NetworkTransportDiagnosticsRecorder? = nil,
        operation: @Sendable (String) async throws -> T
    ) async throws -> T {
        transportDiagnostics?.markServerSelectionStarted()
        let baseURLs = await serverRegistry.orderedServers(preferred: preferredServers)
        transportDiagnostics?.markServerSelectionCompleted()
        try Task.checkCancellation()

        guard !baseURLs.isEmpty else {
            throw TypefluxOfficialASRError.connectionFailed("No Typeflux Cloud endpoint configured.")
        }

        var lastError: Error?
        for baseURL in baseURLs {
            try Task.checkCancellation()
            do {
                return try await operation(baseURL.absoluteString)
            } catch {
                if Task.isCancelled || TypefluxOfficialASRCancellation.isCancellation(error) {
                    throw CancellationError()
                }
                let admitted = error is TypefluxOfficialASRAdmittedStreamError
                let failure = (error as? TypefluxOfficialASRAdmittedStreamError)?.underlying ?? error
                if let refreshError = failure as? TypefluxOfficialASRGrantRefreshError {
                    throw refreshError.underlying
                }
                if TypefluxCloudASRDirectiveError.fromError(failure) != nil {
                    throw TypefluxCloudASRDirectiveError()
                }
                if failure is CloudCreditsExhaustedError {
                    throw failure
                }
                if failure is TypefluxCloudIntegratedRewriteError {
                    // A billing stop after the transcript arrived; the caller
                    // keeps the transcript.
                    throw failure
                }
                if let billingError = TypefluxCloudBillingError.fromError(failure) {
                    throw billingError
                }
                await serverRegistry.reportFailure(baseURL, error: failure)
                if admitted {
                    throw failure
                }
                lastError = failure
            }
        }
        throw lastError ?? TypefluxOfficialASRError.connectionFailed("All endpoints failed.")
    }
}
