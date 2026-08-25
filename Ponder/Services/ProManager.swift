//
//  ProManager.swift
//  Ponder
//

import Foundation
import Combine
import StoreKit
import SwiftUI

@MainActor
final class ProManager: ObservableObject {
    static let shared = ProManager()
    enum Plan: String, CaseIterable, Identifiable {
        case monthly = "com.lexur.canvio.pro.monthlyy"
        case yearly = "com.lexur.canvio.pro.yearly"
        case local = "com.lexur.canvio.pro.local"
        case lifetime = "com.lexur.canvio.pro.lifetime"
        case lifetimeUpgrade = "com.lexur.canvio.pro.cloud.lifetime.upgrade"

        var id: String { rawValue }

        static let availableForPurchase: [Plan] = [
            .monthly,
            .yearly,
            .local,
            .lifetime,
            .lifetimeUpgrade
        ]

        var includesCloudSync: Bool {
            switch self {
            case .monthly, .yearly, .lifetime:
                return true
            case .local, .lifetimeUpgrade:
                return false
            }
        }
    }

    @AppStorage("isPro") private var storedIsPro = false
    @AppStorage("hasLifetimePro") private var hasLifetimePro = false
    @AppStorage("canUseCloudSync") private var storedCanUseCloudSync = false

    @Published private(set) var isPro: Bool
    @Published private(set) var canUseCloudSync: Bool
    @Published private(set) var ownsLocalPro: Bool
    @Published private(set) var ownsLifetimePro: Bool
    @Published private(set) var ownsLifetimeUpgrade: Bool
    @Published private(set) var products: [Product] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    var isEligibleForLifetimeUpgrade: Bool {
        ownsLocalPro && !ownsLifetimePro && !ownsLifetimeUpgrade
    }

    var hasLifetimeAccess: Bool {
        ownsLifetimePro || (ownsLocalPro && ownsLifetimeUpgrade)
    }

    private init() {
        isPro = UserDefaults.standard.bool(forKey: "isPro")
        canUseCloudSync = UserDefaults.standard.bool(forKey: "canUseCloudSync")
            || UserDefaults.standard.bool(forKey: "hasLifetimePro")
        ownsLocalPro = false
        ownsLifetimePro = UserDefaults.standard.bool(forKey: "hasLifetimePro")
        ownsLifetimeUpgrade = false
        updatesTask = listenForTransactionUpdates()
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            products = try await Product.products(for: Plan.availableForPurchase.map(\.rawValue))
                .sorted { lhs, rhs in
                    order(for: lhs.id) < order(for: rhs.id)
                }
        } catch {
            errorMessage = "Unable to load purchases: \(error.localizedDescription)"
        }
    }

    func refreshStatus() async {
        // Preserve the entitlement promised to purchasers of the retired
        // all-inclusive lifetime product, including while they are offline.
        var ownsLocal = false
        var ownsLifetime = hasLifetimePro
        var ownsUpgrade = false
        var hasActiveCloudSubscription = false

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result),
                  Plan(rawValue: transaction.productID) != nil,
                  transaction.revocationDate == nil
            else { continue }

            let plan = Plan(rawValue: transaction.productID)!
            switch plan {
            case .monthly, .yearly:
                hasActiveCloudSubscription = true
            case .local:
                ownsLocal = true
            case .lifetime:
                ownsLifetime = true
                hasLifetimePro = true
            case .lifetimeUpgrade:
                ownsUpgrade = true
            }
        }

        ownsLocalPro = ownsLocal
        ownsLifetimePro = ownsLifetime
        ownsLifetimeUpgrade = ownsUpgrade

        let hasLifetimeAccess = ownsLifetime || (ownsLocal && ownsUpgrade)
        let hasProFeatures = ownsLocal || hasActiveCloudSubscription || hasLifetimeAccess
        let hasCloudSync = hasActiveCloudSubscription || hasLifetimeAccess
        setEntitlements(pro: hasProFeatures, cloudSync: hasCloudSync)
    }

    @discardableResult
    func purchase(_ plan: Plan) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if plan == .lifetimeUpgrade {
            await refreshStatus()
            guard ownsLocalPro else {
                errorMessage = "The Lifetime Cloud Upgrade requires Canvio Local Pro."
                return false
            }
        }

        await loadProducts()
        guard let product = products.first(where: { $0.id == plan.rawValue }) else {
            errorMessage = "This purchase is not available right now."
            return false
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                if transaction.productID == Plan.lifetime.rawValue {
                    hasLifetimePro = true
                }
                await transaction.finish()
                await refreshStatus()
                switch plan {
                case .local:
                    return ownsLocalPro
                case .lifetimeUpgrade:
                    return canUseCloudSync && ownsLifetimeUpgrade
                case .monthly, .yearly, .lifetime:
                    return canUseCloudSync
                }
            case .pending:
                errorMessage = "Purchase is pending approval."
                return false
            case .userCancelled:
                return false
            @unknown default:
                errorMessage = "Purchase could not be completed."
                return false
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            return false
        }
    }

    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshStatus()
            if !isPro {
                errorMessage = "No active Canvio purchase was found."
            }
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            for await result in Transaction.updates {
                guard let transaction = try? self.checkVerified(result) else { continue }
                if transaction.productID == Plan.lifetime.rawValue {
                    self.hasLifetimePro = transaction.revocationDate == nil
                }
                await transaction.finish()
                await self.refreshStatus()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let error):
            throw error
        }
    }

    private func setEntitlements(pro: Bool, cloudSync: Bool) {
        storedIsPro = pro
        storedCanUseCloudSync = cloudSync
        isPro = pro
        canUseCloudSync = cloudSync
    }

    private func order(for productID: String) -> Int {
        switch Plan(rawValue: productID) {
        case .monthly: return 0
        case .yearly: return 1
        case .local: return 2
        case .lifetime: return 3
        case .lifetimeUpgrade: return 4
        case .none: return 5
        }
    }
}
