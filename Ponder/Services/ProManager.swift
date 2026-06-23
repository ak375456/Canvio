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
        case lifetime = "com.lexur.canvio.pro.lifetime"

        var id: String { rawValue }
    }

    @AppStorage("isPro") private var storedIsPro = false
    @AppStorage("hasLifetimePro") private var hasLifetimePro = true

    @Published private(set) var isPro: Bool
    @Published private(set) var products: [Product] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        isPro = UserDefaults.standard.bool(forKey: "isPro")
        updatesTask = listenForTransactionUpdates()
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            products = try await Product.products(for: Plan.allCases.map(\.rawValue))
                .sorted { lhs, rhs in
                    order(for: lhs.id) < order(for: rhs.id)
                }
        } catch {
            errorMessage = "Unable to load purchases: \(error.localizedDescription)"
        }
    }

    func refreshStatus() async {
        var hasActiveEntitlement = hasLifetimePro

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result),
                  Plan(rawValue: transaction.productID) != nil,
                  transaction.revocationDate == nil
            else { continue }

            if transaction.productID == Plan.lifetime.rawValue {
                hasLifetimePro = true
            }
            hasActiveEntitlement = true
        }

        setPro(hasActiveEntitlement)
    }

    @discardableResult
    func purchase(_ plan: Plan) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

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
                return isPro
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
                errorMessage = "No active Canvio Pro purchase was found."
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
                    self.hasLifetimePro = true
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

    private func setPro(_ value: Bool) {
        storedIsPro = value
        isPro = value
    }

    private func order(for productID: String) -> Int {
        switch Plan(rawValue: productID) {
        case .monthly: return 0
        case .yearly: return 1
        case .lifetime: return 2
        case .none: return 3
        }
    }
}
