//
//  CloudModelAPIContract.swift
//  FlowDown
//

import Foundation
import Storage

/// The wire protocol a cloud model speaks.
///
/// Storage only knows `CloudModel.ResponseFormat` (`chatCompletions` / `responses`).
/// Anthropic Messages is represented without a schema change: it is stored as
/// `.chatCompletions` and identified by its endpoint, which always ends in `/messages`
/// (the Anthropic path, never a valid Chat Completions or Responses path).
/// Keep every read and write of the contract going through this type so the
/// representation can move to a dedicated storage value later in one place.
enum CloudModelAPIContract: String, CaseIterable, Hashable, Sendable {
    case chatCompletions
    case responses
    case anthropicMessages

    /// The path appended to a provider base URL to form the inference endpoint.
    var endpointPath: String {
        switch self {
        case .chatCompletions: "/chat/completions"
        case .responses: "/responses"
        case .anthropicMessages: "/messages"
        }
    }

    /// The stored response format for this contract.
    var responseFormat: CloudModel.ResponseFormat {
        switch self {
        case .chatCompletions, .anthropicMessages: .chatCompletions
        case .responses: .responses
        }
    }

    /// Model list template resolved against the inference endpoint by `ModelManager`.
    var defaultModelListEndpoint: String {
        switch self {
        case .chatCompletions: "$INFERENCE_ENDPOINT$/../../models"
        case .responses: "$INFERENCE_ENDPOINT$/../models"
        case .anthropicMessages: "$INFERENCE_ENDPOINT$/../models?limit=1000"
        }
    }

    static var defaultModelListEndpoints: Set<String> {
        Set(allCases.map(\.defaultModelListEndpoint))
    }

    /// Resolves the contract from the stored fields of a model.
    static func resolve(responseFormat: CloudModel.ResponseFormat, endpoint: String) -> Self {
        switch responseFormat {
        case .responses:
            return .responses
        case .chatCompletions:
            if let path = CloudProvider.endpointPathComponent(endpoint),
               path.hasSuffix(Self.anthropicMessages.endpointPath)
            {
                return .anthropicMessages
            }
            return .chatCompletions
        }
    }

    /// Infers the contract from a full inference endpoint, or nil when the path is not recognized.
    static func inferred(fromEndpoint endpoint: String) -> Self? {
        guard let path = CloudProvider.endpointPathComponent(endpoint) else { return nil }
        return allCases.first { path.hasSuffix($0.endpointPath) }
    }
}

extension CloudModelAPIContract {
    var localizedTitle: String {
        switch self {
        case .chatCompletions: String(localized: "OpenAI Chat Completions")
        case .responses: String(localized: "OpenAI Responses")
        case .anthropicMessages: String(localized: "Anthropic Messages")
        }
    }

    var localizedDescription: String {
        switch self {
        case .chatCompletions:
            String(localized: "Most compatible. Used by OpenAI and almost every third-party or local server.")
        case .responses:
            String(localized: "OpenAI's newer API with better support for reasoning models.")
        case .anthropicMessages:
            String(localized: "Native Claude API, also offered by some compatible providers.")
        }
    }

    var icon: String {
        switch self {
        case .chatCompletions: "bubble.left.and.bubble.right"
        case .responses: "arrow.triangle.branch"
        case .anthropicMessages: "text.bubble"
        }
    }
}

extension CloudModel {
    var apiContract: CloudModelAPIContract {
        CloudModelAPIContract.resolve(responseFormat: response_format, endpoint: endpoint)
    }

    /// Switches the model to `contract`, rewriting the endpoint path and the default
    /// model list template so all stored fields agree.
    func apply(contract: CloudModelAPIContract) {
        update(\.response_format, to: contract.responseFormat)
        // Only a recognized path is rewritten; a custom path is left as the user wrote it.
        if CloudModelAPIContract.inferred(fromEndpoint: endpoint) != nil {
            update(\.endpoint, to: CloudProvider.resolveEndpoint(baseURL: endpoint, contract: contract))
        }
        if model_list_endpoint.isEmpty || CloudModelAPIContract.defaultModelListEndpoints.contains(model_list_endpoint) {
            update(\.model_list_endpoint, to: contract.defaultModelListEndpoint)
        }
    }
}
