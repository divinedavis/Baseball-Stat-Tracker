import Foundation
import Supabase

/// Calls the Barrel AI edge functions. Always uses the authenticated user's
/// JWT — the edge functions verify it and bypass RLS via the service role to
/// run quota checks. Failures surface as `AIClientError`.
@MainActor
final class AIClient {
    static let shared = AIClient()
    private init() {}

    struct ChatResponse: Codable {
        let reply: String
        let tier: String
        let monthly_remaining: Int
    }

    struct SwingResponse: Codable {
        let id: UUID
        let feedback: String
        let tier: String
        let monthly_remaining: Int
        let daily_remaining: Int
    }

    enum AIClientError: LocalizedError {
        case notSignedIn
        case quotaExceeded(reason: String, tier: String)
        case server(String)
        case decode

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in to use AI."
            case .quotaExceeded(let reason, _):
                switch reason {
                case "monthly_swings_exhausted": return "You've used all your swing analyses for this month."
                case "daily_swings_exhausted": return "Daily swing limit reached. Try again tomorrow."
                case "monthly_questions_exhausted": return "You've used all your questions for this month."
                default: return "Quota exceeded."
                }
            case .server(let msg): return msg
            case .decode: return "Couldn't parse the response."
            }
        }
    }

    /// Uploads `data` to Supabase Storage under `<userId>/<uuid>.<ext>` and
    /// returns the resulting object path.
    func uploadSwingMedia(data: Data, fileExtension: String, contentType: String) async throws -> String {
        guard let session = try? await SupabaseService.client.auth.session else {
            throw AIClientError.notSignedIn
        }
        let userId = session.user.id.uuidString
        let path = "\(userId)/\(UUID().uuidString).\(fileExtension)"
        _ = try await SupabaseService.client.storage
            .from(SupabaseConfig.storageBucket)
            .upload(
                path: path,
                file: data,
                options: FileOptions(contentType: contentType, upsert: false)
            )
        return path
    }

    func analyzeSwing(storagePath: String, mediaKind: String, note: String?) async throws -> SwingResponse {
        let body: [String: Any?] = [
            "storage_path": storagePath,
            "media_kind": mediaKind,
            "note": note,
        ]
        let data = try await invoke(name: "ai-analyze-swing", body: body)
        return try decode(data, as: SwingResponse.self)
    }

    func chat(message: String, swingId: UUID? = nil) async throws -> ChatResponse {
        let body: [String: Any?] = [
            "message": message,
            "swing_id": swingId?.uuidString,
        ]
        let data = try await invoke(name: "ai-chat", body: body)
        return try decode(data, as: ChatResponse.self)
    }

    private func invoke(name: String, body: [String: Any?]) async throws -> Data {
        let cleaned = body.compactMapValues { $0 }
        let payload = try JSONSerialization.data(withJSONObject: cleaned, options: [])
        let url = SupabaseConfig.url.appendingPathComponent("functions/v1/\(name)")

        guard let session = try? await SupabaseService.client.auth.session else {
            throw AIClientError.notSignedIn
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = payload
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        req.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AIClientError.server("No response.")
        }

        if http.statusCode == 402 {
            struct QuotaErr: Codable { let reason: String; let tier: String }
            if let q = try? JSONDecoder().decode(QuotaErr.self, from: data) {
                throw AIClientError.quotaExceeded(reason: q.reason, tier: q.tier)
            }
            throw AIClientError.quotaExceeded(reason: "unknown", tier: "free")
        }

        if !(200..<300).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error \(http.statusCode)"
            throw AIClientError.server(msg)
        }

        return data
    }

    private func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw AIClientError.decode
        }
    }
}
