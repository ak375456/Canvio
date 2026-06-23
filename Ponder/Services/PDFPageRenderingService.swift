import Foundation
import PDFKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum PDFPageRenderingService {
    static func render(fileName: String, pageIndex: Int,
                       crop: PDFNormalizedRect = .fullPage,
                       maxPixels: CGFloat = 1600) -> PlatformImage? {
        guard let document = PDFStorageService.loadPDF(fileName: fileName),
              let page = document.page(at: pageIndex) else { return nil }
        let bounds = page.bounds(for: .cropBox)
        let normalized = sanitized(crop)
        let cropRect = CGRect(
            x: bounds.minX + bounds.width * normalized.cgRect.minX,
            y: bounds.minY + bounds.height * normalized.cgRect.minY,
            width: bounds.width * normalized.cgRect.width,
            height: bounds.height * normalized.cgRect.height
        )
        let scale = maxPixels / max(cropRect.width, cropRect.height)
        let size = CGSize(width: max(1, cropRect.width * scale),
                          height: max(1, cropRect.height * scale))

        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let cg = context.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: scale, y: -scale)
            cg.translateBy(x: -cropRect.minX, y: -cropRect.minY)
            page.draw(with: .cropBox, to: cg)
        }
        #else
        guard let cg = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        cg.setFillColor(NSColor.white.cgColor)
        cg.fill(CGRect(origin: .zero, size: size))
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: -cropRect.minX, y: -cropRect.minY)
        page.draw(with: .cropBox, to: cg)
        guard let image = cg.makeImage() else { return nil }
        return NSImage(cgImage: image, size: size)
        #endif
    }

    static func pageAspect(fileName: String, pageIndex: Int,
                           crop: PDFNormalizedRect = .fullPage) -> CGFloat {
        guard let page = PDFStorageService.loadPDF(fileName: fileName)?.page(at: pageIndex) else {
            return 0.75
        }
        let bounds = page.bounds(for: .cropBox)
        return max(0.05, bounds.width * crop.cgRect.width)
            / max(1, bounds.height * crop.cgRect.height)
    }

    private static func sanitized(_ rect: PDFNormalizedRect) -> PDFNormalizedRect {
        let x = min(0.999, max(0, rect.x))
        let y = min(0.999, max(0, rect.y))
        return PDFNormalizedRect(
            x: x,
            y: y,
            width: min(1 - x, max(0.001, rect.width)),
            height: min(1 - y, max(0.001, rect.height))
        )
    }
}
