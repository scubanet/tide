import Foundation

/// Thin client for the ElevenLabs Text-to-Speech REST API.
///
/// Two endpoints used:
///   1. `GET /v1/voices` — list available voices for the API-key holder
///   2. `POST /v1/text-to-speech/{voice_id}` — synthesise text to MP3 bytes
///
/// We use the non-streaming endpoint. Per-sentence latency is ~500–1200ms,
/// which is acceptable for our use (sentences flushed as Claude streams).
/// Switch to `/v1/text-to-speech/{voice_id}/stream` later if needed.
public struct ElevenLabsClient: Sendable {
  public let apiKey: String
  public let session: URLSession

  public init(apiKey: String, session: URLSession = .shared) {
    self.apiKey = apiKey
    self.session = session
  }

  public struct Voice: Sendable, Codable, Identifiable, Hashable {
    public let voice_id: String
    public let name: String
    public let category: String?
    public var id: String { voice_id }
  }

  private struct VoicesResponse: Decodable {
    let voices: [Voice]
  }

  /// Fetches the list of voices accessible to this API key. Free-tier
  /// users see ~10 default voices; paid tiers can clone their own.
  public func listVoices() async throws -> [Voice] {
    var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/voices")!)
    req.httpMethod = "GET"
    req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: req)
    try Self.checkOK(response)
    return try JSONDecoder().decode(VoicesResponse.self, from: data).voices
  }

  /// Synthesises `text` with the given voice. Returns raw audio bytes
  /// (MP3 mono, 44.1 kHz by default). Caller is responsible for playback.
  public func synthesize(
    text: String,
    voiceID: String,
    modelID: String = "eleven_multilingual_v2"
  ) async throws -> Data {
    let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")!
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

    let body: [String: Any] = [
      "text": text,
      "model_id": modelID,
      "voice_settings": [
        "stability": 0.5,
        "similarity_boost": 0.75,
      ],
    ]
    req.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await session.data(for: req)
    try Self.checkOK(response)
    return data
  }

  public enum Error: Swift.Error, Equatable {
    case unauthorized
    case rateLimit
    case server(code: Int, body: String)
    case network(String)
  }

  private static func checkOK(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else {
      throw Error.network("non-HTTP response")
    }
    switch http.statusCode {
    case 200..<300: return
    case 401: throw Error.unauthorized
    case 429: throw Error.rateLimit
    default:
      throw Error.server(code: http.statusCode, body: "")
    }
  }
}
