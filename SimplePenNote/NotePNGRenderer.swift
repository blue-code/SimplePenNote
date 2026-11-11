import SwiftUI
import PencilKit
import CoreText
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The same bounded bitmap renderer is exercised by iOS and native regression tests.
@MainActor
enum NotePNGRenderer {
    static func render(page: NotePage, options: NoteImageExportOptions,
                       showWatermark: Bool, maximumDimension: CGFloat = 2500) throws -> CGImage {
        let layout = NoteImageLayout(drawingBounds: page.drawing.bounds, options: options, showWatermark: showWatermark,
                                     maximumDimension: maximumDimension)
        let width = Int(layout.outputSize.width)
        let height = Int(layout.outputSize.height)
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NoteExportError.renderingFailed
        }
        let destination = CGRect(x: layout.contentRect.minX,
                                 y: layout.outputSize.height - layout.contentRect.maxY,
                                 width: layout.contentRect.width, height: layout.contentRect.height)
        if options.background == .paper {
            context.setFillColor(CGColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1))
            context.fill(CGRect(origin: .zero, size: layout.outputSize))
            let content = PaperBackgroundView(style: page.paperStyle)
                .frame(width: NoteCanvas.size.width, height: NoteCanvas.size.height)
                .offset(x: -layout.sourceRect.minX, y: -layout.sourceRect.minY)
                .frame(width: layout.sourceRect.width, height: layout.sourceRect.height, alignment: .topLeading)
                .clipped()
                .background(Color(red: 0.98, green: 0.97, blue: 0.95))
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: content)
            renderer.scale = layout.scale
            renderer.isOpaque = true
            guard let paper = renderer.cgImage else { throw NoteExportError.renderingFailed }
            context.draw(paper, in: destination)
        }
        let inkImage = page.drawing.lightImage(from: layout.sourceRect, scale: layout.scale)
        #if canImport(UIKit)
        let ink = inkImage.cgImage
        #else
        let ink = inkImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
        guard let ink else { throw NoteExportError.renderingFailed }
        context.draw(ink, in: destination)
        if showWatermark {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("HelveticaNeue-Medium" as CFString, 16, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.25, alpha: 0.65)
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "SimplePenNote", attributes: attributes))
            let textWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
            context.textPosition = CGPoint(x: layout.outputSize.width - textWidth - 20, y: layout.hasFooter ? 12 : 24)
            CTLineDraw(line, context)
        }
        guard let image = context.makeImage() else { throw NoteExportError.renderingFailed }
        return image
    }
}
