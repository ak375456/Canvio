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
        .init(plan: .monthly,  title: "Monthly",  badge: nil),
        .init(plan: .yearly,   title: "Yearly",   badge: "Save 16%"),
        .init(plan: .lifetime, title: "Lifetime", badge: "Best Value")
    ]

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
                    Text("Unlock Canvio Pro")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Everything you need to think visually")
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
            featureRow(icon: "checkmark.circle.fill", title: "Create unlimited canvases")
            featureRow(icon: "checkmark.circle.fill", title: "Create unlimited pages inside every canvas")
            featureRow(icon: "checkmark.circle.fill", title: "Add unlimited images, audio and tables")
            featureRow(icon: "checkmark.circle.fill", title: "Use templates without image, audio and table limits")
            featureRow(icon: "checkmark.circle.fill", title: "All grid styles — grid, lines, columns, blank")
            featureRow(icon: "checkmark.circle.fill", title: "Premium canvas background palettes")
            featureRow(icon: "checkmark.circle.fill", title: "Custom light and dark canvas background colors")
            featureRow(icon: "checkmark.circle.fill", title: "Watermark-free PNG and PDF exports")
            featureRow(icon: "checkmark.circle.fill", title: "Import custom .ttf fonts for text")
            syncFeatureRow
        }
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
            Image(systemName: "star.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.yellow)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text("Sync across iPhone, iPad and Mac")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                Text("Most Popular Reason to Upgrade")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Pricing cards

    private var pricingCards: some View {
        HStack(spacing: 8) {
            ForEach(plans) { option in
                priceCard(option)
            }
        }
    }

    private func priceCard(_ option: PaywallPlan) -> some View {
        let isSelected = selectedPlan == option.plan

        return Button {
            withAnimation(.spring(duration: 0.22)) {
                selectedPlan = option.plan
            }
        } label: {
            VStack(spacing: 8) {
                Text(option.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Text(displayPrice(for: option.plan))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)

                Text(option.badge ?? " ")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(option.badge == nil ? .clear : Color.accentColor)
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
                    let success = await pro.purchase(selectedPlan)
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
                        Text("Get Canvio Pro — \(displayPrice(for: selectedPlan))")
                            .font(.headline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(pro.isLoading)

            Button {
                Task {
                    await pro.restorePurchases()
                    if pro.isPro {
                        dismiss()
                        onPurchaseCompleted?()
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
                Text("Cancel anytime · Billed by Apple ·")
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

    private func displayPrice(for plan: ProManager.Plan) -> String {
        guard let product = product(for: plan) else {
            return fallbackPrice(for: plan)
        }

        switch plan {
        case .monthly:
            return "\(product.displayPrice)/month"
        case .yearly:
            return "\(product.displayPrice)/year"
        case .lifetime:
            return "\(product.displayPrice) once"
        }
    }

    private func fallbackPrice(for plan: ProManager.Plan) -> String {
        switch plan {
        case .monthly:
            return "Loading..."
        case .yearly:
            return "Loading..."
        case .lifetime:
            return "Loading..."
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
