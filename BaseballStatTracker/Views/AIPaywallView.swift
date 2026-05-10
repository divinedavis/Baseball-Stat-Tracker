import SwiftUI
import StoreKit

/// "What's New"–style paywall: hero copy, three feature rows, two tier
/// cards (Standard / Pro), and a primary CTA at the bottom. Triggered from
/// the profile menu's "Use AI" button.
struct AIPaywallView: View {
    @EnvironmentObject private var billing: BillingStore
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProductId: String = BillingStore.proId

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    features
                    plans
                    fineprint
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 24)
            }
            footer
        }
        .background(Color(.systemBackground))
        .task {
            await billing.loadProducts()
            await billing.refreshEntitlements()
            EventLogger.shared.log("paywall_shown", properties: [
                "current_tier": .string(billing.tier.rawValue),
            ])
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.tint)
                .padding(.bottom, 4)
            Text("Coach in your pocket")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Upload a swing — get expert feedback in seconds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 18) {
            FeatureRow(
                icon: "video.fill.badge.checkmark",
                title: "Frame-by-frame swing analysis",
                subtitle: "Photo or short video. Barrel highlights what's working and the one thing to fix."
            )
            FeatureRow(
                icon: "bubble.left.and.bubble.right.fill",
                title: "Ask anything about hitting",
                subtitle: "Stance, timing, pitch recognition. Plain answers, no fluff."
            )
            FeatureRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "Built on your real at-bats",
                subtitle: "Pulls in your slash line so the advice fits your game, not a textbook."
            )
        }
    }

    private var plans: some View {
        VStack(spacing: 12) {
            ForEach(billing.products, id: \.id) { product in
                PlanCard(
                    product: product,
                    selected: selectedProductId == product.id,
                    isPro: product.id == BillingStore.proId
                )
                .onTapGesture { selectedProductId = product.id }
            }
            if billing.isLoadingProducts {
                ProgressView().padding(.vertical, 8)
            } else if billing.products.isEmpty {
                Text("Subscriptions are loading…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fineprint: some View {
        VStack(spacing: 8) {
            Text(
                "Auto-renewable monthly subscription. Payment is charged to your "
                + "Apple Account at confirmation of purchase. Subscription auto-renews "
                + "unless cancelled at least 24 hours before the end of the current "
                + "period. Manage or cancel in Settings → Apple ID → Subscriptions."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)

            HStack(spacing: 16) {
                Button("Restore Purchases") {
                    Task { await billing.restore() }
                }
                .font(.footnote)
                Link("Privacy",
                     destination: URL(string: "https://github.com/divinedavis/Baseball-Stat-Tracker#privacy")!)
                    .font(.footnote)
                Link("Terms (EULA)",
                     destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    .font(.footnote)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 10) {
                if let err = billing.lastError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                Button(action: handlePurchase) {
                    HStack {
                        if billing.purchasingProductId != nil {
                            ProgressView().tint(.white)
                        }
                        Text(ctaTitle)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(.tint))
                }
                .disabled(canPurchase == false)

                Button("Maybe later") { dismiss() }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - State

    private var selectedProduct: Product? {
        billing.products.first(where: { $0.id == selectedProductId })
    }

    private var ctaTitle: String {
        if let p = selectedProduct {
            return "Subscribe — \(p.displayPrice) / mo"
        }
        return "Subscribe"
    }

    private var canPurchase: Bool {
        billing.purchasingProductId == nil
            && selectedProduct != nil
            && auth.supabaseUserId != nil
    }

    private func handlePurchase() {
        guard let product = selectedProduct,
              let userId = auth.supabaseUserId else { return }
        EventLogger.shared.log("subscribe_tapped", properties: [
            "product_id": .string(product.id),
            "price": .string(product.displayPrice),
        ])
        Task {
            await billing.purchase(product, supabaseUserId: userId)
            if billing.tier != .free {
                EventLogger.shared.log("subscribe_completed", properties: [
                    "product_id": .string(product.id),
                    "tier": .string(billing.tier.rawValue),
                ])
                dismiss()
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PlanCard: View {
    let product: Product
    let selected: Bool
    let isPro: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .font(.title2)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(product.displayName).font(.headline)
                    if isPro {
                        Text("Most popular")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.tint.opacity(0.18)))
                            .foregroundStyle(.tint)
                    }
                }
                Text(product.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(product.displayPrice).font(.headline)
                Text("/ month").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? Color.accentColor : .clear, lineWidth: 2)
        )
    }
}

#Preview {
    AIPaywallView()
        .environmentObject(AuthStore())
        .environmentObject(BillingStore())
}
