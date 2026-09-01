//
//  CanvasGridView.swift
//  Ponder
//

import SwiftUI

struct CanvasGridView: View {
    let offset: CGSize
    let scale: CGFloat
    let style: GridStyle
    let spacing: CGFloat
    let dotSize: CGFloat
    let showsAlternatingBands: Bool
    let backgroundMode: CanvasBackgroundMode
    let backgroundPalette: CanvasBackgroundPalette
    let customBackgroundColors: CanvasCustomBackgroundColors

    @Environment(\.colorScheme) private var colorScheme

    init(
        offset: CGSize,
        scale: CGFloat,
        style: GridStyle,
        spacing: CGFloat = CGFloat(AppSettings.defaultCanvasPatternSpacing),
        dotSize: CGFloat = CGFloat(AppSettings.defaultCanvasDotSize),
        showsAlternatingBands: Bool = true,
        backgroundMode: CanvasBackgroundMode = .adaptive,
        backgroundPalette: CanvasBackgroundPalette = .neutral,
        customBackgroundColors: CanvasCustomBackgroundColors = .defaults
    ) {
        self.offset = offset
        self.scale = scale
        self.style = style
        self.spacing = spacing
        self.dotSize = dotSize
        self.showsAlternatingBands = showsAlternatingBands
        self.backgroundMode = backgroundMode
        self.backgroundPalette = backgroundPalette
        self.customBackgroundColors = customBackgroundColors
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                drawBackground(in: context, size: size)
            }
        }
    }

    private var appearance: CanvasBackgroundAppearance {
        let resolvedScheme = backgroundMode.resolvedColorScheme(system: colorScheme)
        return backgroundPalette.appearance(
            for: resolvedScheme,
            customColors: customBackgroundColors
        )
    }

    private func drawBackground(in context: GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(appearance.base))

        let resolvedSpacing = max(8, spacing)
        let rawStep = max(0.25, resolvedSpacing * scale)
        // At overview zoom levels, drawing every logical grid point can create tens
        // of thousands of paths per frame. Skip evenly spaced subdivisions while
        // preserving the same canvas origin so panning remains visually stable.
        let subdivisionStride = max(1, ceil(12 / rawStep))
        let stepX = rawStep * subdivisionStride
        let stepY = rawStep * subdivisionStride

        if showsAlternatingBands {
            drawAlternatingBands(context: context, size: size, stepX: stepX, stepY: stepY)
        }
        drawGrid(context: context, size: size, stepX: stepX, stepY: stepY)
    }

    private func drawGrid(context: GraphicsContext, size: CGSize, stepX: CGFloat, stepY: CGFloat) {
        guard style != .none else { return }

        let offsetX = snappedOffset(offset.width, step: stepX)
        let offsetY = snappedOffset(offset.height, step: stepY)

        switch style {
        case .dotted:
            drawDots(context: context, size: size,
                     stepX: stepX, stepY: stepY,
                     offsetX: offsetX, offsetY: offsetY,
                     dotSize: max(0.5, dotSize),
                     color: appearance.dot)
        case .squares:
            drawLines(context: context, size: size,
                      stepX: stepX, stepY: stepY,
                      offsetX: offsetX, offsetY: offsetY,
                      color: appearance.line,
                      horizontal: true, vertical: true)
        case .horizontal:
            drawLines(context: context, size: size,
                      stepX: stepX, stepY: stepY,
                      offsetX: offsetX, offsetY: offsetY,
                      color: appearance.line,
                      horizontal: true, vertical: false)
        case .vertical:
            drawLines(context: context, size: size,
                      stepX: stepX, stepY: stepY,
                      offsetX: offsetX, offsetY: offsetY,
                      color: appearance.line,
                      horizontal: false, vertical: true)
        case .none:
            break
        }
    }

    private func drawAlternatingBands(
        context: GraphicsContext,
        size: CGSize,
        stepX: CGFloat,
        stepY: CGFloat
    ) {
        switch style {
        case .vertical:
            drawColumnBands(context: context, size: size, stepX: stepX)
        case .horizontal:
            drawRowBands(context: context, size: size, stepY: stepY)
        case .squares:
            drawColumnBands(context: context, size: size, stepX: stepX, opacity: 0.55)
        case .dotted, .none:
            break
        }
    }

    private func drawColumnBands(
        context: GraphicsContext,
        size: CGSize,
        stepX: CGFloat,
        opacity: Double = 1
    ) {
        let startIndex = Int(floor((0 - offset.width) / stepX)) - 1
        let endIndex = Int(ceil((size.width - offset.width) / stepX)) + 1

        for index in startIndex...endIndex where index.isMultiple(of: 2) {
            let x = CGFloat(index) * stepX + offset.width
            let rect = CGRect(x: x, y: 0, width: stepX, height: size.height)
            context.fill(Path(rect), with: .color(appearance.alternate.opacity(opacity)))
        }
    }

    private func drawRowBands(
        context: GraphicsContext,
        size: CGSize,
        stepY: CGFloat,
        opacity: Double = 1
    ) {
        let startIndex = Int(floor((0 - offset.height) / stepY)) - 1
        let endIndex = Int(ceil((size.height - offset.height) / stepY)) + 1

        for index in startIndex...endIndex where index.isMultiple(of: 2) {
            let y = CGFloat(index) * stepY + offset.height
            let rect = CGRect(x: 0, y: y, width: size.width, height: stepY)
            context.fill(Path(rect), with: .color(appearance.alternate.opacity(opacity)))
        }
    }

    private func snappedOffset(_ value: CGFloat, step: CGFloat) -> CGFloat {
        let remainder = value.truncatingRemainder(dividingBy: step)
        return remainder >= 0 ? remainder : remainder + step
    }

    private func drawDots(context: GraphicsContext, size: CGSize,
                          stepX: CGFloat, stepY: CGFloat,
                          offsetX: CGFloat, offsetY: CGFloat,
                          dotSize: CGFloat,
                          color: Color) {
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
