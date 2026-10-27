import Foundation

/// Meta's Model API: chat completions in the OpenAI format, with the answer held to a
/// JSON schema so it can be decoded as it is.
struct ModelClient {
    enum Part {
        case text(String)
        case jpeg(Data)
    }

    /// Tokens spent, and what they cost at Standard prices.
    struct Usage: Codable {
        var prompt = 0
        var completion = 0
        /// In US dollars.
        var cost = 0.0

        static func += (a: inout Usage, b: Usage) {
            a.prompt += b.prompt
            a.completion += b.completion
            a.cost += b.cost
        }
    }

    enum Problem: LocalizedError {
        case noKey
        case failed(status: Int, message: String)
        case cutOff
        case refused(String)

        var errorDescription: String? {
            switch self {
            case .noKey: "No MODEL_API_KEY in the environment or in .env."
            case .failed(let status, let message): "The model service answered \(status): \(message)"
            case .cutOff: "The model's answer was cut off before it finished."
            case .refused(let reason): "The model declined: \(reason)"
            }
        }
    }

    static let base = URL(string: "https://api.meta.ai/v1")!

    /// Dollars per million tokens: input, cached input, output. Never the `-contributor`
    /// models: they are cheaper because Meta trains on what is sent to them.
    static let prices: [String: (input: Double, cached: Double, output: Double)] = [
        "muse-spark-1.3": (1.25, 0.15, 4.25),
        "muse-wonder-1.0": (4, 0.20, 20),
    ]

    let key: String
    var model = "muse-spark-1.3"
    /// minimal, low, medium, high or xhigh. Muse Spark always reasons; the reasoning counts
    /// against `max_completion_tokens`.
    var reasoning = "low"

    /// The key and settings from the environment, or from `.env` until the key moves to
    /// our server. Variables set in the shell win over the file.
    static func fromEnvironment() throws -> ModelClient {
        var values = ProcessInfo.processInfo.environment
        for file in envFiles {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where !line.hasPrefix("#") {
                let pair = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces.union(["\"", "'"])) }
                if pair.count == 2, values[pair[0]] == nil { values[pair[0]] = pair[1] }
            }
        }
        guard let key = values["MODEL_API_KEY"], !key.isEmpty else { throw Problem.noKey }
        var client = ModelClient(key: key)
        if let model = values["MODEL"], !model.isEmpty { client.model = model }
        if let reasoning = values["MODEL_REASONING"], !reasoning.isEmpty { client.reasoning = reasoning }
        return client
    }

    /// The working directory, then the checkout a development build was made from.
    private static var envFiles: [URL] {
        let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return [URL(fileURLWithPath: FileManager.default.currentDirectoryPath), checkout].map { $0.appending(path: ".env") }
    }

    /// Asks once and decodes the answer as `T`. `schema` must follow the strict rules: every
    /// object closed with `additionalProperties: false` and all its fields required.
    func answer<T: Decodable>(_ type: T.Type, schemaName: String, schema: [String: Any], instructions: String, input: [Part], maxTokens: Int = 16000) async throws -> (T, Usage) {
        let content: [[String: Any]] = input.map { part in
            switch part {
            case .text(let text): ["type": "text", "text": text]
            case .jpeg(let data): ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + data.base64EncodedString()]]
            }
        }
        let body: [String: Any] = [
            "model": model,
            "reasoning_effort": reasoning,
            "max_completion_tokens": maxTokens,
            "messages": [
                ["role": "developer", "content": instructions],
                ["role": "user", "content": content],
            ],
            "response_format": ["type": "json_schema", "json_schema": ["name": schemaName, "strict": true, "schema": schema]],
        ]
        var request = URLRequest(url: Self.base.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // Reasoning over a screenshot can take a minute or more.
        request.timeoutInterval = 300

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Problem.failed(status: status, message: Self.message(in: data)) }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let completion = try decoder.decode(Completion.self, from: data)
        let usage = self.usage(completion.usage)
        guard let choice = completion.choices.first else { throw Problem.failed(status: status, message: "no answer") }
        if let refusal = choice.message.refusal { throw Problem.refused(refusal) }
        switch choice.finishReason {
        case "length": throw Problem.cutOff
        case "content_filter": throw Problem.refused("content filter")
        default: break
        }
        return (try JSONDecoder().decode(T.self, from: Data((choice.message.content ?? "").utf8)), usage)
    }

    private func usage(_ counted: Completion.Counted) -> Usage {
        let price = Self.prices[model] ?? (0, 0, 0)
        let cached = counted.promptTokensDetails?.cachedTokens ?? 0
        let cost = Double(counted.promptTokens - cached) * price.input + Double(cached) * price.cached + Double(counted.completionTokens) * price.output
        return Usage(prompt: counted.promptTokens, completion: counted.completionTokens, cost: cost / 1_000_000)
    }

    /// The service's own words for what went wrong, when it gives them.
    private static func message(in data: Data) -> String {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = json?["error"] as? [String: Any], let message = error["message"] as? String { return message }
        return String(decoding: data.prefix(300), as: UTF8.self)
    }

    private struct Completion: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
                let refusal: String?
            }

            let finishReason: String?
            let message: Message
        }

        struct Counted: Decodable {
            struct Details: Decodable {
                let cachedTokens: Int?
            }

            let promptTokens: Int
            let completionTokens: Int
            let promptTokensDetails: Details?
        }

        let choices: [Choice]
        let usage: Counted
    }
}
