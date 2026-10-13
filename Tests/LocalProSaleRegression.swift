import Foundation

@main
struct LocalProSaleRegression {
    static func main() {
        expect(LocalProSaleCampaign.isEnabled, "The sale is manually enabled without a date cutoff")

        let salePrice = LocalProSaleCampaign.saleUSDPrice
        let regularPrice = LocalProSaleCampaign.regularUSDPrice
        expect(LocalProSaleCampaign.shouldPromote(isPro: false, price: salePrice, currencyCode: "USD"),
               "Apple's confirmed discounted USD price enables the sale")
        expect(!LocalProSaleCampaign.shouldPromote(isPro: false, price: regularPrice, currencyCode: "USD"),
               "The sale is hidden if Apple returns the original USD price")
        expect(!LocalProSaleCampaign.shouldPromote(isPro: true, price: salePrice, currencyCode: "USD"),
               "Existing Pro customers aren't shown an extra Local Pro purchase promotion")
        expect(!LocalProSaleCampaign.shouldPromote(isPro: false, price: 0, currencyCode: "USD"),
               "Invalid prices cannot enable a promotion")
        print("Local Pro sale regressions passed")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message)
    }
}
