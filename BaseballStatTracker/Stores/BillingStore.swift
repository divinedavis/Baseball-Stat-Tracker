import Foundation
import StoreKit
import Supabase

enum AITier: String, Codable {
    case free
    case standard
    case pro

    var monthlySwings: Int {
        switch self {
        case .free: return 2
        case .standard: return 15
        case .pro: return 50
        }
    }
    var dailySwings: Int {
        switch self {
        case .free: return 2
        case .standard: return 5
        case .pro: return 15
        }
    }
    var monthlyQuestions: Int {
        switch self {
        case .free: return 5
        case .standard: return 30
        case .pro: return -1
        }
    }
    var displayName: String {
        switch self {
        case .free: return "Free"
        case .standard: return "Barrel AI Standard"
        case .pro: return "Barrel AI Pro"
        }
    }
}

/// StoreKit 2 wrapper for the Barrel AI subscriptions.
///
/// On launch we attach a `Transaction.updates` listener so the app reacts to
/// renewals, refunds, and family-share grants without a relaunch. Tier is
/// derived from the local entitlements; the server view comes from the
/// `subscriptions` row updated by the StoreKit webhook.
@MainActor
final class BillingStore: ObservableObject {
    static let standardId = "com.divinedavis.BaseballStatTracker.aistandard.monthly"
    static let proId = "com.divinedavis.BaseballStatTracker.aipro.monthly"
    static let allIds = [standardId, proId]

    @Published private(set) var products: [Product] = []
    @Published private(set) var tier: AITier = .free
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var purchasingProductId: String?
    @Published var lastError: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handleTransactionResult(result)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let fetched = try await Product.products(for: Self.allIds)
            products = fetched.sorted { lhs, rhs in
                lhs.id == Self.standardId && rhs.id == Self.proId
            }
        } catch {
            lastError = "Failed to load products: \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        var resolved: AITier = .free
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result else { continue }
            if tx.revocationDate == nil, tx.expirationDate.map({ $0 > .now }) ?? true {
                if tx.productID == Self.proId {
                    resolved = .pro
                } else if tx.productID == Self.standardId, resolved != .pro {
                    resolved = .standard
                }
            }
        }
        // Fall back to the server's view of the subscription. Catches:
        //  - admin / promo grants that don't go through StoreKit
        //  - newly-installed devices where Transaction.currentEntitlements
        //    hasn't synced yet
        //  - webhook-updated state after a purchase on another device
        if resolved == .free, let serverTier = await fetchServerTier() {
            resolved = serverTier
        }
        tier = resolved
    }

    private struct SubscriptionRow: Decodable {
        let tier: String
        let expires_at: Date?
    }

    private func fetchServerTier() async -> AITier? {
        do {
            let rows: [SubscriptionRow] = try await SupabaseService.client
                .from("subscriptions")
                .select("tier, expires_at")
                .execute()
                .value
            guard let row = rows.first else { return nil }
            if let expires = row.expires_at, expires < Date() { return .free }
            return AITier(rawValue: row.tier)
        } catch {
            return nil
        }
    }

    func purchase(_ product: Product, supabaseUserId: UUID) async {
        purchasingProductId = product.id
        defer { purchasingProductId = nil }
        do {
            let result = try await product.purchase(
                options: [.appAccountToken(supabaseUserId)]
            )
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    await tx.finish()
                    await refreshEntitlements()
                }
            case .userCancelled:
                break
            case .pending:
                lastError = "Purchase pending approval."
            @unknown default:
                break
            }
        } catch {
            lastError = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastError = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func handleTransactionResult(_ result: VerificationResult<Transaction>) async {
        if case .verified(let tx) = result {
            await tx.finish()
            await refreshEntitlements()
        }
    }
}
