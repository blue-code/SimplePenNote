import XCTest
import PencilKit
import UIKit
@testable import SimplePenNote

@MainActor
final class NoteExporterTests: XCTestCase {
    func testPNGHasBoundedDimensionsAndPreservesInkCoordinates() throws {
        let page = NotePage(drawing: horizontalStroke(color: .red, y: 1000), paperStyle: .blank)
        let image = try exportImage(page: page)
        XCTAssertEqual(image.width, 1500)
        XCTAssertEqual(image.height, 2500)

        // Canvas (1000, 1000) must become export (500, 500).
        let ink = try pixel(image, x: 500, y: 500)
        XCTAssertGreaterThan(ink.red, ink.green + 100)
        let paper = try pixel(image, x: 500, y: 550)
        XCTAssertGreaterThan(paper.green, 200)
    }

    func testPaperSpacingScalesInTheSameCoordinateSpaceAsInk() throws {
        let lined = try exportImage(page: NotePage(paperStyle: .lines))
        let blank = try exportImage(page: NotePage(paperStyle: .blank))

        // First rule is at canvas y=100, hence export y=50. Rendering the
        // template directly at output size would incorrectly put it at y=100.
        let lineDifferences = try (48...51).map { y in
            abs(try pixel(lined, x: 50, y: y).red - pixel(blank, x: 50, y: y).red)
        }
        XCTAssertGreaterThan(lineDifferences.max() ?? 0, 0)
        XCTAssertEqual(try pixel(lined, x: 50, y: 20), try pixel(blank, x: 50, y: 20))
    }

    func testPDFIncludesEveryPageInSelectedOrder() throws {
        let pages = [
            NotePage(drawing: horizontalStroke(color: .red, y: 1000), paperStyle: .blank),
            NotePage(drawing: horizontalStroke(color: .blue, y: 1000), paperStyle: .blank)
        ]
        let url = try export(pages: pages, format: .pdf, watermark: false)
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(document.numberOfPages, 2)

        let first = try rasterize(XCTUnwrap(document.page(at: 1)))
        let second = try rasterize(XCTUnwrap(document.page(at: 2)))
        let firstInk = try pixel(first, x: 500, y: 500)
        let secondInk = try pixel(second, x: 500, y: 500)
        XCTAssertGreaterThan(firstInk.red, firstInk.blue + 100)
        XCTAssertGreaterThan(secondInk.blue, secondInk.red + 100)
    }

    func testAsyncPDFPreservesPageOrderAndReportsProgress() async throws {
        let pages = [
            NotePage(drawing: horizontalStroke(color: .red, y: 1000), paperStyle: .blank),
            NotePage(drawing: horizontalStroke(color: .blue, y: 1000), paperStyle: .blank)
        ]
        var progress: [Int] = []
        let url = try await NoteExporter.exportPDF(pages: pages, showWatermark: false) { progress.append($0) }
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(document.numberOfPages, 2)
        XCTAssertEqual(progress, [1, 2])
        let first = try pixel(rasterize(XCTUnwrap(document.page(at: 1))), x: 500, y: 500)
        let second = try pixel(rasterize(XCTUnwrap(document.page(at: 2))), x: 500, y: 500)
        XCTAssertGreaterThan(first.red, first.blue + 100)
        XCTAssertGreaterThan(second.blue, second.red + 100)
    }

    func testCancellingBatchExportRemovesUnfinishedFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SimplePenNoteExports")
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        let task = Task { @MainActor in
            try await NoteExporter.exportPDF(pages: [NotePage(), NotePage()], showWatermark: false) { count in
                if count == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled export must not produce a shareable PDF")
        } catch is CancellationError {
            // Expected after the first rendered page, before a complete PDF exists.
        }
        let after = Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        XCTAssertEqual(after, before)
    }

    func testUserTitleCannotEscapeExportDirectoryAndExportsDoNotOverwrite() throws {
        let page = NotePage(title: "../../outside/노트.pdf", paperStyle: .blank)
        let first = try export(pages: [page], format: .pdf, watermark: false)
        let second = try export(pages: [page], format: .pdf, watermark: false)
        XCTAssertEqual(first.lastPathComponent, "SimplePenNote.pdf")
        XCTAssertEqual(first.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent,
                       "SimplePenNoteExports")
        XCTAssertNotNil(UUID(uuidString: first.deletingLastPathComponent().lastPathComponent))
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testRejectsEmptyExportsAndMultiplePNGPages() {
        XCTAssertThrowsError(try NoteExporter.export(pages: [], format: .pdf, showWatermark: false)) { error in
            guard case NoteExportError.noPages = error else {
                return XCTFail("Expected noPages, received \(error)")
            }
        }
        XCTAssertThrowsError(try NoteExporter.export(pages: [NotePage(), NotePage()],
                                                     format: .png, showWatermark: false)) { error in
            guard case NoteExportError.multipleImages = error else {
                return XCTFail("Expected multipleImages, received \(error)")
            }
        }
    }

    func testWatermarkChangesFooterWithoutChangingPageContent() throws {
        let page = NotePage(paperStyle: .blank)
        let clean = try exportImage(page: page)
        let marked = try exportImage(page: page, watermark: true)
        XCTAssertEqual(try pixel(clean, x: 500, y: 500), try pixel(marked, x: 500, y: 500))

        // Sample the full text region: glyph position and font rasterization
        // may vary slightly across supported OS versions.
        var changedPixels = 0
        for y in stride(from: 2450, to: 2490, by: 2) {
            for x in stride(from: 1300, to: 1490, by: 2) {
                if try pixel(clean, x: x, y: y) != pixel(marked, x: x, y: y) {
                    changedPixels += 1
                }
            }
        }
        XCTAssertGreaterThan(changedPixels, 20)
    }

    private func export(pages: [NotePage], format: NoteExportFormat, watermark: Bool) throws -> URL {
        let url = try NoteExporter.export(pages: pages, format: format, showWatermark: watermark)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        return url
    }

    private func exportImage(page: NotePage, watermark: Bool = false) throws -> CGImage {
        let url = try export(pages: [page], format: .png, watermark: watermark)
        return try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
    }

    private func horizontalStroke(color: UIColor, y: CGFloat) -> PKDrawing {
        let points = (0...12).map { index in
            PKStrokePoint(location: CGPoint(x: 700 + CGFloat(index) * 50, y: y),
                          timeOffset: Double(index) * 0.01,
                          size: CGSize(width: 70, height: 70), opacity: 1,
                          force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: color), path: path)])
    }

    private func rasterize(_ page: CGPDFPage) throws -> CGImage {
        let bounds = page.getBoxRect(.mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { renderer in
            renderer.cgContext.translateBy(x: 0, y: bounds.height)
            renderer.cgContext.scaleBy(x: 1, y: -1)
            renderer.cgContext.drawPDFPage(page)
        }
        return try XCTUnwrap(image.cgImage)
    }

    private struct Pixel: Equatable {
        let red: Int
        let green: Int
        let blue: Int
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> Pixel {
        let cropped = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1,
                                                bitsPerComponent: 8, bytesPerRow: 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                                    | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Pixel(red: Int(bytes[0]), green: Int(bytes[1]), blue: Int(bytes[2]))
    }
}
