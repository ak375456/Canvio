import Foundation

/// Manually managed sale. There is no automatic start or expiration date.
/// Checkout pricing remains controlled by App Store Connect.
struct LocalProSaleCampaign {
    static let isEnabled = true
    static let regularUSDPrice = Decimal(string: "29.99")!
    static let saleUSDPrice = Decimal(string: "14.99")!

    static func shouldPromote(isPro: Bool, price: Decimal, currencyCode: String) -> Bool {
        guard isEnabled, !isPro, price > 0 else { return false }
        // Stop advertising the USD discount if Apple is still returning the
        // regular price, or the price has already been changed back manually.
        return currencyCode != "USD" || price == saleUSDPrice
    }
}

struct LocalProSaleOffer {
    let price: String
    let originalPrice: String?
    let badge: String
}
