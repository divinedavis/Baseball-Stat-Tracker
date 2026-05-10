import Foundation
import UIKit
import Supabase

/// Records product-interaction events (screen views, button taps, paywall flow,
/// purchase completion) into the Supabase `app_events` table.
///
/// Inserts run under the user's JWT — RLS allows only the owner to insert.
/// Anonymous users (not signed in) are silently skipped. Network failures
/// are logged in DEBUG and otherwise swallowed: telemetry must never break
/// the UX.
@MainActor
final class EventLogger {
    static let shared = EventLogger()
    private init() {}

    private struct EventRow: Encodable {
        let user_id: String
        let event: String
        let properties: [String: AnyJSON]
        let app_version: String?
        let os_version: String?
        let device_model: String?
    }

    private let appVersion: String? = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (v?, b?): return "\(v) (\(b))"
        case let (v?, nil): return v
        default: return nil
        }
    }()

    private let osVersion: String? = {
        let v = UIDevice.current.systemVersion
        return "iOS \(v)"
    }()

    private let deviceModel: String? = {
        var sys = utsname()
        uname(&sys)
        let mirror = Mirror(reflecting: sys.machine)
        let id = mirror.children.compactMap { element -> String? in
            guard let value = element.value as? Int8, value != 0 else { return nil }
            return String(UnicodeScalar(UInt8(value)))
        }.joined()
        return id.isEmpty ? nil : id
    }()

    /// Fire-and-forget logger. Returns immediately; insert runs on a detached
    /// task so the caller (often a SwiftUI view body) is never blocked.
    func log(_ event: String, properties: [String: AnyJSON] = [:]) {
        Task { [weak self] in
            await self?.send(event: event, properties: properties)
        }
    }

    private func send(event: String, properties: [String: AnyJSON]) async {
        guard let session = try? await SupabaseService.client.auth.session else {
            return
        }
        let row = EventRow(
            user_id: session.user.id.uuidString.lowercased(),
            event: event,
            properties: properties,
            app_version: appVersion,
            os_version: osVersion,
            device_model: deviceModel
        )
        do {
            try await SupabaseService.client
                .from("app_events")
                .insert(row)
                .execute()
        } catch {
            #if DEBUG
            print("EventLogger insert failed for \(event): \(error)")
            #endif
        }
    }
}
