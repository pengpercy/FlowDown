//
//  AnthropicMessagesStreamDecoder.swift
//  FlowDown
//

import ChatClientKit
import Foundation

/// Turns Anthropic Messages server-sent event payloads into chat chunks.
///
/// Text and thinking deltas are emitted as they arrive. A tool call is emitted
/// once its content block stops, in block order, so the caller always receives
/// complete arguments.
struct AnthropicMessagesStreamDecoder {
    struct StreamError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct PendingTool {
        var id: String
        var name: String
        var arguments: String
    }

    private var pendingTools: [Int: PendingTool] = [:]

    /// Decodes one `data:` payload.
    mutating func consume(data: String) throws -> [ChatResponseChunk] {
        guard let json = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
              let type = json["type"] as? String
        else { return [] }

        switch type {
        case "content_block_start":
            guard let index = json["index"] as? Int,
                  let block = json["content_block"] as? [String: Any]
            else { return [] }
            switch block["type"] as? String {
            case "text":
                if let text = block["text"] as? String, !text.isEmpty { return [.text(text)] }
            case "thinking":
                if let thinking = block["thinking"] as? String, !thinking.isEmpty { return [.reasoning(thinking)] }
            case "tool_use":
                let input = block["input"] as? [String: Any] ?? [:]
                pendingTools[index] = PendingTool(
                    id: block["id"] as? String ?? "",
                    name: block["name"] as? String ?? "",
                    // A non-empty start input is only replaced by deltas when they arrive.
                    arguments: input.isEmpty ? "" : Self.jsonString(input),
                )
            default:
                break
            }
            return []

        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any] else { return [] }
            switch delta["type"] as? String {
            case "text_delta":
                if let text = delta["text"] as? String, !text.isEmpty { return [.text(text)] }
            case "thinking_delta":
                if let thinking = delta["thinking"] as? String, !thinking.isEmpty { return [.reasoning(thinking)] }
            case "input_json_delta":
                if let index = json["index"] as? Int,
                   let partial = delta["partial_json"] as? String,
                   var tool = pendingTools[index]
                {
                    if tool.arguments == "{}" { tool.arguments = "" }
                    tool.arguments += partial
                    pendingTools[index] = tool
                }
            default:
                break
            }
            return []

        case "content_block_stop":
            guard let index = json["index"] as? Int, let tool = pendingTools.removeValue(forKey: index) else {
                return []
            }
            return Self.makeToolChunk(tool).map { [$0] } ?? []

        case "message_stop":
            return finish()

        case "error":
            let error = json["error"] as? [String: Any]
            let message = error?["message"] as? String ?? String(localized: "Unknown error.")
            throw StreamError(message: message)

        default:
            // message_start, message_delta, ping and future event types.
            return []
        }
    }

    /// Emits tool calls whose block never reported a stop.
    mutating func finish() -> [ChatResponseChunk] {
        let tools = pendingTools.sorted { $0.key < $1.key }.map(\.value)
        pendingTools.removeAll()
        return tools.compactMap(Self.makeToolChunk)
    }

    private static func makeToolChunk(_ tool: PendingTool) -> ChatResponseChunk? {
        guard !tool.name.isEmpty else { return nil }
        let arguments = tool.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        return makeToolRequest(id: tool.id, name: tool.name, args: arguments.isEmpty ? "{}" : arguments)
            .map(ChatResponseChunk.tool)
    }

    /// `ToolRequest` has no public initializer; it is built through its public `Codable` form.
    static func makeToolRequest(id: String, name: String, args: String) -> ToolRequest? {
        let identifier = id.isEmpty ? UUID().uuidString : id
        let payload = ["id": identifier, "name": name, "args": args]
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return try? JSONDecoder().decode(ToolRequest.self, from: data)
    }

    private static func jsonString(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}
