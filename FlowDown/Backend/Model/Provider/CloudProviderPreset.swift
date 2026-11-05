//
//  CloudProviderPreset.swift
//  FlowDown
//

import Foundation

/// Connection defaults for well-known providers. Provider and product names are
/// proper nouns and are not localized.
struct CloudProviderPreset: Hashable, Identifiable {
    let id: String
    let name: String
    let contract: CloudModelAPIContract
    let baseURL: String
    let requiresAPIKey: Bool
    /// Where the user creates an API key.
    let apiKeyPage: URL?
    let headers: [String: String]
    let icon: String

    init(
        id: String,
        name: String,
        contract: CloudModelAPIContract = .chatCompletions,
        baseURL: String,
        requiresAPIKey: Bool = true,
        apiKeyPage: String? = nil,
        headers: [String: String] = [:],
        icon: String = "cloud",
    ) {
        self.id = id
        self.name = name
        self.contract = contract
        self.baseURL = baseURL
        self.requiresAPIKey = requiresAPIKey
        self.apiKeyPage = apiKeyPage.flatMap(URL.init(string:))
        self.headers = headers
        self.icon = icon
    }

    var host: String? {
        URL(string: baseURL)?.host?.lowercased()
    }
}

extension CloudProviderPreset {
    static let openAI = Self(
        id: "openai",
        name: "OpenAI",
        contract: .responses,
        baseURL: "https://api.openai.com/v1",
        apiKeyPage: "https://platform.openai.com/api-keys",
    )

    static let anthropic = Self(
        id: "anthropic",
        name: "Anthropic",
        contract: .anthropicMessages,
        baseURL: "https://api.anthropic.com/v1",
        apiKeyPage: "https://console.anthropic.com/settings/keys",
    )

    static let gemini = Self(
        id: "gemini",
        name: "Google Gemini",
        baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
        apiKeyPage: "https://aistudio.google.com/apikey",
    )

    static let openRouter = Self(
        id: "openrouter",
        name: "OpenRouter",
        baseURL: "https://openrouter.ai/api/v1",
        apiKeyPage: "https://openrouter.ai/keys",
        headers: [
            "HTTP-Referer": "https://flowdown.ai/",
            "X-Title": "FlowDown",
        ],
    )

    static let deepSeek = Self(
        id: "deepseek",
        name: "DeepSeek",
        baseURL: "https://api.deepseek.com/v1",
        apiKeyPage: "https://platform.deepseek.com/api_keys",
    )

    static let xAI = Self(
        id: "xai",
        name: "xAI",
        baseURL: "https://api.x.ai/v1",
        apiKeyPage: "https://console.x.ai",
    )

    static let mistral = Self(
        id: "mistral",
        name: "Mistral",
        baseURL: "https://api.mistral.ai/v1",
        apiKeyPage: "https://console.mistral.ai/api-keys",
    )

    static let groq = Self(
        id: "groq",
        name: "Groq",
        baseURL: "https://api.groq.com/openai/v1",
        apiKeyPage: "https://console.groq.com/keys",
    )

    static let moonshot = Self(
        id: "moonshot",
        name: "Moonshot AI",
        baseURL: "https://api.moonshot.ai/v1",
        apiKeyPage: "https://platform.moonshot.ai/console/api-keys",
    )

    static let qwen = Self(
        id: "dashscope",
        name: "Alibaba Cloud Model Studio",
        baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
        apiKeyPage: "https://bailian.console.aliyun.com/?apiKey=1",
    )

    static let zhipu = Self(
        id: "zhipu",
        name: "Zhipu AI",
        baseURL: "https://open.bigmodel.cn/api/paas/v4",
        apiKeyPage: "https://open.bigmodel.cn/usercenter/apikeys",
    )

    static let siliconFlow = Self(
        id: "siliconflow",
        name: "SiliconFlow",
        baseURL: "https://api.siliconflow.cn/v1",
        apiKeyPage: "https://cloud.siliconflow.cn/account/ak",
    )

    static let ollama = Self(
        id: "ollama",
        name: "Ollama",
        baseURL: "http://localhost:11434/v1",
        requiresAPIKey: false,
        icon: "desktopcomputer",
    )

    static let lmStudio = Self(
        id: "lmstudio",
        name: "LM Studio",
        baseURL: "http://localhost:1234/v1",
        requiresAPIKey: false,
        icon: "desktopcomputer",
    )

    /// Hosted providers, in menu order.
    static let cloud: [Self] = [
        .openAI, .anthropic, .gemini, .openRouter, .deepSeek, .xAI, .mistral, .groq,
        .moonshot, .qwen, .zhipu, .siliconFlow,
    ]

    /// Servers running on the user's machine or network.
    static let local: [Self] = [.ollama, .lmStudio]

    static let all: [Self] = cloud + local

    /// The preset whose host matches `endpoint`. Local presets also match on port so
    /// Ollama and LM Studio are told apart.
    static func matching(endpoint: String) -> Self? {
        guard let url = URL(string: endpoint), let host = url.host?.lowercased() else { return nil }
        return all.first { preset in
            guard let presetURL = URL(string: preset.baseURL), preset.host == host else { return false }
            if preset.requiresAPIKey { return true }
            return presetURL.port == url.port
        }
    }
}
