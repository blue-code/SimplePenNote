import XCTest
import PencilKit
import UIKit
@testable import SimplePenNote

@MainActor
final class InkSnippetTests: XCTestCase {
    func testSelectionUsesZoomAndScrollInBothDragDirections() throws {
        let rect = InkSelection.canvasRect(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 20, y: 60),
                                           zoom: 0.5, offset: CGPoint(x: 50, y: 30))
        XCTAssertEqual(rect, CGRect(x: 140, y: 180, width: 160, height: 280))
        XCTAssertNil(NoteSelection(rect: .null))
        XCTAssertTrue(InkSelection.canvasRect(from: .zero, to: .zero, zoom: 0, offset: .zero).isNull)
    }

    func testSelectedPNGAndSavedInkRetainEraserMasksAndExcludeOutsideInk() throws {
        let original = drawing()
        let originalData = original.dataRepresentation()
        let selection = region()
        let store = InkSnippetStore(directory: try temporaryDirectory())
        let item = try store.add(drawing: original, selection: selection, title: "My arrow")
        XCTAssertEqual(item.drawing.strokes.count, 1)
        XCTAssertEqual(original.dataRepresentation(), originalData)
        let rendered = try NotePNGRenderer.render(page: item.page, options: item.imageOptions, showWatermark: false)
        XCTAssertEqual(rendered.width, 600)
        XCTAssertEqual(rendered.height, 200)
        XCTAssertEqual(try pixel(rendered, x: 100, y: 100)[3], 0, "An old eraser mask must remain in place")
        XCTAssertGreaterThan(try pixel(rendered, x: 400, y: 100)[0], 200)
        let inserted = item.drawing(centeredAt: CGPoint(x: 1000, y: 1000), scale: 0.5)
        let options = NoteImageExportOptions(background: .transparent,
                                            selection: NoteSelection(rect: CGRect(x: 850, y: 900, width: 300, height: 200)))
        let image = try NoteExporter.pngImage(page: NotePage(drawing: inserted), options: options, showWatermark: false)
        let encoded = try XCTUnwrap(UIImage(data: XCTUnwrap(image.pngData()))?.cgImage)
        XCTAssertEqual(try pixel(encoded, x: 500, y: 200)[3], 0, "Hidden path points must not bleed beyond the stored rectangle")
        XCTAssertGreaterThan(try pixel(encoded, x: 350, y: 200)[0], 200)
    }

    func testLibraryRestoresRenamesAndKeepsUnreadableFilesWithoutLosingOtherItems() throws {
        let root = try temporaryDirectory()
        let store = InkSnippetStore(directory: root)
        let item = try store.add(drawing: drawing(), selection: region(), title: "../../outside.png")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first?.lastPathComponent,
                       "\(item.id.uuidString).inksnippet")
        try store.rename(item, title: "내 화살표")
        let corrupt = root.appendingPathComponent("\(UUID().uuidString).inksnippet")
        try Data("unreadable".utf8).write(to: corrupt)
        let relaunched = InkSnippetStore(directory: root)
        XCTAssertEqual(relaunched.items.first?.title, "내 화살표")
        XCTAssertNotNil(relaunched.loadWarning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: corrupt.path))
        try relaunched.delete(XCTUnwrap(relaunched.items.first))
        XCTAssertTrue(InkSnippetStore(directory: root).items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: corrupt.path))
    }

    func testInsertedVectorInkCanBeUndoneAndRedone() throws {
        let canvas = CanvasWithUndo()
        canvas.testUndoManager.groupsByEvent = false
        let before = drawing()
        canvas.drawing = before
        canvas.testUndoManager.removeAllActions()
        var persisted = before
        let item = try InkSnippetStore(persistChanges: false).add(drawing: before, selection: region(), title: "Arrow")
        let libraryData = item.drawing.dataRepresentation()
        let combined = before.appending(item.drawing(centeredAt: CGPoint(x: 1000, y: 1000), scale: 0.5))
        canvas.testUndoManager.beginUndoGrouping()
        CanvasDrawingEdits.apply(combined, to: canvas) { persisted = $0 }
        canvas.testUndoManager.endUndoGrouping()
        XCTAssertEqual(persisted.strokes.count, 3)
        canvas.testUndoManager.undo()
        XCTAssertEqual(persisted.dataRepresentation(), before.dataRepresentation())
        XCTAssertEqual(canvas.drawing.strokes.count, 2)
        canvas.testUndoManager.redo()
        XCTAssertEqual(canvas.drawing.strokes.count, 3)
        XCTAssertEqual(persisted.strokes.count, 3)
        XCTAssertEqual(item.drawing.dataRepresentation(), libraryData)
    }

    private func region() -> NoteSelection { NoteSelection(rect: CGRect(x: 400, y: 700, width: 300, height: 100))! }

    private func drawing() -> PKDrawing {
        func stroke(y: CGFloat, color: UIColor) -> PKStroke {
            let points = (0...20).map { index in
                PKStrokePoint(location: CGPoint(x: CGFloat(index) * 20, y: y), timeOffset: Double(index) * 0.01,
                              size: CGSize(width: 12, height: 12), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        }
        var red = stroke(y: 100, color: .red)
        red.mask = UIBezierPath(rect: CGRect(x: 150, y: 50, width: 250, height: 100))
        red.transform = CGAffineTransform(a: 1.5, b: 0, c: 0, d: 1.5, tx: 300, ty: 600)
        return PKDrawing(strokes: [red, stroke(y: 300, color: .blue)])
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("InkSnippetTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let sample = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }
}

@MainActor
private final class CanvasWithUndo: PKCanvasView {
    let testUndoManager = UndoManager()
    override var undoManager: UndoManager? { testUndoManager }
}
