//
//  CloudProvider.swift
//  FlowDown
//

import Foundation
import Storage

/// A model provider: one API endpoint plus credentials, shared by many models.
///
/// Storage keeps connection settings on every `CloudModel`, so a provider is not
/// persisted on its own. It is derived by grouping models that share the same
/// inference endpoint, API key and response format, and saving a provider writes
/// the connection settings back to every model in its group. This keeps CloudKit
/// sync, model export and older app versions working without a schema migration.
struct CloudProvider: Hashable, Identifiable {
    /// Models with identical connection settings belong to one provider.
    struct GroupKey: Hashable {
        var endpoint: String
        var token: String
        var responseFormat: CloudModel.ResponseFormat

        init(model: CloudModel) {
            endpoint = CloudProvider.normalizedEndpoint(model.endpoint)
            token = model.token.trimmingCharacters(in: .whitespacesAndNewlines)
            responseFormat = model.response_format
        }
    }

    var contract: CloudModelAPIContract
    /// What the user typed: a base URL (`https://api.openai.com/v1`) or a full endpoint.
    var baseURL: String
    var apiKey: String
    var headers: [String: String]
    /// Models currently stored for this provider, oldest first.
    var modelIDs: [CloudModel.ID]
    var modelIdentifiers: [String]

    init(
        contract: CloudModelAPIContract,
        baseURL: String,
        apiKey: String = "",
        headers: [String: String] = [:],
        modelIDs: [CloudModel.ID] = [],
        modelIdentifiers: [String] = [],
    ) {
        self.contract = contract
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
        self.modelIDs = modelIDs
        self.modelIdentifiers = modelIdentifiers
    }

    init(preset: CloudProviderPreset) {
        self.init(contract: preset.contract, baseURL: preset.baseURL, headers: preset.headers)
    }

    var id: String {
        [endpoint, apiKey, contract.rawValue].joined(separator: "\n")
    }

    /// The full inference endpoint stored on each model.
    var endpoint: String {
        Self.resolveEndpoint(baseURL: baseURL, contract: contract)
    }

    var preset: CloudProviderPreset? {
        CloudProviderPreset.matching(endpoint: endpoint)
    }

    var displayName: String {
        if let preset { return preset.name }
        if let host = URL(string: endpoint)?.host, !host.isEmpty { return host }
        return String(localized: "Custom Provider")
    }
}

// MARK: - Grouping

extension CloudProvider {
    /// Groups configured models into providers. Models without an endpoint are not
    /// part of any provider. Providers are ordered by their oldest model.
    static func group(_ models: [CloudModel]) -> [CloudProvider] {
        var order: [GroupKey] = []
        var buckets: [GroupKey: [CloudModel]] = [:]
        for model in models.sorted(by: { $0.creation < $1.creation }) {
            guard !normalizedEndpoint(model.endpoint).isEmpty else { continue }
            let key = GroupKey(model: model)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(model)
        }
        return order.compactMap { key in
            guard let members = buckets[key], let first = members.first else { return nil }
            return CloudProvider(
                contract: first.apiContract,
                baseURL: displayBaseURL(forEndpoint: first.endpoint),
                apiKey: key.token,
                headers: first.headers,
                modelIDs: members.map(\.id),
                modelIdentifiers: members.map(\.model_identifier),
            )
        }
    }

    /// The provider a model belongs to, if its endpoint is configured.
    static func provider(containing modelID: CloudModel.ID, in models: [CloudModel]) -> CloudProvider? {
        group(models).first { $0.modelIDs.contains(modelID) }
    }

    struct SavePlan: Equatable {
        /// Existing models that stay and receive the new connection settings.
        var update: [CloudModel.ID]
        /// Existing models whose identifier was deselected.
        var remove: [CloudModel.ID]
        /// Identifiers that need a new model.
        var create: [String]
    }

    /// Decides which models to keep, remove and create when the user saves the
    /// provider with `selectedIdentifiers` checked.
    static func plan(
        existing: [(id: CloudModel.ID, identifier: String)],
        selectedIdentifiers: [String],
    ) -> SavePlan {
        let selected = Set(selectedIdentifiers)
        var plan = SavePlan(update: [], remove: [], create: [])
        var present: Set<String> = []
        for item in existing {
            if selected.contains(item.identifier) {
                plan.update.append(item.id)
                present.insert(item.identifier)
            } else {
                plan.remove.append(item.id)
            }
        }
        var seen: Set<String> = []
        for identifier in selectedIdentifiers where !present.contains(identifier) {
            guard !identifier.isEmpty, seen.insert(identifier).inserted else { continue }
            plan.create.append(identifier)
        }
        return plan
    }
}

// MARK: - Endpoint

extension CloudProvider {
    /// Trims whitespace and trailing slashes so equivalent endpoints compare equal.
    static func normalizedEndpoint(_ endpoint: String) -> String {
        var value = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    /// The lowercased path of an endpoint without query, fragment or trailing slash.
    static func endpointPathComponent(_ endpoint: String) -> String? {
        let (path, _) = splitQuery(normalizedEndpoint(endpoint))
        var value = path.lowercased()
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value.isEmpty ? nil : value
    }

    /// Builds the inference endpoint for `contract`. `baseURL` may already be a full
    /// endpoint for any contract; its known path suffix is replaced, and any query
    /// (e.g. Azure `api-version`) is preserved.
    static func resolveEndpoint(baseURL: String, contract: CloudModelAPIContract) -> String {
        let normalized = normalizedEndpoint(baseURL)
        guard !normalized.isEmpty else { return "" }
        var (path, query) = splitQuery(normalized)
        while path.hasSuffix("/") {
            path.removeLast()
        }
        if let suffix = knownSuffix(of: path) {
            path.removeLast(suffix.count)
        }
        return path + contract.endpointPath + query
    }

    /// The text shown in the Base URL field for a stored endpoint: the base URL when the
    /// endpoint is a plain base plus a known path, otherwise the endpoint unchanged.
    static func displayBaseURL(forEndpoint endpoint: String) -> String {
        let normalized = normalizedEndpoint(endpoint)
        let (path, query) = splitQuery(normalized)
        guard query.isEmpty, let suffix = knownSuffix(of: path) else { return normalized }
        return String(path.dropLast(suffix.count))
    }

    private static func knownSuffix(of path: String) -> String? {
        let lowered = path.lowercased()
        // Longest first so `/chat/completions` wins over any shorter overlap.
        let suffixes = CloudModelAPIContract.allCases
            .map(\.endpointPath)
            .sorted { $0.count > $1.count }
        return suffixes.first { lowered.hasSuffix($0) }
    }

    private static func splitQuery(_ value: String) -> (path: String, query: String) {
        guard let index = value.firstIndex(where: { $0 == "?" || $0 == "#" }) else {
            return (value, "")
        }
        return (String(value[..<index]), String(value[index...]))
    }
}

// MARK: - Validation

extension CloudProvider {
    enum ValidationIssue: Equatable {
        case missingBaseURL
        case invalidBaseURL
        case missingAPIKey

        /// Errors block saving; warnings are only shown.
        var isError: Bool {
            switch self {
            case .missingBaseURL, .invalidBaseURL: true
            case .missingAPIKey: false
            }
        }

        var message: String {
            switch self {
            case .missingBaseURL:
                String(localized: "Enter the base URL of the provider.")
            case .invalidBaseURL:
                String(localized: "The base URL must be a full address starting with http:// or https://.")
            case .missingAPIKey:
                String(localized: "No API key is set. Most cloud providers reject requests without one.")
            }
        }
    }

    var validationIssues: [ValidationIssue] {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [.missingBaseURL] }
        var issues: [ValidationIssue] = []
        if let url = URL(string: endpoint),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           let host = url.host, !host.isEmpty
        {
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !Self.isLocalHost(host) {
                issues.append(.missingAPIKey)
            }
        } else {
            issues.append(.invalidBaseURL)
        }
        return issues
    }

    var canSave: Bool {
        !validationIssues.contains(where: \.isError)
    }

    static func isLocalHost(_ host: String) -> Bool {
        let lowered = host.lowercased()
        if ["localhost", "127.0.0.1", "::1", "0.0.0.0"].contains(lowered) { return true }
        if lowered.hasSuffix(".local") { return true }
        return lowered.hasPrefix("192.168.") || lowered.hasPrefix("10.")
    }
}

// MARK: - Requests

extension CloudProvider {
    static let anthropicVersion = "2023-06-01"

    /// Applies the credentials each contract expects, then the custom headers, which may
    /// override any of them.
    static func authorize(
        _ request: inout URLRequest,
        contract: CloudModelAPIContract,
        token: String,
        headers: [String: String],
    ) {
        switch contract {
        case .chatCompletions, .responses:
            if !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        case .anthropicMessages:
            if !token.isEmpty {
                request.setValue(token, forHTTPHeaderField: "x-api-key")
            }
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    /// Resolves a model list template such as `$INFERENCE_ENDPOINT$/../../models`.
    static func resolveModelListURL(template: String, endpoint: String) -> URL? {
        var value = template
        if value.contains("$INFERENCE_ENDPOINT$") {
            let endpoint = normalizedEndpoint(endpoint)
            guard !endpoint.isEmpty else { return nil }
            // A query on the endpoint would end up in the middle of the path.
            let (path, _) = splitQuery(endpoint)
            value = value.replacingOccurrences(of: "$INFERENCE_ENDPOINT$", with: path)
        }
        guard !value.isEmpty, let url = URL(string: value)?.standardized else { return nil }
        return url
    }

    var modelListURL: URL? {
        Self.resolveModelListURL(template: contract.defaultModelListEndpoint, endpoint: endpoint)
    }
}
