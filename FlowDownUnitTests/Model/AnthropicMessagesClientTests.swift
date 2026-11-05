//
//  AnthropicMessagesClientTests.swift
//  FlowDownUnitTests
//

import ChatClientKit
@testable import FlowDown
import Foundation
import Testing

struct AnthropicMessagesClientTests {
    private func makeBody() -> ChatRequestBody {
        ChatRequestBody(
            messages: [
                .system(content: .text("Be brief.")),
                .developer(content: .text("Use tools.")),
                .user(content: .parts([
                    .text("What is in this picture?"),
                    .imageURL(URL(string: "data:image/jpeg;base64,QUJD")!),
                ])),
                .assistant(
                    content: .text("Checking."),
                    toolCalls: [.init(id: "call_1", function: .init(name: "lookup", arguments: #"{"q":"cat"}"#))],
                ),
                .tool(content: .text("A cat."), toolCallID: "call_1"),
                .user(content: .text("Thanks")),
            ],
            temperature: 1.5,
            tools: [
                .function(
                    name: "lookup",
                    description: "Look something up.",
                    parameters: ["properties": .object(["q": .object(["type": .string("string")])])],
                    strict: nil,
                ),
            ],
            toolChoice: .required,
        )
    }

    @Test
    func makeBody_translatesChatRequest() throws {
        let body = try AnthropicMessagesRequestBuilder.makeBody(
            from: makeBody(),
            model: "claude-test",
            additionalBodyField: ["max_tokens": 1024],
        )
        #expect(body["model"] as? String == "claude-test")
        #expect(body["stream"] as? Bool == true)
        #expect(body["max_tokens"] as? Int == 1024)
        #expect(body["system"] as? String == "Be brief.\n\nUse tools.")
        #expect(body["temperature"] as? Double == 1)

        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "user"])

        let firstBlocks = try #require(messages[0]["content"] as? [[String: Any]])
        #expect(firstBlocks.map { $0["type"] as? String } == ["text", "image"])
        let source = try #require(firstBlocks[1]["source"] as? [String: Any])
        #expect(source["type"] as? String == "base64")
        #expect(source["media_type"] as? String == "image/jpeg")
        #expect(source["data"] as? String == "QUJD")

        let assistantBlocks = try #require(messages[1]["content"] as? [[String: Any]])
        #expect(assistantBlocks.map { $0["type"] as? String } == ["text", "tool_use"])
        #expect(assistantBlocks[1]["id"] as? String == "call_1")
        #expect((assistantBlocks[1]["input"] as? [String: Any])?["q"] as? String == "cat")

        // The tool result and the following user turn merge into one user message.
        let lastBlocks = try #require(messages[2]["content"] as? [[String: Any]])
        #expect(lastBlocks.map { $0["type"] as? String } == ["tool_result", "text"])
        #expect(lastBlocks[0]["tool_use_id"] as? String == "call_1")

        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect(tools.first?["name"] as? String == "lookup")
        let schema = try #require(tools.first?["input_schema"] as? [String: Any])
        #expect(schema["type"] as? String == "object")
        #expect((body["tool_choice"] as? [String: Any])?["type"] as? String == "any")
    }

    @Test
    func makeBody_withoutMaxTokens_usesDefault() throws {
        let body = try AnthropicMessagesRequestBuilder.makeBody(
            from: ChatRequestBody(messages: [.user(content: .text("Hi"))]),
            model: "claude-test",
            additionalBodyField: [:],
        )
        #expect(body["max_tokens"] as? Int == AnthropicMessagesRequestBuilder.defaultMaxTokens)
        #expect(body["tools"] == nil)
        #expect(body["system"] == nil)
    }

    @Test
    func makeURLRequest_setsAnthropicHeaders() throws {
        let client = AnthropicMessagesChatClient(
            model: "claude-test",
            endpoint: "https://api.anthropic.com/v1/messages",
            apiKey: "sk-ant",
        )
        let request = try client.makeURLRequest(body: ChatRequestBody(messages: [.user(content: .text("Hi"))]))
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == CloudProvider.anthropicVersion)
    }

    @Test
    func streamDecoder_emitsTextReasoningAndTools() throws {
        var decoder = AnthropicMessagesStreamDecoder()
        let events = [
            #"{"type":"message_start","message":{"id":"msg"}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Hmm"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello"}}"#,
            #"{"type":"content_block_stop","index":1}"#,
            #"{"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_1","name":"lookup","input":{}}}"#,
            #"{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"q\":"}}"#,
            #"{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"\"cat\"}"}}"#,
            #"{"type":"ping"}"#,
            #"{"type":"content_block_stop","index":2}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"tool_use"}}"#,
            #"{"type":"message_stop"}"#,
        ]
        var chunks: [ChatResponseChunk] = []
        for event in events {
            chunks += try decoder.consume(data: event)
        }
        chunks += decoder.finish()

        #expect(chunks.count == 3)
        #expect(chunks[0] == .reasoning("Hmm"))
        #expect(chunks[1] == .text("Hello"))
        let tool = try #require(chunks[2].toolValue)
        #expect(tool.id == "toolu_1")
        #expect(tool.name == "lookup")
        #expect(tool.args == #"{"q":"cat"}"#)
    }

    @Test
    func streamDecoder_toolWithoutInput_reportsEmptyObject() throws {
        var decoder = AnthropicMessagesStreamDecoder()
        _ = try decoder.consume(data: #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t","name":"now","input":{}}}"#)
        let chunks = try decoder.consume(data: #"{"type":"content_block_stop","index":0}"#)
        #expect(chunks.first?.toolValue?.args == "{}")
    }

    @Test
    func streamDecoder_errorEvent_throwsMessage() {
        var decoder = AnthropicMessagesStreamDecoder()
        #expect(throws: AnthropicMessagesStreamDecoder.StreamError.self) {
            _ = try decoder.consume(data: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
        }
    }
}
