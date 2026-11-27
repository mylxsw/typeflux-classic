import Foundation

extension SettingsStore {
    enum RewriteModelSelection: Equatable {
        case cloud
        case remote(LLMRemoteProvider, model: String)
        case ollama(model: String)
    }

    private static let rewriteReferenceKey = "llm.profile.reference"

    var rewriteModelSelection: RewriteModelSelection {
        if llmProvider == .ollama { return .ollama(model: ollamaModel) }
        if llmRemoteProvider == .typefluxCloud { return .cloud }
        return .remote(llmRemoteProvider, model: llmModel)
    }

    /// Returns false when a saved Typeflux selection cannot be represented by Classic.
    @discardableResult
    func importSharedRewriteModelSelection() -> Bool {
        defer { lastBridgedRewriteModelSelection = rewriteModelSelection }
        guard let reference = defaults.string(forKey: Self.rewriteReferenceKey), !reference.isEmpty else {
            return true
        }
        guard let selection = sharedRewriteModelSelection(for: reference) else { return false }

        switch selection {
        case .cloud:
            llmRemoteProvider = .typefluxCloud
            llmProvider = .openAICompatible
        case let .remote(provider, model):
            // The unscoped key is also the fallback for Classic's custom endpoint.
            defaults.set(model, forKey: "llm.remote.\(provider.rawValue).model")
            llmRemoteProvider = provider
            llmProvider = .openAICompatible
        case let .ollama(model):
            ollamaModel = model
            llmProvider = .ollama
        }
        return true
    }

    /// Call after committing the legacy keys for a user-initiated selection change.
    @discardableResult
    func exportSharedRewriteModelSelection(ifChangedFrom previous: RewriteModelSelection) -> Bool {
        let selection = rewriteModelSelection
        lastBridgedRewriteModelSelection = selection
        guard selection != previous else { return false }

        writeSharedRewriteModelReference(for: selection)
        return true
    }

    /// The account module posts after applying its legacy settings.
    @MainActor
    func observeCloudRewriteModelDefaults() -> NSObjectProtocol {
        lastBridgedRewriteModelSelection = rewriteModelSelection
        return NotificationCenter.default.addObserver(
            forName: .cloudAccountModelDefaultsDidApply, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let previous = self.lastBridgedRewriteModelSelection else { return }
                if self.rewriteModelSelection == .cloud,
                   self.defaults.string(forKey: Self.rewriteReferenceKey) == "cloud:default" {
                    // The account coordinator already saved the canonical reference.
                    self.lastBridgedRewriteModelSelection = .cloud
                    return
                }
                self.exportSharedRewriteModelSelection(ifChangedFrom: previous)
            }
        }
    }

    private func sharedRewriteModelSelection(for reference: String) -> RewriteModelSelection? {
        if reference == "cloud:default" { return .cloud }
        return sharedRewriteModels.first { $0.reference == reference }?.selection
    }

    private func writeSharedRewriteModelReference(for selection: RewriteModelSelection) {
        let reference = sharedRewriteModels.first {
            $0.selection == selection && (selection != .cloud || $0.modelID == "default")
        }?.reference
        if let reference {
            guard defaults.string(forKey: Self.rewriteReferenceKey) != reference else { return }
            defaults.set(reference, forKey: Self.rewriteReferenceKey)
        } else if defaults.object(forKey: Self.rewriteReferenceKey) != nil {
            defaults.removeObject(forKey: Self.rewriteReferenceKey)
        }
    }

    private struct SharedRewriteModel {
        let selection: RewriteModelSelection
        let modelID: String
        let reference: String
    }

    private var sharedRewriteModels: [SharedRewriteModel] {
        guard let data = defaults.data(forKey: "models.registry.v2"),
              let registry = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              registry["version"] as? Int == 2,
              let providers = registry["providers"] as? [Any]
        else { return [] }

        return providers.flatMap { entry -> [SharedRewriteModel] in
            guard let provider = entry as? [String: Any],
                  let providerID = provider["id"] as? String, !providerID.isEmpty, !providerID.hasPrefix("endpoint:"),
                  let models = provider["models"] as? [Any]
            else { return [] }

            return models.compactMap { entry in
                guard let model = entry as? [String: Any],
                      let modelID = model["id"] as? String, !modelID.isEmpty,
                      let reference = model["reference"] as? String, !reference.isEmpty
                else { return nil }

                let selection: RewriteModelSelection
                if providerID == "ollama" {
                    selection = .ollama(model: modelID)
                } else if let rawProvider = provider["remote"] as? String,
                          let remote = LLMRemoteProvider(rawValue: rawProvider), remote != .custom {
                    selection = remote == .typefluxCloud ? .cloud : .remote(remote, model: modelID)
                } else {
                    return nil
                }
                return SharedRewriteModel(selection: selection, modelID: modelID, reference: reference)
            }
        }
    }
}
