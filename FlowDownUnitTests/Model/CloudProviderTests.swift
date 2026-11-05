//
//  CloudProviderTests.swift
//  FlowDownUnitTests
//

import ChatClientKit
@testable import FlowDown
import Foundation
import Storage
import Testing

struct CloudProviderTests {
    private func makeModel(
        identifier: String = "model",
        endpoint: String,
        token: String = "key",
        format: CloudModel.ResponseFormat = .chatCompletions,
        creation: Date = Date(timeIntervalSince1970: 0),
    ) -> CloudModel {
        CloudModel(
            deviceId: "device",
            model_identifier: identifier,
            creation: creation,
            endpoint: endpoint,
            token: token,
            response_format: format,
        )
    }

    // MARK: Endpoint

    @Test
    func resolveEndpoint_baseURL_appendsContractPath() {
        let base = "https://api.openai.com/v1/"
        #expect(CloudProvider.resolveEndpoint(baseURL: base, contract: .chatCompletions) == "https://api.openai.com/v1/chat/completions")
        #expect(CloudProvider.resolveEndpoint(baseURL: base, contract: .responses) == "https://api.openai.com/v1/responses")
        #expect(CloudProvider.resolveEndpoint(baseURL: base, contract: .anthropicMessages) == "https://api.openai.com/v1/messages")
    }

    @Test
    func resolveEndpoint_fullEndpoint_replacesKnownPath() {
        let endpoint = "https://api.example.com/v1/chat/completions"
        #expect(CloudProvider.resolveEndpoint(baseURL: endpoint, contract: .chatCompletions) == endpoint)
        #expect(CloudProvider.resolveEndpoint(baseURL: endpoint, contract: .responses) == "https://api.example.com/v1/responses")
    }

    @Test
    func resolveEndpoint_query_isPreserved() {
        let base = "https://x.openai.azure.com/openai/deployments/gpt?api-version=2024-10-21"
        #expect(
            CloudProvider.resolveEndpoint(baseURL: base, contract: .chatCompletions)
                == "https://x.openai.azure.com/openai/deployments/gpt/chat/completions?api-version=2024-10-21"
        )
    }

    @Test
    func resolveEndpoint_empty_staysEmpty() {
        #expect(CloudProvider.resolveEndpoint(baseURL: "  ", contract: .responses).isEmpty)
    }

    @Test
    func displayBaseURL_stripsKnownPathOnly() {
        #expect(CloudProvider.displayBaseURL(forEndpoint: "https://api.anthropic.com/v1/messages") == "https://api.anthropic.com/v1")
        #expect(CloudProvider.displayBaseURL(forEndpoint: "https://host/custom/generate") == "https://host/custom/generate")
        let withQuery = "https://host/v1/chat/completions?api-version=1"
        #expect(CloudProvider.displayBaseURL(forEndpoint: withQuery) == withQuery)
    }

    // MARK: Contract

    @Test
    func contract_resolvesFromStoredFields() {
        #expect(CloudModelAPIContract.resolve(responseFormat: .responses, endpoint: "https://a/v1/responses") == .responses)
        #expect(CloudModelAPIContract.resolve(responseFormat: .chatCompletions, endpoint: "https://a/v1/chat/completions") == .chatCompletions)
        #expect(CloudModelAPIContract.resolve(responseFormat: .chatCompletions, endpoint: "https://api.anthropic.com/v1/messages/") == .anthropicMessages)
        #expect(CloudModelAPIContract.resolve(responseFormat: .chatCompletions, endpoint: "") == .chatCompletions)
    }

    @Test
    func contract_mapsToStoredResponseFormat() {
        #expect(CloudModelAPIContract.chatCompletions.responseFormat == .chatCompletions)
        #expect(CloudModelAPIContract.responses.responseFormat == .responses)
        #expect(CloudModelAPIContract.anthropicMessages.responseFormat == .chatCompletions)
    }

    @Test
    func contract_inferredFromEndpoint() {
        #expect(CloudModelAPIContract.inferred(fromEndpoint: "https://a/v1/chat/completions?x=1") == .chatCompletions)
        #expect(CloudModelAPIContract.inferred(fromEndpoint: "https://a/v1/RESPONSES") == .responses)
        #expect(CloudModelAPIContract.inferred(fromEndpoint: "https://a/anthropic/v1/messages") == .anthropicMessages)
        #expect(CloudModelAPIContract.inferred(fromEndpoint: "https://a/v1") == nil)
    }

    @Test
    func applyContract_rewritesEndpointAndDefaultModelList() {
        let model = makeModel(endpoint: "https://api.anthropic.com/v1/chat/completions")
        model.apply(contract: .anthropicMessages)
        #expect(model.endpoint == "https://api.anthropic.com/v1/messages")
        #expect(model.response_format == .chatCompletions)
        #expect(model.apiContract == .anthropicMessages)
        #expect(model.model_list_endpoint == CloudModelAPIContract.anthropicMessages.defaultModelListEndpoint)

        model.apply(contract: .responses)
        #expect(model.endpoint == "https://api.anthropic.com/v1/responses")
        #expect(model.apiContract == .responses)
    }

    @Test
    func applyContract_customPath_isLeftUntouched() {
        let model = makeModel(endpoint: "https://host/custom/generate")
        model.apply(contract: .responses)
        #expect(model.endpoint == "https://host/custom/generate")
        #expect(model.response_format == .responses)
    }

    @Test
    func routing_picksClientForContract() {
        let manager = ModelManager.shared
        let chat = makeModel(endpoint: "https://a/v1/chat/completions")
        let responses = makeModel(endpoint: "https://a/v1/responses", format: .responses)
        let anthropic = makeModel(endpoint: "https://api.anthropic.com/v1/messages")
        #expect(manager.makeCloudChatService(for: chat, additionalBodyField: [:]) is RemoteCompletionsChatClient)
        #expect(manager.makeCloudChatService(for: responses, additionalBodyField: [:]) is RemoteResponsesChatClient)
        #expect(manager.makeCloudChatService(for: anthropic, additionalBodyField: [:]) is AnthropicMessagesChatClient)
    }

    // MARK: Grouping

    @Test
    func group_sharedEndpointAndKey_formOneProvider() {
        let models = [
            makeModel(identifier: "b", endpoint: "https://api.openai.com/v1/chat/completions/", creation: .init(timeIntervalSince1970: 2)),
            makeModel(identifier: "a", endpoint: "https://api.openai.com/v1/chat/completions", creation: .init(timeIntervalSince1970: 1)),
            makeModel(identifier: "c", endpoint: "https://api.openai.com/v1/chat/completions", token: "other"),
            makeModel(identifier: "d", endpoint: ""),
        ]
        let providers = CloudProvider.group(models)
        #expect(providers.count == 2)
        let shared = providers.first { $0.apiKey == "key" }
        #expect(shared?.modelIdentifiers == ["a", "b"])
        #expect(shared?.baseURL == "https://api.openai.com/v1")
        #expect(shared?.contract == .chatCompletions)
        #expect(shared?.displayName == "OpenAI")
        #expect(!providers.contains { $0.modelIdentifiers.contains("d") })
    }

    @Test
    func group_differentFormats_areSeparateProviders() {
        let models = [
            makeModel(identifier: "a", endpoint: "https://h/v1/responses", format: .responses),
            makeModel(identifier: "b", endpoint: "https://h/v1/responses", format: .chatCompletions),
        ]
        #expect(CloudProvider.group(models).count == 2)
    }

    @Test
    func providerContaining_findsGroupOfModel() {
        let a = makeModel(identifier: "a", endpoint: "https://h/v1/chat/completions")
        let b = makeModel(identifier: "b", endpoint: "https://h/v1/chat/completions")
        let provider = CloudProvider.provider(containing: b.id, in: [a, b])
        #expect(provider?.modelIDs.sorted() == [a.id, b.id].sorted())
    }

    @Test
    func plan_keepsRemovesAndCreates() {
        let plan = CloudProvider.plan(
            existing: [(id: "1", identifier: "keep"), (id: "2", identifier: "drop"), (id: "3", identifier: "keep")],
            selectedIdentifiers: ["keep", "new", "new", ""],
        )
        #expect(plan.update == ["1", "3"])
        #expect(plan.remove == ["2"])
        #expect(plan.create == ["new"])
    }

    // MARK: Validation

    @Test
    func validation_reportsErrorsAndWarnings() {
        #expect(CloudProvider(contract: .chatCompletions, baseURL: "").validationIssues == [.missingBaseURL])
        #expect(CloudProvider(contract: .chatCompletions, baseURL: "api.openai.com/v1").validationIssues == [.invalidBaseURL])
        #expect(CloudProvider(contract: .chatCompletions, baseURL: "ftp://host/v1").validationIssues == [.invalidBaseURL])

        let noKey = CloudProvider(contract: .chatCompletions, baseURL: "https://api.openai.com/v1")
        #expect(noKey.validationIssues == [.missingAPIKey])
        #expect(noKey.canSave)

        let local = CloudProvider(contract: .chatCompletions, baseURL: "http://localhost:11434/v1")
        #expect(local.validationIssues.isEmpty)
    }

    // MARK: Requests

    @Test
    func modelListURL_resolvesPerContract() {
        let chat = CloudProvider(contract: .chatCompletions, baseURL: "https://api.openai.com/v1")
        #expect(chat.modelListURL?.absoluteString == "https://api.openai.com/v1/models")
        let responses = CloudProvider(contract: .responses, baseURL: "https://api.openai.com/v1")
        #expect(responses.modelListURL?.absoluteString == "https://api.openai.com/v1/models")
        let anthropic = CloudProvider(contract: .anthropicMessages, baseURL: "https://api.anthropic.com/v1")
        #expect(anthropic.modelListURL?.absoluteString == "https://api.anthropic.com/v1/models?limit=1000")
    }

    @Test
    func authorize_usesContractCredentials() throws {
        let url = try #require(URL(string: "https://example.com"))
        var bearer = URLRequest(url: url)
        CloudProvider.authorize(&bearer, contract: .responses, token: "sk", headers: [:])
        #expect(bearer.value(forHTTPHeaderField: "Authorization") == "Bearer sk")
        #expect(bearer.value(forHTTPHeaderField: "x-api-key") == nil)

        var anthropic = URLRequest(url: url)
        CloudProvider.authorize(&anthropic, contract: .anthropicMessages, token: "sk", headers: ["anthropic-version": "2024-01-01"])
        #expect(anthropic.value(forHTTPHeaderField: "x-api-key") == "sk")
        #expect(anthropic.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(anthropic.value(forHTTPHeaderField: "anthropic-version") == "2024-01-01")
    }

    @Test
    func scrubModelIdentifiers_readsCommonShapes() {
        #expect(ModelManager.scrubModelIdentifiers(from: ["data": [["id": "a"], ["id": "b"]]]) == ["a", "b"])
        #expect(ModelManager.scrubModelIdentifiers(from: ["models": [["name": "c"]]]) == ["c"])
        #expect(ModelManager.scrubModelIdentifiers(from: ["d"]) == ["d"])
    }

    @Test
    func serverErrorMessage_prefersNestedMessage() {
        let data = Data(#"{"error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
        #expect(ModelManager.serverErrorMessage(from: data) == "invalid x-api-key")
    }

    // MARK: Presets

    @Test
    func presets_matchByHostAndLocalPort() {
        #expect(CloudProviderPreset.matching(endpoint: "https://api.openai.com/v1/responses") == .openAI)
        #expect(CloudProviderPreset.matching(endpoint: "https://api.anthropic.com/v1/messages") == .anthropic)
        #expect(CloudProviderPreset.matching(endpoint: "http://localhost:11434/v1/chat/completions") == .ollama)
        #expect(CloudProviderPreset.matching(endpoint: "http://localhost:1234/v1/chat/completions") == .lmStudio)
        #expect(CloudProviderPreset.matching(endpoint: "http://localhost:9999/v1/chat/completions") == nil)
    }

    @Test
    func presets_haveValidEndpoints() {
        for preset in CloudProviderPreset.all {
            let provider = CloudProvider(preset: preset)
            #expect(provider.canSave, "\(preset.name)")
            #expect(CloudModelAPIContract.inferred(fromEndpoint: provider.endpoint) == preset.contract, "\(preset.name)")
        }
    }
}
