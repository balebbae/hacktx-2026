// Familiar experimental skeleton: spoken text -> Muse Image -> local image file.
//
// This file is intentionally standalone and is not wired into the iOS target yet.
// It is a one-off feasibility probe for the later Familiar integration.
//
// Plan for the full feature:
// 1. Feed the wearer's transcript into `generate(prompt:)` after speech finalizes.
// 2. Add an explicit user command/confirmation before sending text off-device.
// 3. Move the API key into the app's existing Secrets.xcconfig -> Info.plist path.
// 4. Return `GeneratedImage` to a UI or accessibility flow instead of writing a file.
// 5. Add cancellation, request limits, image caching, and an Apple/local fallback.
// 6. Never send camera frames or face data; this proof of concept sends text only.
//
// Build/run on macOS with Swift installed:
//   swiftc -parse-as-library samples/muse/image.swift -o /tmp/muse-image-skeleton
//   /tmp/muse-image-skeleton "a simple high-contrast map of a park entrance"
//
// If no command-line prompt is supplied, the program reads one prompt from stdin.
// The root .env is ignored by git and must contain:
//   META_API_KEY=...       (spaces around `=` are also accepted)

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct GeneratedImage {
    let bytes: Data
    let format: String
}

final class MuseImageClient {
    enum ClientError: LocalizedError {
        case missingAPIKey
        case emptyPrompt
        case httpStatus(Int, String)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "META_API_KEY is missing from .env or the process environment."
            case .emptyPrompt:
                return "The spoken prompt was empty."
            case let .httpStatus(status, message):
                return "Muse Image returned HTTP \(status): \(message)"
            case .malformedResponse:
                return "Muse Image returned no usable image data."
            }
        }
    }

    private struct RequestBody: Encodable {
        let model: String
        let prompt: String
        let n: Int
        let responseFormat: String
        let outputFormat: String

        enum CodingKeys: String, CodingKey {
            case model, prompt, n
            case responseFormat = "response_format"
            case outputFormat = "output_format"
        }
    }

    private struct ResponseBody: Decodable {
        struct Image: Decodable {
            let b64JSON: String?
            let url: URL?

            enum CodingKeys: String, CodingKey {
                case b64JSON = "b64_json"
                case url
            }
        }

        let data: [Image]?
    }

    static let endpoint = URL(string: "https://api.meta.ai/v1/images/generations")!
    static let model = "muse-image-1.0"

    private let apiKey: String?
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(apiKey: String? = nil, session: URLSession = .shared) {
        self.apiKey = apiKey ?? Self.environmentAPIKey()
        self.session = session
    }

    func generate(prompt: String) async throws -> GeneratedImage {
        let cleanedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPrompt.isEmpty else { throw ClientError.emptyPrompt }
        guard let apiKey, !apiKey.isEmpty else { throw ClientError.missingAPIKey }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(RequestBody(
            model: Self.model,
            prompt: cleanedPrompt,
            n: 1,
            responseFormat: "b64_json",
            outputFormat: "png"
        ))

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClientError.httpStatus(status, message)
        }

        let body = try decoder.decode(ResponseBody.self, from: data)
        guard let first = body.data?.first else { throw ClientError.malformedResponse }

        if let encoded = first.b64JSON, let imageData = Data(base64Encoded: encoded) {
            return GeneratedImage(bytes: imageData, format: "png")
        }

        // Keep URL responses usable if response_format is changed during experimentation.
        if let imageURL = first.url {
            let (imageData, imageResponse) = try await session.data(from: imageURL)
            let imageStatus = (imageResponse as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(imageStatus) else {
                throw ClientError.httpStatus(imageStatus, "Could not download the generated image")
            }
            return GeneratedImage(bytes: imageData, format: "png")
        }

        throw ClientError.malformedResponse
    }

    private static func environmentAPIKey() -> String? {
        if let value = ProcessInfo.processInfo.environment["META_API_KEY"], !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["MODEL_API_KEY"], !value.isEmpty {
            return value
        }
        return loadDotEnvValue(named: "META_API_KEY")
    }

    private static func loadDotEnvValue(named name: String) -> String? {
        let path = FileManager.default.currentDirectoryPath + "/.env"
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }

        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == name else { continue }
            return String(parts[1])
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
        }
        return nil
    }
}

@main
struct MuseImageOneOff {
    static func main() async {
        do {
            let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")
            let spokenText: String
            if prompt.isEmpty {
                spokenText = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
            } else {
                spokenText = prompt
            }

            let image = try await MuseImageClient().generate(prompt: spokenText)
            // Run from the repository root, as with the .env lookup above.
            let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("samples/muse/output", isDirectory: true)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let outputURL = outputDirectory.appendingPathComponent("muse-image-output.\(image.format)")
            try image.bytes.write(to: outputURL, options: .atomic)
            print("Generated image written to \(outputURL.path)")
        } catch {
            print("Muse Image test failed: \(error.localizedDescription)")
        }
    }
}
