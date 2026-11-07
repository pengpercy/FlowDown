//
//  MLX+Unavailable.swift
//  FlowDown
//

#if !canImport(MLX)

    import Foundation

    /// Stands in for the MLX module in builds that ship without on-device
    /// inference, so the settings and lifecycle hooks written against
    /// `MLX.GPU` and `MLX.Memory` keep compiling and simply report the
    /// device as unsupported.
    enum MLX {
        enum GPU {}

        enum Memory {
            static var cacheLimit = 0
            static func clearCache() {}
        }
    }

    /// Mirrors `MLXLMCommon`'s `Encodable.toolResult`, which web search uses
    /// to render each result as snake-case JSON for the model.
    extension Encodable {
        var toolResult: String {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            guard let data = try? encoder.encode(self) else { return "{}" }
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }

#endif
