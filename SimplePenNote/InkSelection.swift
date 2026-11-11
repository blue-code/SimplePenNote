import Foundation
import PencilKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct NoteSelection: Hashable, Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init?(rect: CGRect) {
        let rect = rect.standardized
        guard !rect.isNull, [rect.minX, rect.minY, rect.width, rect.height].allSatisfy({ $0.isFinite }),
              rect.width >= 1, rect.height >= 1 else { return nil }
        x = rect.minX; y = rect.minY; width = rect.width; height = rect.height
    }

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    var isValid: Bool { [x, y, width, height, x + width, y + height].allSatisfy { $0.isFinite } && width >= 1 && height >= 1 }
}

enum InkSelection {
    static func canvasRect(from start: CGPoint, to end: CGPoint, zoom: CGFloat, offset: CGPoint) -> CGRect {
        guard zoom.isFinite, zoom > 0 else { return .null }
        return CGRect(x: (min(start.x, end.x) + offset.x) / zoom,
                      y: (min(start.y, end.y) + offset.y) / zoom,
                      width: abs(end.x - start.x) / zoom,
                      height: abs(end.y - start.y) / zoom)
    }

    /// Masks use each stroke's pre-transform coordinates. Intersect with existing
    /// eraser masks so clipping can never bring erased ink back into a saved item.
    static func drawing(from drawing: PKDrawing, in selection: NoteSelection) -> PKDrawing {
        guard selection.isValid else { return PKDrawing() }
        let rect = selection.rect
        let strokes = drawing.strokes.compactMap { stroke -> PKStroke? in
            guard stroke.renderBounds.intersects(rect) else { return nil }
            let determinant = stroke.transform.a * stroke.transform.d - stroke.transform.b * stroke.transform.c
            guard determinant.isFinite, abs(determinant) > 0.000001 else { return nil }
            var inverse = stroke.transform.inverted()
            let clip = CGPath(rect: rect, transform: &inverse)
            let mask: CGPath
            if let existing = stroke.mask {
                #if canImport(UIKit)
                let rule: CGPathFillRule = existing.usesEvenOddFillRule ? .evenOdd : .winding
                #else
                let rule: CGPathFillRule = existing.windingRule == .evenOdd ? .evenOdd : .winding
                #endif
                mask = existing.cgPath.intersection(clip, using: rule)
            } else { mask = clip }
            guard !mask.isEmpty else { return nil }
            var copy = stroke
            #if canImport(UIKit)
            copy.mask = UIBezierPath(cgPath: mask)
            #else
            copy.mask = NSBezierPath(cgPath: mask)
            #endif
            return copy
        }
        return PKDrawing(strokes: strokes).transformed(using: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
    }

    static func hasInk(_ drawing: PKDrawing, in rect: CGRect) -> Bool {
        guard !drawing.strokes.isEmpty, let selection = NoteSelection(rect: rect) else { return false }
        let scale = min(1, 128 / max(selection.width, selection.height))
        let rendered = drawing.lightImage(from: rect, scale: scale)
        #if canImport(UIKit)
        let image = rendered.cgImage
        #else
        let image = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
        guard let image else { return false }
        let width = max(1, Int(ceil(rect.width * scale)))
        let height = max(1, Int(ceil(rect.height * scale)))
        let byteCount = width * height * 4
        var bytes = [UInt8](repeating: 0, count: byteCount)
        return bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return stride(from: 3, to: byteCount, by: 4).contains { buffer[$0] > 0 }
        }
    }
}

extension PKDrawing {
    /// Renders ink exactly as written. `image(from:scale:)` follows the current appearance, so in
    /// Dark Mode PencilKit turns dark ink light — exported PNGs and PDFs would lose black writing
    /// on paper. Exports and previews are always on light paper, so render in the light style.
    func lightImage(from rect: CGRect, scale: CGFloat) -> PlatformImage {
        #if canImport(UIKit)
        var image = PlatformImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = self.image(from: rect, scale: scale)
        }
        return image
        #else
        let appearance = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        var image = PlatformImage()
        appearance.performAsCurrentDrawingAppearance { image = self.image(from: rect, scale: scale) }
        return image
        #endif
    }
}

#if canImport(UIKit)
typealias PlatformImage = UIImage
#else
typealias PlatformImage = NSImage
#endif
