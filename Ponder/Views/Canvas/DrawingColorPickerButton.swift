//
//  DrawingColorPickerButton.swift
//  Canvio
//

import SwiftUI

#if os(iOS)
import UIKit

struct DrawingColorPickerButton: View {
    @Binding var selectedColor: UIColor
    var compact: Bool = false
    var isActive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "eyedropper.halffull")
                    .font(.system(size: 13, weight: .semibold))
                if !compact {
                    Text("Pick")
                        .font(.caption.weight(.semibold))
                }
                Circle()
                    .fill(Color(uiColor: selectedColor))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
            }
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .padding(.horizontal, compact ? 9 : 11)
            .padding(.vertical, 9)
            .background(
                isActive
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(.regularMaterial),
                in: Capsule()
            )
            .shadow(
                color: isActive ? Color.accentColor.opacity(0.35) : .clear,
                radius: 6, x: 0, y: 2
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "Cancel color picking" : "Pick drawing color from canvas")
    }
}

struct DrawingColorSamplingOverlay: View {
    var onColorPicked: (UIColor) -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            UIKitDrawingColorSampler(onColorPicked: onColorPicked)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            VStack {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "eyedropper.halffull")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Tap a color")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .allowsHitTesting(false)

                    Spacer(minLength: 8)

                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 36, height: 36)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel color picking")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct UIKitDrawingColorSampler: UIViewRepresentable {
    var onColorPicked: (UIColor) -> Void

    func makeUIView(context: Context) -> ColorSamplingView {
        let view = ColorSamplingView()
        view.onColorPicked = onColorPicked
        return view
    }

    func updateUIView(_ view: ColorSamplingView, context: Context) {
        view.onColorPicked = onColorPicked
    }
}

private final class ColorSamplingView: UIView {
    var onColorPicked: ((UIColor) -> Void)?
    private let previewView = UIView(frame: CGRect(x: 0, y: 0, width: 58, height: 58))
    private let previewColorView = UIView(frame: CGRect(x: 7, y: 7, width: 44, height: 44))
    private var latestColor: UIColor?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false

        previewView.isHidden = true
        previewView.isUserInteractionEnabled = false
        previewView.backgroundColor = .systemBackground
        previewView.layer.cornerRadius = 29
        previewView.layer.borderWidth = 1
        previewView.layer.borderColor = UIColor.separator.cgColor
        previewView.layer.shadowColor = UIColor.black.cgColor
        previewView.layer.shadowOpacity = 0.2
        previewView.layer.shadowRadius = 10
        previewView.layer.shadowOffset = CGSize(width: 0, height: 4)

        previewColorView.layer.cornerRadius = 22
        previewColorView.layer.borderWidth = 1
        previewColorView.layer.borderColor = UIColor.label.withAlphaComponent(0.18).cgColor

        previewView.addSubview(previewColorView)
        addSubview(previewView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        updatePreview(for: touches.first)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        updatePreview(for: touches.first)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        updatePreview(for: touches.first)
        let color = latestColor
        previewView.isHidden = true

        if let color {
            onColorPicked?(color.withAlphaComponent(1))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        previewView.isHidden = true
        latestColor = nil
    }

    private func updatePreview(for touch: UITouch?) {
        guard let touch,
              let window else { return }

        let location = touch.location(in: self)
        let windowPoint = convert(location, to: window)
        previewView.isHidden = true

        guard let color = window.drawingSampledColor(at: windowPoint) else {
            latestColor = nil
            return
        }

        latestColor = color
        previewColorView.backgroundColor = color
        previewView.center = constrainedPreviewCenter(for: location)
        previewView.isHidden = false
    }

    private func constrainedPreviewCenter(for location: CGPoint) -> CGPoint {
        let halfSize = previewView.bounds.width / 2
        let x = min(max(location.x, halfSize + 8), max(halfSize + 8, bounds.width - halfSize - 8))
        let preferredY = location.y - 72
        let fallbackY = location.y + 72
        let y = preferredY >= halfSize + 8
            ? preferredY
            : min(max(fallbackY, halfSize + 8), max(halfSize + 8, bounds.height - halfSize - 8))
        return CGPoint(x: x, y: y)
    }
}

private extension UIView {
    func drawingSampledColor(at point: CGPoint) -> UIColor? {
        guard bounds.contains(point) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 1, height: 1),
            format: format
        ).image { context in
            context.cgContext.translateBy(x: -point.x, y: -point.y)
            if !drawHierarchy(in: bounds, afterScreenUpdates: false) {
                layer.render(in: context.cgContext)
            }
        }

        return image.drawingSinglePixelColor()
    }
}

private extension UIImage {
    func drawingSinglePixelColor() -> UIColor? {
        guard let cgImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue |
            CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let alpha = CGFloat(pixel[3]) / 255
        guard alpha > 0.01 else { return nil }

        return UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: alpha
        )
    }
}
#endif
