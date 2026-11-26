import Foundation

extension SettingsStore {
    /// An explicit full-app rewrite selection takes precedence over the legacy provider.
    var usesCloudRewriteForAccountDefaults: Bool {
        let reference = rewriteModelReference
        if reference.isEmpty { return textLLMConfiguration().provider == .typefluxCloud }
        if reference == "cloud:default" { return true }
        guard let data = defaults.data(forKey: "models.registry.v2"),
              let registry = try? JSONDecoder().decode(AccountModelRegistry.self, from: data),
              registry.version == 2 else { return false }
        return registry.providers.contains { provider in
            provider.remote == LLMRemoteProvider.typefluxCloud.rawValue
                && provider.models.contains { $0.reference == reference }
        }
    }
}

private struct AccountModelRegistry: Decodable {
    struct Provider: Decodable {
        struct Model: Decodable { let reference: String }
        let remote: String?
        let models: [Model]
    }

    let version: Int
    let providers: [Provider]
}
