import SwiftUI

struct LocalProSaleCard: View {
    let offer: LocalProSaleOffer
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        cardTitle
                        Spacer(minLength: 8)
                        saleBadge
                        selectionIndicator
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            cardTitle
                            Spacer(minLength: 8)
                            selectionIndicator
                        }
                        saleBadge
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        originalPrice
                        salePrice
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        originalPrice
                        salePrice
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Pay once. Keep forever.")
                        .font(.subheadline.weight(.semibold))
                    Text("Unlimited canvases, extended zoom, premium tools and more.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

            }
            .foregroundStyle(.primary)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.orange.opacity(0.16), Color.yellow.opacity(0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.orange.opacity(isSelected ? 0.9 : 0.35), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Selects the one-time Local Pro purchase.")
    }

    @ViewBuilder
    private var originalPrice: some View {
        if let price = offer.originalPrice {
            Text(price)
                .font(.title3.weight(.medium))
                .strikethrough()
                .foregroundStyle(.secondary)
        }
    }

    private var cardTitle: some View {
        Label("Local Pro", systemImage: "sparkles")
            .font(.title3.weight(.bold))
            .fixedSize()
    }

    private var saleBadge: some View {
        Text(offer.badge)
            .font(.caption.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.orange.gradient, in: Capsule())
            .fixedSize()
    }

    private var selectionIndicator: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3.weight(.semibold))
            .foregroundStyle(isSelected ? Color.orange : Color.secondary)
    }

    private var salePrice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(offer.price)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("once")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
