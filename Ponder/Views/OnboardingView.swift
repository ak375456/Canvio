//
//  OnboardingView.swift
//  Ponder
//

import SwiftUI

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var selection = 0

    private let slides: [OnboardingSlide] = [
        .init(
            badge: nil,
            title: "Your ideas have no limits",
            subtitle: "An infinite canvas that grows with your thinking. Add text, shapes, images, symbols and more.",
            colors: [
                Color(red: 0.03, green: 0.04, blue: 0.10),
                Color(red: 0.06, green: 0.10, blue: 0.20),
                Color(red: 0.10, green: 0.06, blue: 0.18)
            ],
            illustration: .canvas
        ),
        .init(
            badge: nil,
            title: "Connect and visualize anything",
            subtitle: "Draw connections between ideas, build mind maps and organize your thoughts visually.",
            colors: [
                Color(red: 0.03, green: 0.05, blue: 0.11),
                Color(red: 0.04, green: 0.14, blue: 0.15),
                Color(red: 0.13, green: 0.08, blue: 0.18)
            ],
            illustration: .connections
        ),
        .init(
            badge: "Pro Feature",
            title: "Always with you, on every device",
            subtitle: "With Canvio Pro your canvases sync instantly across iPhone, iPad and Mac.",
            colors: [
                Color.accentColor.opacity(0.95),
                Color(red: 0.08, green: 0.12, blue: 0.30),
                Color(red: 0.03, green: 0.04, blue: 0.10)
            ],
            illustration: .sync
        )
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: slides[selection].colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(slides.indices, id: \.self) { index in
                    OnboardingSlideView(slide: slides[index])
                        .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif

            if selection < slides.count - 1 {
                Button("Skip") { onComplete() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .padding(.top, 18)
                    .padding(.trailing, 18)
            }

            VStack {
                Spacer()
                HStack(spacing: 8) {
                    ForEach(slides.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == selection ? Color.white : Color.white.opacity(0.28))
                            .frame(width: index == selection ? 26 : 8, height: 8)
                            .animation(.spring(duration: 0.25), value: selection)
                    }
                }
                .padding(.bottom, 22)

                Button {
                    if selection == slides.count - 1 {
                        onComplete()
                    } else {
                        withAnimation(.spring(duration: 0.35)) {
                            selection += 1
                        }
                    }
                } label: {
                    Text(selection == slides.count - 1 ? "Get Started" : "Next")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .foregroundStyle(Color(red: 0.05, green: 0.06, blue: 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct OnboardingSlide {
    enum Illustration {
        case canvas
        case connections
        case sync
    }

    let badge: String?
    let title: String
    let subtitle: String
    let colors: [Color]
    let illustration: Illustration
}

private struct OnboardingSlideView: View {
    let slide: OnboardingSlide

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)

            illustration
                .frame(maxWidth: 520)
                .frame(height: 330)
                .padding(.horizontal, 24)

            VStack(spacing: 14) {
                if let badge = slide.badge {
                    Text(badge)
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.16), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                }

                Text(slide.title)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)

                Text(slide.subtitle)
                    .font(.body)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.74))
                    .padding(.horizontal, 34)
                    .frame(maxWidth: 560)
            }

            Spacer(minLength: 132)
        }
    }

    @ViewBuilder
    private var illustration: some View {
        switch slide.illustration {
        case .canvas:
            CanvasIllustration()
        case .connections:
            ConnectionIllustration()
        case .sync:
            SyncIllustration()
        }
    }
}

private struct CanvasIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(Color.white.opacity(0.08))
                .overlay(CanvasDots().opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 30, y: 18)

            RoundedRectangle(cornerRadius: 12)
                .fill(Color.yellow)
                .frame(width: 120, height: 92)
                .rotationEffect(.degrees(-7))
                .offset(x: -82, y: -54)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule().fill(Color.black.opacity(0.25)).frame(width: 66, height: 7)
                        Capsule().fill(Color.black.opacity(0.18)).frame(width: 44, height: 7)
                    }
                    .padding(18)
                    .offset(x: -82, y: -54)
                    .rotationEffect(.degrees(-7))
                }

            RoundedRectangle(cornerRadius: 18)
                .fill(Color.blue.opacity(0.9))
                .frame(width: 122, height: 74)
                .offset(x: 80, y: -44)
                .overlay {
                    Text("Idea")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .offset(x: 80, y: -44)
                }

            Circle()
                .fill(Color.pink)
                .frame(width: 74, height: 74)
                .offset(x: -36, y: 66)

            Image(systemName: "sparkles")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(Color.mint)
                .offset(x: 92, y: 68)
        }
    }
}

private struct ConnectionIllustration: View {
    private let nodes: [(CGPoint, Color, String)] = [
        (CGPoint(x: 0.5, y: 0.28), .blue, "Plan"),
        (CGPoint(x: 0.25, y: 0.56), .orange, "Notes"),
        (CGPoint(x: 0.72, y: 0.58), .mint, "Map"),
        (CGPoint(x: 0.48, y: 0.78), .pink, "Next")
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Canvas { context, size in
                    let points = nodes.map { CGPoint(x: $0.0.x * size.width, y: $0.0.y * size.height) }
                    let pairs = [(0, 1), (0, 2), (1, 3), (2, 3)]
                    for pair in pairs {
                        var path = Path()
                        path.move(to: points[pair.0])
                        path.addLine(to: points[pair.1])
                        context.stroke(path, with: .color(.white.opacity(0.55)), lineWidth: 4)
                    }
                }

                ForEach(nodes.indices, id: \.self) { index in
                    let node = nodes[index]
                    VStack(spacing: 8) {
                        Circle()
                            .fill(node.1.gradient)
                            .frame(width: index == 0 ? 96 : 82, height: index == 0 ? 96 : 82)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                            .shadow(color: node.1.opacity(0.35), radius: 18, y: 10)
                        Text(node.2)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .position(x: node.0.x * proxy.size.width, y: node.0.y * proxy.size.height)
                }
            }
        }
    }
}

private struct SyncIllustration: View {
    var body: some View {
        ZStack {
            device(width: 110, height: 210, corner: 26)
                .offset(x: -122, y: 22)
                .scaleEffect(0.82)
            device(width: 178, height: 238, corner: 28)
                .offset(x: 0, y: -4)
            device(width: 230, height: 154, corner: 22)
                .offset(x: 118, y: 46)
                .scaleEffect(0.82)

            Image(systemName: "icloud.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.25), radius: 18)
                .offset(y: -114)
        }
    }

    private func device(width: CGFloat, height: CGFloat, corner: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(Color.black.opacity(0.46))
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: corner - 6)
                    .strokeBorder(Color.white.opacity(0.24), lineWidth: 2)
            )
            .overlay {
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 8).fill(Color.yellow).frame(width: width * 0.42, height: 34)
                    RoundedRectangle(cornerRadius: 8).fill(Color.blue).frame(width: width * 0.52, height: 28)
                    HStack(spacing: 8) {
                        Circle().fill(Color.pink).frame(width: 28, height: 28)
                        Capsule().fill(Color.white.opacity(0.22)).frame(width: width * 0.36, height: 8)
                    }
                }
                .padding(18)
            }
    }
}

private struct CanvasDots: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 22
            for x in stride(from: CGFloat(0), through: size.width, by: spacing) {
                for y in stride(from: CGFloat(0), through: size.height, by: spacing) {
                    let rect = CGRect(x: x, y: y, width: 2.5, height: 2.5)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.35)))
                }
            }
        }
    }
}
