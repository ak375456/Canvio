//
//  CanvasGridView.swift
//  Ponder
//

import SwiftUI

struct CanvasGridView: View {
    let offset: CGSize
    let scale: CGFloat
    let style: GridStyle

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                drawGrid(in: context, size: size)
            }
            .background(canvasBackground)
        }
    }

    private var canvasBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemBackground)
        #else
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }

    private func drawGrid(in context: GraphicsContext, size: CGSize) {
        guard style != .none else { return }

        let spacing: CGFloat = 30
        let stepX = spacing * scale
        let stepY = spacing * scale

        let offsetX = offset.width.truncatingRemainder(dividingBy: stepX)
        let offsetY = offset.height.truncatingRemainder(dividingBy: stepY)

        let lineColor = Color.gray.opacity(0.25)
        let dotColor = Color.gray.opacity(0.4)

        switch style {
        case .dotted:
            drawDots(context: context, size: size,
                     stepX: stepX, stepY: stepY,
                     offsetX: offsetX, offsetY: offsetY,
                     color: dotColor)
        case .squares:
            drawLines(context: context, size: size,
                      stepX: stepX, stepY: stepY,
                      offsetX: offsetX, offsetY: offsetY,
                      color: lineColor,
                      horizontal: true, vertical: true)
        case .horizontal:
            drawLines(context: context, size: size,
                      stepX: stepX, stepY: stepY,
                      offsetX: offsetX, offsetY: offsetY,
                      color: lineColor,
                      horizontal: true, vertical: false)
        case .vertical:
            drawLines(context: context, size: size,
                      stepX: stepX, stepY: stepY,
                      offsetX: offsetX, offsetY: offsetY,
                      color: lineColor,
                      horizontal: false, vertical: true)
        case .none:
            break
        }
    }

    private func drawDots(context: GraphicsContext, size: CGSize,
                          stepX: CGFloat, stepY: CGFloat,
                          offsetX: CGFloat, offsetY: CGFloat,
                          color: Color) {
        let dotSize: CGFloat = 1.5
        var x = offsetX
        while x < size.width {
            var y = offsetY
            while y < size.height {
                let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2,
                                  width: dotSize, height: dotSize)
                context.fill(Path(ellipseIn: rect), with: .color(color))
                y += stepY
            }
            x += stepX
        }
    }

    private func drawLines(context: GraphicsContext, size: CGSize,
                           stepX: CGFloat, stepY: CGFloat,
                           offsetX: CGFloat, offsetY: CGFloat,
                           color: Color,
                           horizontal: Bool, vertical: Bool) {
        if vertical {
            var x = offsetX
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(color), lineWidth: 0.5)
                x += stepX
            }
        }
        if horizontal {
            var y = offsetY
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(color), lineWidth: 0.5)
                y += stepY
            }
        }
    }
}
