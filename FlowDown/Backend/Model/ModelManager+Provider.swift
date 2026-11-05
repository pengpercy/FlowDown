//
//  ModelManager+Provider.swift
//  FlowDown
//

import Foundation
import Storage

enum CloudProviderConnectionError: LocalizedError {
    case invalidURL
    case server(statusCode: Int, message: String?)
    case unreadableResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            String(localized: "The base URL is not valid.")
        case let .server(statusCode, message):
            if let message, !message.isEmpty {
                String(localized: "The server responded with status \(statusCode): \(message)")
            } else {
                String(localized: "The server responded with status \(statusCode).")
            }
        case .unreadableResponse:
            String(localized: "The server response does not contain a model list.")
        }
    }
}

extension ModelManager {
    /// All providers derived from the stored cloud models.
    var cloudProviders: [CloudProvider] {
        CloudProvider.group(cloudModels.value)
    }

    func cloudProvider(containing modelID: CloudModel.ID) -> CloudProvider? {
        CloudProvider.provider(containing: modelID, in: cloudModels.value)
    }

    /// Lists the models a provider serves. Throws a readable error so it doubles as a
    /// connection test.
    func fetchProviderModels(_ provider: CloudProvider) async throws -> [String] {
        guard let url = provider.modelListURL else { throw CloudProviderConnectionError.invalidURL }
        return try await Self.fetchModelIdentifiers(
            url: url,
            contract: provider.contract,
            token: provider.apiKey,
            headers: provider.headers,
        )
    }

    static func fetchModelIdentifiers(
        url: URL,
        contract: CloudModelAPIContract,
        token: String,
        headers: [String: String],
    ) async throws -> [String] {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        CloudProvider.authorize(&request, contract: contract, token: token, headers: headers)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            Logger.network.errorFile("[fetchModelIdentifiers] status \(http.statusCode) for URL: \(url.absoluteString)")
            throw CloudProviderConnectionError.server(
                statusCode: http.statusCode,
                message: serverErrorMessage(from: data),
            )
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw CloudProviderConnectionError.unreadableResponse
        }
        let identifiers = scrubModelIdentifiers(from: json)
        guard !identifiers.isEmpty || isEmptyModelList(json) else {
            throw CloudProviderConnectionError.unreadableResponse
        }
        return Array(Set(identifiers)).sorted()
    }

    /// Extracts `error.message`, `error` or `message` from a JSON error body.
    static func serverErrorMessage(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                return message
            }
            if let error = json["error"] as? String { return error }
            if let message = json["message"] as? String { return message }
            if let detail = json["detail"] as? String { return detail }
        }
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        return String(text.prefix(200))
    }

    static func scrubModelIdentifiers(from json: Any) -> [String] {
        // OpenAI and Anthropic: { data: [{ id }] }
        if let dict = json as? [String: Any] {
            if let data = dict["data"] as? [[String: Any]] {
                return data.compactMap { $0["id"] as? String }
            }
            if let data = dict["data"] as? [String] {
                return data
            }
            // Some providers: { models: [{ id/name/model }] }
            if let models = dict["models"] as? [[String: Any]] {
                return models.compactMap { item in
                    (item["id"] as? String)
                        ?? (item["name"] as? String)
                        ?? (item["model"] as? String)
                }
            }
            if let models = dict["models"] as? [String] {
                return models
            }
            if let items = dict["items"] as? [[String: Any]] {
                return items.compactMap { $0["id"] as? String ?? $0["name"] as? String }
            }
        }
        if let array = json as? [[String: Any]] {
            return array.compactMap { $0["id"] as? String ?? $0["name"] as? String }
        }
        if let array = json as? [String] {
            return array
        }
        return []
    }

    private static func isEmptyModelList(_ json: Any) -> Bool {
        if let dict = json as? [String: Any] {
            for key in ["data", "models", "items"] {
                if let list = dict[key] as? [Any], list.isEmpty { return true }
            }
        }
        if let list = json as? [Any], list.isEmpty { return true }
        return false
    }

    /// Writes `provider` to its models: models whose identifier is no longer selected
    /// are removed, the rest receive the new connection settings, and new identifiers
    /// become new models.
    /// - Parameter applyHeaders: Overwrite headers on existing models. Only pass `true`
    ///   when the user edited them, so per-model header tweaks survive other edits.
    @discardableResult
    func saveCloudProvider(
        _ provider: CloudProvider,
        selectedIdentifiers: [String],
        applyHeaders: Bool,
    ) -> CloudProvider.SavePlan {
        let existing = provider.modelIDs.compactMap { id in
            cloudModel(identifier: id).map { (id: $0.id, identifier: $0.model_identifier) }
        }
        let plan = CloudProvider.plan(existing: existing, selectedIdentifiers: selectedIdentifiers)
        let endpoint = provider.endpoint
        let token = provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        for id in plan.remove {
            sdb.cloudModelRemove(identifier: id)
        }
        for id in plan.update {
            sdb.cloudModelEdit(identifier: id) { model in
                model.update(\.endpoint, to: endpoint)
                model.update(\.token, to: token)
                model.update(\.response_format, to: provider.contract.responseFormat)
                if model.model_list_endpoint.isEmpty
                    || CloudModelAPIContract.defaultModelListEndpoints.contains(model.model_list_endpoint)
                {
                    model.update(\.model_list_endpoint, to: provider.contract.defaultModelListEndpoint)
                }
                if applyHeaders {
                    model.update(\.headers, to: provider.headers)
                }
            }
        }
        let now = dateProvider()
        for (offset, identifier) in plan.create.enumerated() {
            let model = CloudModel(
                deviceId: Storage.deviceId,
                model_identifier: identifier,
                model_list_endpoint: provider.contract.defaultModelListEndpoint,
                // Keeps the selection order when models are listed by creation date.
                creation: now.addingTimeInterval(Double(offset) / 1000),
                endpoint: endpoint,
                token: token,
                headers: provider.headers,
                response_format: provider.contract.responseFormat,
            )
            try? sdb.cloudModelPut(model)
        }
        cloudModels.send(scanCloudModels())
        return plan
    }

    func removeCloudProvider(_ provider: CloudProvider) {
        for id in provider.modelIDs {
            sdb.cloudModelRemove(identifier: id)
        }
        cloudModels.send(scanCloudModels())
    }
}
