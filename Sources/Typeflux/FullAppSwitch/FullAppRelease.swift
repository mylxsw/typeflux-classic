import Foundation

/// One downloadable package of the full Typeflux app (1.x) for this Mac.
struct FullAppPackage: Equatable, Sendable {
    let version: String
    let downloadURL: URL
    let sha256: String?
    let fileSize: Int64?
}

/// `GET /api/v1/app/releases/latest?product=typeflux`.
struct FullAppReleaseEnvelope: Decodable {
    let code: String?
    let message: String?
    let data: FullAppReleasePayload?
}

struct FullAppReleasePayload: Decodable, Equatable {
    let version: String
    let assets: [FullAppReleaseAsset]?
}

struct FullAppReleaseAsset: Decodable, Equatable {
    let platform: String
    let architecture: String
    let packageType: String
    let channel: String
    let fileSize: Int64?
    let sha256: String?
    let downloadURL: String

    enum CodingKeys: String, CodingKey {
        case platform, architecture, channel, sha256
        case packageType = "package_type"
        case fileSize = "file_size"
        case downloadURL = "download_url"
    }
}

enum FullAppReleaseResolver {
    static let apiPath = "/api/v1/app/releases/latest"
    /// The product identifier the full Typeflux app sends to the update and release APIs.
    static let product = "typeflux"
    static let packageType = "app_only_zip"
    static let preferredChannel = "global"

    /// The release API names Intel packages `x86_64`; the update API calls them `amd64`.
    static func serverArchitecture(_ packageArchitecture: String = AutoUpdateRequestSupport.packageArchitecture()) -> String {
        packageArchitecture == "amd64" ? "x86_64" : packageArchitecture
    }

    /// Returns nil when the server reports an error or has no app-only package for this architecture.
    static func package(from data: Data, apiBaseURL: URL, architecture: String = serverArchitecture()) -> FullAppPackage? {
        guard let envelope = try? JSONDecoder().decode(FullAppReleaseEnvelope.self, from: data),
              envelope.code == nil || envelope.code == "OK",
              let release = envelope.data
        else { return nil }
        return package(from: release, apiBaseURL: apiBaseURL, architecture: architecture)
    }

    static func package(from release: FullAppReleasePayload, apiBaseURL: URL, architecture: String) -> FullAppPackage? {
        let version = release.version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isFullAppVersion(version) else { return nil }
        let candidates = (release.assets ?? []).filter {
            $0.platform == "macos" && $0.architecture == architecture && $0.packageType == packageType
        }
        let asset = candidates.first { $0.channel == preferredChannel }
            ?? candidates.sorted { $0.channel < $1.channel }.first
        guard let asset, let url = downloadURL(for: asset.downloadURL, apiBaseURL: apiBaseURL) else { return nil }
        let checksum = asset.sha256?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return FullAppPackage(
            version: version,
            downloadURL: url,
            sha256: checksum?.isEmpty == false ? checksum : nil,
            fileSize: asset.fileSize
        )
    }

    /// The full app is on 1.x or later. A server that ignores `product=typeflux` may answer with a
    /// Classic (0.x) release, which must never be offered as the full app.
    static func isFullAppVersion(_ version: String) -> Bool {
        let trimmed = version.hasPrefix("v") || version.hasPrefix("V") ? String(version.dropFirst()) : version
        guard let major = trimmed.split(separator: ".").first.flatMap({ Int($0) }) else { return false }
        return major >= 1
    }

    /// The server returns a relative `/d/...` redirect path. Relative paths resolve against the API
    /// base and always carry `product=typeflux`, so a server that forgets it cannot hand out Classic.
    static func downloadURL(for raw: String, apiBaseURL: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), let scheme = absolute.scheme?.lowercased() {
            return ["https", "http"].contains(scheme) && absolute.host != nil ? absolute : nil
        }
        let pieces = trimmed.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let resolved = AuthEndpointResolver.resolve(baseURL: apiBaseURL, path: String(pieces[0]))
        guard var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) else { return nil }
        var items = pieces.count == 2 ? (URLComponents(string: "?" + pieces[1])?.queryItems ?? []) : []
        items.removeAll { $0.name == "product" }
        items.append(URLQueryItem(name: "product", value: product))
        components.queryItems = items
        return components.url
    }

    /// Recovers the endpoint base URL from the response URL of the release request.
    static func apiBaseURL(fromResponseURL url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var path = components.path
        if path.hasSuffix(apiPath) { path.removeLast(apiPath.count) }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

protocol FullAppReleaseFetching: Sendable {
    /// Returns nil when no full Typeflux release is published for this Mac.
    func latestFullAppPackage() async throws -> FullAppPackage?
}

struct CloudFullAppReleaseFetcher: FullAppReleaseFetching {
    func latestFullAppPackage() async throws -> FullAppPackage? {
        let apiPath = FullAppReleaseResolver.apiPath
        let (data, response) = try await CloudRequestExecutor().execute(apiPath: apiPath) { baseURL in
            let url = AuthEndpointResolver.resolve(baseURL: baseURL, path: apiPath)
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
            components.queryItems = [URLQueryItem(name: "product", value: FullAppReleaseResolver.product)]
            var request = URLRequest(url: components.url ?? url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            return request
        }
        guard (200 ..< 300).contains(response.statusCode),
              let responseURL = response.url,
              let baseURL = FullAppReleaseResolver.apiBaseURL(fromResponseURL: responseURL)
        else { return nil }
        return FullAppReleaseResolver.package(from: data, apiBaseURL: baseURL)
    }
}
