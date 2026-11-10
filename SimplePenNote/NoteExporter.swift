import SwiftUI
import PencilKit
import UIKit

enum NoteExportFormat: String, CaseIterable, Identifiable {
    case png, pdf

    var id: String { rawValue }
    var displayName: String { rawValue.uppercased() }
}

enum NoteExportError: LocalizedError {
    case noPages
    case multipleImages
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .noPages:
            return "내보낼 노트를 선택해 주세요."
        case .multipleImages:
            return "PNG는 한 페이지씩 내보낼 수 있습니다. 여러 페이지는 PDF를 선택해 주세요."
        case .renderingFailed:
            return "노트를 파일로 만들지 못했습니다. 다시 시도해 주세요."
        }
    }
}

/// All paper and ink use the canvas coordinate space before being reduced to
/// the export size. In particular, grid spacing must shrink with the drawing.
@MainActor
enum NoteExporter {
    static let canvasSize = NoteCanvas.size
    static let outputSize = CGSize(width: 1500, height: 2500)

    static func export(pages: [NotePage], format: NoteExportFormat,
                       showWatermark: Bool) throws -> URL {
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
                    let rendererFormat = UIGraphicsImageRendererFormat()
                    rendererFormat.scale = 1
                    rendererFormat.opaque = true
                    let renderer = UIGraphicsImageRenderer(size: outputSize, format: rendererFormat)
                    // Render first so failure can propagate out of the drawing closure.
                    let paper = try paperImage(style: pages[0].paperStyle)
                    let ink = drawingImage(for: pages[0])
                    let image = renderer.image { _ in
                        draw(paper: paper, ink: ink, showWatermark: showWatermark)
                    }
                    guard let data = image.pngData() else { throw NoteExportError.renderingFailed }
                    try data.write(to: url, options: .atomic)
                }
            case .pdf:
                let pdfFormat = UIGraphicsPDFRendererFormat()
                pdfFormat.documentInfo = [
                    kCGPDFContextCreator as String: "SimplePenNote",
                    kCGPDFContextTitle as String: pages.count == 1 ? pages[0].title : "나의 노트"
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
                    kCGPDFContextTitle as String: "나의 노트"]
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
        page.drawing.image(from: CGRect(origin: .zero, size: canvasSize),
                           scale: outputSize.width / canvasSize.width)
    }

    private static func draw(paper: UIImage, ink: UIImage, showWatermark: Bool) {
        let bounds = CGRect(origin: .zero, size: outputSize)
        paper.draw(in: bounds)
        ink.draw(in: bounds)
        guard showWatermark else { return }

        let text = NSAttributedString(string: "SimplePenNote", attributes: [
            .font: UIFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: UIColor.darkGray.withAlphaComponent(0.65)
        ])
        let size = text.size()
        text.draw(at: CGPoint(x: outputSize.width - size.width - 20,
                              y: outputSize.height - size.height - 20))
    }
}
