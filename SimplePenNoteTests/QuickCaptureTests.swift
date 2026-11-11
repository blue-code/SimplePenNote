import XCTest
import PencilKit
import UIKit
@testable import SimplePenNote

@MainActor
final class QuickCaptureTests: XCTestCase {
    func testPenAndPaperPreferencesSurviveRelaunchWithoutTouchingNotes() {
        let suite = "SimplePenNote.QuickTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([1, 2, 3]), forKey: "SimplePenNote_LocalCache_v2")
        let preferences = QuickNotePreferences(defaults: defaults)
        XCTAssertEqual(preferences.paperStyle, .blank)
        preferences.penColor = .blue
        preferences.penWidth = 8
        preferences.paperStyle = .grid
        let restored = QuickNotePreferences(defaults: defaults)
        XCTAssertEqual(restored.penColor, .blue)
        XCTAssertEqual(restored.penWidth, 8)
        XCTAssertEqual(restored.paperStyle, .grid)
        XCTAssertEqual(defaults.data(forKey: "SimplePenNote_LocalCache_v2"), Data([1, 2, 3]))
    }

    func testCropKeepsOffPaperInkAndLimitsBitmapSize() {
        let bounds = CGRect(x: -100, y: 4900, width: 400, height: 2000)
        let layout = NoteImageLayout(drawingBounds: bounds, options: .init(), showWatermark: true)
        XCTAssertTrue(layout.sourceRect.contains(bounds))
        XCTAssertLessThanOrEqual(layout.outputSize.width, 2500)
        XCTAssertLessThanOrEqual(layout.outputSize.height, 2500)
        XCTAssertEqual(layout.outputSize.height - layout.contentRect.height, 40)
        let empty = NoteImageLayout(drawingBounds: .null, options: .init(), showWatermark: true)
        XCTAssertEqual(empty.outputSize, CGSize(width: 1500, height: 2500))
    }

    func testTransparentPNGPreservesAlphaAndInkThroughEncoding() throws {
        let points = (0...10).map { index in
            PKStrokePoint(location: CGPoint(x: -40 + CGFloat(index) * 30, y: 5100), timeOffset: Double(index) * 0.01,
                          size: CGSize(width: 30, height: 30), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .red), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
        let page = NotePage(drawing: drawing, paperStyle: .grid)
        let dataBefore = drawing.dataRepresentation()
        let options = NoteImageExportOptions(area: .content, background: .transparent)
        let url = try NoteExporter.export(pages: [page], format: .png, showWatermark: false, imageOptions: options)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        XCTAssertEqual(try pixel(image, x: 0, y: 0)[3], 0)
        let center = try pixel(image, x: image.width / 2, y: image.height / 2)
        XCTAssertGreaterThan(center[3], 200)
        XCTAssertGreaterThan(Int(center[0]), Int(center[1]) + 100)
        XCTAssertEqual(page.drawing.dataRepresentation(), dataBefore, "Export must not alter the saved drawing")
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let sample = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }
}
