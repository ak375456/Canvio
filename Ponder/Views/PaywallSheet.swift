//
//  PaywallSheet.swift
//  Ponder
//

import SwiftUI
import StoreKit

struct PaywallSheet: View {
    var onPurchaseCompleted: (() -> Void)? = nil

    @ObservedObject private var pro = ProManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: ProManager.Plan = .yearly

    private let plans: [PaywallPlan] = [
        .init(plan: .monthly,  title: "Monthly Cloud", badge: nil),
        .init(plan: .yearly,   title: "Yearly Cloud",  badge: "Popular"),
        .init(plan: .local,    title: "Local Pro",     badge: "No Sync"),
        .init(plan: .lifetime, title: "Lifetime Pro",  badge: "Best Value")
    ]

    private var visiblePlans: [PaywallPlan] {
        pro.ownsLocalPro ? plans.filter { $0.plan != .local } : plans
    }

    private var pricingColumns: [GridItem] {
        let count = pro.ownsLocalPro ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    featureList
                    pricingCards
                    ctaSection
                }
                .padding(24)
            }
        }
        .background(platformBackground)
        .task {
            await pro.loadProducts()
            await pro.refreshStatus()
            if pro.isEligibleForLifetimeUpgrade {
                selectedPlan = .lifetime
            }
        }
        .onChange(of: pro.isEligibleForLifetimeUpgrade) { _, isEligible in
            if isEligible {
                selectedPlan = .lifetime
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [
                    Color.accentColor,
                    Color(red: 0.08, green: 0.12, blue: 0.26),
                    Color(red: 0.03, green: 0.04, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 210)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 48, height: 48)
                        .overlay {
                            Image(systemName: "square.on.square.dashed")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.white)
                        }

                    Text("Canvio")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(pro.ownsLocalPro ? "Add Cloud Sync" : "Unlock Canvio Pro")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(pro.ownsLocalPro
                         ? "Choose monthly, yearly or a one-time lifetime upgrade"
                         : "Choose cloud sync or a one-time local upgrade")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.74))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .padding(.top, 18)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.82))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .padding(20)
        }
    }

    // MARK: - Features

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if pro.ownsLocalPro {
                localProOwnedRow
            } else {
                featureRow(icon: "checkmark.circle.fill", title: "Create unlimited canvases")
                featureRow(icon: "checkmark.circle.fill", title: "Create unlimited pages inside every canvas")
                featureRow(icon: "checkmark.circle.fill", title: "Add unlimited images, audio and tables")
                featureRow(icon: "checkmark.circle.fill", title: "Use templates without image, audio and table limits")
                featureRow(icon: "checkmark.circle.fill", title: "All grid styles — grid, lines, columns, blank")
                featureRow(icon: "checkmark.circle.fill", title: "Premium canvas background palettes")
                featureRow(icon: "checkmark.circle.fill", title: "Custom light and dark canvas background colors")
                featureRow(icon: "checkmark.circle.fill", title: "Continuous color cycling within every stroke")
                featureRow(icon: "checkmark.circle.fill", title: "Watermark-free PNG and PDF exports")
                featureRow(icon: "checkmark.circle.fill", title: "Import custom .ttf fonts for text")
            }
            syncFeatureRow
        }
    }

    private var localProOwnedRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("Local Pro is already unlocked")
                    .font(.headline.weight(.bold))

                Text("Your one-time Local Pro purchase remains yours.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    private func featureRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var syncFeatureRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: selectedPlan.includesCloudSync ? "icloud.fill" : "icloud.slash.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(selectedPlan.includesCloudSync ? Color.accentColor : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(selectedPlan.includesCloudSync
                     ? "Sync across iPhone, iPad and Mac"
                     : "Cloud sync is not included")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                Text(selectedPlan.includesCloudSync
                     ? "Included with Cloud Pro and Lifetime Pro"
                     : "Your canvases remain local to each device")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selectedPlan.includesCloudSync ? Color.accentColor : .secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            selectedPlan.includesCloudSync
                ? Color.accentColor.opacity(0.12)
                : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    selectedPlan.includesCloudSync
                        ? Color.accentColor.opacity(0.25)
                        : Color.secondary.opacity(0.14),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Pricing cards

    private var pricingCards: some View {
        LazyVGrid(
            columns: pricingColumns,
            spacing: 10
        ) {
            ForEach(visiblePlans) { option in
                priceCard(option)
            }
        }
    }

    private func priceCard(_ option: PaywallPlan) -> some View {
        let isSelected = selectedPlan == option.plan
        let isOwned = isPlanOwned(option.plan)
        let purchasePlan = purchasePlan(for: option.plan)

        return Button {
            withAnimation(.spring(duration: 0.22)) {
                selectedPlan = option.plan
            }
        } label: {
            VStack(spacing: 8) {
                Text(cardTitle(for: option))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Text(isOwned ? "Owned" : displayPrice(for: purchasePlan))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isOwned ? Color.accentColor : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)

                Text(cardBadge(for: option) ?? " ")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(cardBadge(for: option) == nil ? .clear : Color.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 112)
            .padding(.horizontal, 8)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.14),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isOwned)
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 12) {
            if let error = pro.errorMessage,
               !error.lowercased().contains("cancel") {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Button {
                Task {
                    let success = await pro.purchase(purchasePlan(for: selectedPlan))
                    if success {
                        dismiss()
                        onPurchaseCompleted?()
                    }
                }
            } label: {
                HStack {
                    if pro.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(ctaTitle)
                            .font(.headline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(pro.isLoading || isPlanOwned(selectedPlan))

            Button {
                Task {
                    await pro.restorePurchases()
                    if pro.canUseCloudSync {
                        dismiss()
                        onPurchaseCompleted?()
                    } else if pro.ownsLocalPro {
                        selectedPlan = .lifetime
                    }
                }
            } label: {
                Text("Restore Purchases")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(pro.isLoading)

            HStack(spacing: 4) {
                Text(purchasePlan(for: selectedPlan) == .local
                     || purchasePlan(for: selectedPlan) == .lifetime
                     || purchasePlan(for: selectedPlan) == .lifetimeUpgrade
                     ? "One-time payment · Billed by Apple ·"
                     : "Auto-renews · Cancel anytime · Billed by Apple ·")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Link("Terms", destination: URL(string: "https://ak375456.github.io/canvio-site/terms.html")!)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("&")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Link("Privacy", destination: URL(string: "https://ak375456.github.io/canvio-site/privacy.html")!)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - StoreKit price helpers

    private func product(for plan: ProManager.Plan) -> Product? {
        pro.products.first { $0.id == plan.rawValue }
    }

    private func purchasePlan(for displayedPlan: ProManager.Plan) -> ProManager.Plan {
        if displayedPlan == .lifetime, pro.isEligibleForLifetimeUpgrade {
            return .lifetimeUpgrade
        }
        return displayedPlan
    }

    private func isPlanOwned(_ plan: ProManager.Plan) -> Bool {
        switch plan {
        case .local:
            return pro.ownsLocalPro
        case .lifetime:
            return pro.hasLifetimeAccess
        case .monthly, .yearly, .lifetimeUpgrade:
            return false
        }
    }

    private func cardTitle(for option: PaywallPlan) -> String {
        if option.plan == .lifetime, pro.isEligibleForLifetimeUpgrade {
            return "Lifetime Upgrade"
        }
        return option.title
    }

    private func cardBadge(for option: PaywallPlan) -> String? {
        if isPlanOwned(option.plan) {
            return "Purchased"
        }
        if option.plan == .lifetime, pro.isEligibleForLifetimeUpgrade {
            return "Local Pro Credit"
        }
        return option.badge
    }

    private var ctaTitle: String {
        if isPlanOwned(selectedPlan) {
            return "Already Purchased"
        }

        let plan = purchasePlan(for: selectedPlan)
        let action = plan == .lifetimeUpgrade ? "Upgrade to" : "Get"
        return "\(action) \(purchaseName(for: plan)) — \(displayPrice(for: plan))"
    }

    private func displayPrice(for plan: ProManager.Plan) -> String {
        guard let product = product(for: plan) else {
            return fallbackPrice(for: plan)
        }

        switch plan {
        case .monthly:
            return "\(product.displayPrice)/month"
        case .yearly:
            return "\(product.displayPrice)/year"
        case .local:
            return "\(product.displayPrice) once"
        case .lifetime:
            return "\(product.displayPrice) once"
        case .lifetimeUpgrade:
            return "\(product.displayPrice) once"
        }
    }

    private func fallbackPrice(for plan: ProManager.Plan) -> String {
        switch plan {
        case .monthly:
            return "Loading..."
        case .yearly:
            return "Loading..."
        case .local, .lifetime, .lifetimeUpgrade:
            return "Loading..."
        }
    }

    private func purchaseName(for plan: ProManager.Plan) -> String {
        switch plan {
        case .monthly, .yearly:
            return "Cloud Pro"
        case .local:
            return "Local Pro"
        case .lifetime:
            return "Lifetime Pro"
        case .lifetimeUpgrade:
            return "Lifetime Pro"
        }
    }

    private var platformBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}

private struct PaywallPlan: Identifiable {
    let plan: ProManager.Plan
    let title: String
    let badge: String?

    var id: ProManager.Plan { plan }
}
