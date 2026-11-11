import SwiftUI
import PencilKit
import UIKit

enum NoteExportFormat: String, CaseIterable, Identifiable {
    case png, pdf

    var id: String { rawValue }
    var displayName: String { rawValue.uppercased() }
}

/// All paper and ink use the canvas coordinate space before being reduced to
/// the export size. In particular, grid spacing must shrink with the drawing.
@MainActor
enum NoteExporter {
    static let canvasSize = NoteCanvas.size
    static let outputSize = CGSize(width: 1500, height: 2500)

    static func export(pages: [NotePage], format: NoteExportFormat,
                       showWatermark: Bool, imageOptions: NoteImageExportOptions = .fullPage) throws -> URL {
        guard !pages.isEmpty else { throw NoteExportError.noPages }
        guard format != .png || pages.count == 1 else {
            throw NoteExportError.multipleImages
        }

        // Never use a user-editable title as a filesystem path. Separate jobs
        // also keep an open share sheet's file from being overwritten.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimplePenNoteExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("SimplePenNote.\(format.rawValue)")

        do {
            switch format {
            case .png:
                try autoreleasepool {
                    let image = try pngImage(page: pages[0], options: imageOptions, showWatermark: showWatermark)
                    guard let data = image.pngData() else { throw NoteExportError.renderingFailed }
                    try data.write(to: url, options: .atomic)
                }
            case .pdf:
                let pdfFormat = UIGraphicsPDFRendererFormat()
                pdfFormat.documentInfo = [
                    kCGPDFContextCreator as String: "SimplePenNote",
                    kCGPDFContextTitle as String: pages.count == 1 ? pages[0].title : String(localized: "나의 노트")
                ]
                let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: outputSize),
                                                     format: pdfFormat)
                // PDF pages are written sequentially. Only the current page's
                // two bounded images are retained, even for a large notebook.
                var renderingError: Error?
                try renderer.writePDF(to: url) { context in
                    for page in pages {
                        do {
                            try autoreleasepool {
                                let paper = try paperImage(style: page.paperStyle)
                                let ink = drawingImage(for: page)
                                context.beginPage()
                                draw(paper: paper, ink: ink, showWatermark: showWatermark)
                            }
                        } catch {
                            renderingError = error
                            break
                        }
                    }
                }
                if let renderingError { throw renderingError }
            }
            return url
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func pngImage(page: NotePage, options: NoteImageExportOptions,
                         showWatermark: Bool) throws -> UIImage {
        UIImage(cgImage: try NotePNGRenderer.render(page: page, options: options, showWatermark: showWatermark))
    }

    /// Yield between pages so large Pro exports keep the UI responsive and can be cancelled.
    static func exportPDF(pages: [NotePage], showWatermark: Bool,
                          onProgress: @MainActor (Int) -> Void) async throws -> URL {
        guard !pages.isEmpty else { throw NoteExportError.noPages }
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimplePenNoteExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("SimplePenNote.pdf")
        var bounds = CGRect(origin: .zero, size: outputSize)
        let info = [kCGPDFContextCreator as String: "SimplePenNote",
                    kCGPDFContextTitle as String: String(localized: "나의 노트")]
        guard let pdf = CGContext(url as CFURL, mediaBox: &bounds, info as CFDictionary) else {
            try? FileManager.default.removeItem(at: directory)
            throw NoteExportError.renderingFailed
        }
        do {
            for (index, page) in pages.enumerated() {
                try Task.checkCancellation()
                try autoreleasepool {
                    let paper = try paperImage(style: page.paperStyle)
                    let ink = drawingImage(for: page)
                    pdf.beginPDFPage(nil)
                    pdf.saveGState()
                    // Core Graphics PDFs use a bottom-left origin; UIKit images use top-left.
                    pdf.translateBy(x: 0, y: outputSize.height)
                    pdf.scaleBy(x: 1, y: -1)
                    UIGraphicsPushContext(pdf)
                    draw(paper: paper, ink: ink, showWatermark: showWatermark)
                    UIGraphicsPopContext()
                    pdf.restoreGState()
                    pdf.endPDFPage()
                }
                onProgress(index + 1)
                await Task.yield()
            }
            try Task.checkCancellation()
            pdf.closePDF()
            return url
        } catch {
            pdf.closePDF()
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func paperImage(style: PaperStyle) throws -> UIImage {
        let content = PaperBackgroundView(style: style)
            .frame(width: canvasSize.width, height: canvasSize.height)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = outputSize.width / canvasSize.width
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { throw NoteExportError.renderingFailed }
        return image
    }

    private static func drawingImage(for page: NotePage) -> UIImage {
        page.drawing.lightImage(from: CGRect(origin: .zero, size: canvasSize),
                           scale: outputSize.width / canvasSize.width)
    }

    private static func draw(paper: UIImage, ink: UIImage, showWatermark: Bool) {
        let bounds = CGRect(origin: .zero, size: outputSize)
        paper.draw(in: bounds)
        ink.draw(in: bounds)
        guard showWatermark else { return }

        drawWatermark(in: outputSize, bottomInset: 20)
    }

    private static func drawWatermark(in size: CGSize, bottomInset: CGFloat) {
        let text = NSAttributedString(string: "SimplePenNote", attributes: [
            .font: UIFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: UIColor.darkGray.withAlphaComponent(0.65)
        ])
        let textSize = text.size()
        text.draw(at: CGPoint(x: size.width - textSize.width - 20,
                              y: size.height - textSize.height - bottomInset))
    }
}
