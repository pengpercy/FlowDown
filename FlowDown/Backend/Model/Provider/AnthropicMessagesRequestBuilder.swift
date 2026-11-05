//
//  AnthropicMessagesRequestBuilder.swift
//  FlowDown
//

import ChatClientKit
import Foundation

/// Translates a `ChatRequestBody` into an Anthropic Messages request body.
///
/// The body is first encoded with ChatClientKit's own (OpenAI Chat Completions)
/// encoder and then rewritten as JSON. Working on the encoded form keeps this
/// independent of ChatClientKit internals such as tool call identifiers, which
/// are not public API.
enum AnthropicMessagesRequestBuilder {
    /// Used when neither the request nor the model's body fields set `max_tokens`,
    /// which Anthropic requires. Override it per model with the `max_tokens` body field.
    static let defaultMaxTokens = 8192

    enum BuildError: LocalizedError {
        case unencodableBody

        var errorDescription: String? {
            String(localized: "Unable to encode the request for the Anthropic Messages API.")
        }
    }

    static func makeBody(
        from body: ChatRequestBody,
        model: String,
        additionalBodyField: [String: Any],
    ) throws -> [String: Any] {
        let encoded = try JSONEncoder().encode(body.mergingAdjacentAssistantMessages())
        guard let openAI = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw BuildError.unencodableBody
        }
        let sourceMessages = openAI["messages"] as? [[String: Any]] ?? []

        var output: [String: Any] = [
            "model": model,
            "max_tokens": body.maxCompletionTokens ?? defaultMaxTokens,
            "stream": true,
        ]

        let system = sourceMessages
            .filter { ["system", "developer"].contains($0["role"] as? String) }
            .compactMap { plainText(from: $0["content"]) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if !system.isEmpty { output["system"] = system }

        output["messages"] = convertMessages(sourceMessages)

        if let temperature = body.temperature {
            // Anthropic accepts 0...1.
            output["temperature"] = min(max(temperature, 0), 1)
        }

        let tools = (openAI["tools"] as? [[String: Any]] ?? []).compactMap(convertTool)
        if !tools.isEmpty {
            output["tools"] = tools
            if let choice = convertToolChoice(openAI["tool_choice"]) {
                output["tool_choice"] = choice
            }
        }

        for (key, value) in additionalBodyField {
            output[key] = value
        }
        return output
    }

    // MARK: - Messages

    static func convertMessages(_ messages: [[String: Any]]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        for message in messages {
            guard let role = message["role"] as? String else { continue }
            let converted: (role: String, blocks: [[String: Any]])
            switch role {
            case "user":
                converted = ("user", userBlocks(from: message["content"]))
            case "assistant":
                converted = ("assistant", assistantBlocks(from: message))
            case "tool":
                guard let toolCallID = message["tool_call_id"] as? String else { continue }
                let text = plainText(from: message["content"]) ?? ""
                converted = ("user", [[
                    "type": "tool_result",
                    "tool_use_id": toolCallID,
                    "content": text.isEmpty ? " " : text,
                ]])
            default:
                // system and developer are hoisted into the top-level `system` field.
                continue
            }
            guard !converted.blocks.isEmpty else { continue }
            // Anthropic requires alternating roles, so consecutive turns of one role merge.
            if var last = result.last, last["role"] as? String == converted.role {
                var blocks = last["content"] as? [[String: Any]] ?? []
                blocks.append(contentsOf: converted.blocks)
                last["content"] = blocks
                result[result.count - 1] = last
            } else {
                result.append(["role": converted.role, "content": converted.blocks])
            }
        }
        return result
    }

    private static func userBlocks(from content: Any?) -> [[String: Any]] {
        if let text = content as? String {
            return text.isEmpty ? [] : [["type": "text", "text": text]]
        }
        guard let parts = content as? [[String: Any]] else { return [] }
        return parts.compactMap { part in
            switch part["type"] as? String {
            case "text":
                guard let text = part["text"] as? String, !text.isEmpty else { return nil }
                return ["type": "text", "text": text]
            case "image_url":
                guard let image = part["image_url"] as? [String: Any],
                      let url = image["url"] as? String
                else { return nil }
                return imageBlock(from: url)
            default:
                // Audio input is not supported by the Messages API.
                return nil
            }
        }
    }

    static func imageBlock(from url: String) -> [String: Any]? {
        if url.hasPrefix("data:") {
            // data:<media type>;base64,<payload>
            guard let comma = url.firstIndex(of: ",") else { return nil }
            let header = url[url.index(url.startIndex, offsetBy: 5) ..< comma]
            guard header.hasSuffix(";base64") else { return nil }
            let mediaType = String(header.dropLast(";base64".count))
            return [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": mediaType.isEmpty ? "image/png" : mediaType,
                    "data": String(url[url.index(after: comma)...]),
                ],
            ]
        }
        return ["type": "image", "source": ["type": "url", "url": url]]
    }

    private static func assistantBlocks(from message: [String: Any]) -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        if let text = plainText(from: message["content"]), !text.isEmpty {
            blocks.append(["type": "text", "text": text])
        }
        for call in message["tool_calls"] as? [[String: Any]] ?? [] {
            guard let id = call["id"] as? String,
                  let function = call["function"] as? [String: Any],
                  let name = function["name"] as? String
            else { continue }
            blocks.append([
                "type": "tool_use",
                "id": id,
                "name": name,
                "input": toolInput(from: function["arguments"] as? String),
            ])
        }
        // Prior reasoning is not sent back: Anthropic only accepts thinking blocks with
        // the signature it issued, which the shared message model does not keep.
        return blocks
    }

    static func toolInput(from arguments: String?) -> [String: Any] {
        guard let data = arguments?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    /// Joins string content or text parts into one string.
    static func plainText(from content: Any?) -> String? {
        if let text = content as? String { return text }
        if let parts = content as? [String] { return parts.joined(separator: "\n") }
        if let parts = content as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return nil
    }

    // MARK: - Tools

    private static func convertTool(_ tool: [String: Any]) -> [String: Any]? {
        guard let function = tool["function"] as? [String: Any],
              let name = function["name"] as? String
        else { return nil }
        var schema = function["parameters"] as? [String: Any] ?? [:]
        if schema["type"] == nil { schema["type"] = "object" }
        var result: [String: Any] = ["name": name, "input_schema": schema]
        if let description = function["description"] as? String, !description.isEmpty {
            result["description"] = description
        }
        return result
    }

    private static func convertToolChoice(_ choice: Any?) -> [String: Any]? {
        if let value = choice as? String {
            switch value {
            case "auto": return ["type": "auto"]
            case "required": return ["type": "any"]
            default: return nil
            }
        }
        if let object = choice as? [String: Any],
           let function = object["function"] as? [String: Any],
           let name = function["name"] as? String
        {
            return ["type": "tool", "name": name]
        }
        return nil
    }
}
