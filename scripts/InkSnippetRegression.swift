import ImageIO
import UniformTypeIdentifiers

@MainActor
enum InkSnippetRegression {
    static func run() throws {
        let converted = InkSelection.canvasRect(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 20, y: 60),
                                                zoom: 0.5, offset: CGPoint(x: 50, y: 30))
        precondition(converted == CGRect(x: 140, y: 180, width: 160, height: 280), "Reverse drags must account for zoom and pan")
        precondition(InkSelection.canvasRect(from: .zero, to: .zero, zoom: 0, offset: .zero).isNull)
        precondition(NoteSelection(rect: .null) == nil && NoteSelection(rect: CGRect(x: 0, y: 0, width: 0, height: 5)) == nil)

        var stroke = makeStroke(y: 100, color: .red)
        // This existing mask represents erased ink. A later selection must intersect it.
        let retained = CGRect(x: 150, y: 50, width: 250, height: 100)
        stroke.mask = NSBezierPath(rect: retained)
        stroke.transform = CGAffineTransform(a: 1.5, b: 0, c: 0, d: 1.5, tx: 300, ty: 600)
        let drawing = PKDrawing(strokes: [stroke, makeStroke(y: 300, color: .blue)])
        let original = drawing.dataRepresentation()
        let selection = NoteSelection(rect: CGRect(x: 400, y: 700, width: 300, height: 100))!
        let fractional = NoteSelection(rect: CGRect(x: 400.4, y: 700.6, width: 299.2, height: 99.3))!
        let exact = NoteImageLayout(drawingBounds: drawing.bounds,
                                    options: NoteImageExportOptions(selection: fractional), showWatermark: false)
        precondition(exact.sourceRect == fractional.rect, "Fractional selection bounds must not expand to neighboring ink")
        let options = NoteImageExportOptions(background: .transparent, selection: selection)
        let selected = try NotePNGRenderer.render(page: NotePage(drawing: drawing), options: options, showWatermark: false)
        precondition(selected.width == 600 && selected.height == 200, "Manual export must use the chosen rectangle without auto padding")
        precondition(pixel(selected, x: 100, y: 100).a == 0, "Existing erased ink must remain absent")
        precondition(pixel(selected, x: 400, y: 100).r > 200, "Selected ink must remain red")
        var paperOptions = options
        paperOptions.background = .paper
        let marked = try NotePNGRenderer.render(page: NotePage(drawing: drawing), options: paperOptions, showWatermark: true)
        precondition(pixel(marked, x: 0, y: 0).a == 255, "Free partial exports must keep an opaque paper background")
        precondition(marked.height == selected.height + 40, "Free partial exports need a separate watermark footer")
        precondition(!InkSelection.hasInk(drawing, in: CGRect(x: 405, y: 710, width: 20, height: 20)), "An erased selection must be empty")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SimplePenNote-SnippetRegression-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InkSnippetStore(directory: root)
        let item = try store.add(drawing: drawing, selection: selection, title: "../../arrows/../red.png")
        precondition(store.items.count == 1 && item.drawing.strokes.count == 1, "Do not store unrelated strokes")
        precondition(drawing.dataRepresentation() == original, "Saving must not modify the original note")
        let normalized = try NotePNGRenderer.render(page: item.page, options: item.imageOptions, showWatermark: false)
        precondition(pixel(normalized, x: 100, y: 100).a == 0 && pixel(normalized, x: 400, y: 100).r > 200)

        let placed = item.drawing(centeredAt: CGPoint(x: 1000, y: 1000), scale: 0.5)
        let twice = drawing.appending(placed).appending(item.drawing(centeredAt: CGPoint(x: 1500, y: 1500), scale: 1))
        precondition(twice.strokes.count == 4, "Repeated insertions must append independent copies")
        let targetRegion = NoteSelection(rect: CGRect(x: 850, y: 900, width: 300, height: 200))!
        let placedImage = try NotePNGRenderer.render(page: NotePage(drawing: placed),
                                                    options: NoteImageExportOptions(background: .transparent, selection: targetRegion), showWatermark: false)
        precondition(pixel(placedImage, x: 100, y: 200).a == 0, "Masked paths must not bleed outside their stored rectangle after insertion")
        precondition(pixel(placedImage, x: 350, y: 200).r > 200, "Insertion must retain masked ink at the requested size and center")
        precondition(pixel(placedImage, x: 500, y: 200).a == 0, "Outside original path must stay hidden after insertion")

        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        precondition(files.count == 1 && files[0].lastPathComponent == "\(item.id.uuidString).inksnippet", "User titles must not form file paths")
        let relaunched = InkSnippetStore(directory: root)
        precondition(relaunched.items.count == 1 && relaunched.items[0].id == item.id)
        try relaunched.rename(relaunched.items[0], title: "  내 화살표  ")
        precondition(InkSnippetStore(directory: root).items[0].title == "내 화살표", "Unicode names and renames must survive relaunch")
        let corrupted = root.appendingPathComponent("\(UUID().uuidString).inksnippet")
        try Data("broken JSON".utf8).write(to: corrupted)
        let recovered = InkSnippetStore(directory: root)
        precondition(recovered.items.count == 1 && recovered.loadWarning != nil)
        precondition(FileManager.default.fileExists(atPath: corrupted.path), "Never remove unreadable saved data")
        let demo = InkSnippetStore(directory: root, persistChanges: false)
        precondition(demo.items.isEmpty)
        _ = try demo.add(drawing: drawing, selection: selection, title: "Demo")
        let filesAfterDemo = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        precondition(filesAfterDemo.count == 2, "Demo must never write real files")
        do {
            _ = try store.add(drawing: drawing, selection: NoteSelection(rect: CGRect(x: 405, y: 710, width: 20, height: 20))!, title: "Empty")
            preconditionFailure("Empty selections must not be saved")
        } catch InkSnippetError.emptySelection {}
        let blocked = root.appendingPathComponent("not-a-directory")
        try Data("preserve".utf8).write(to: blocked)
        let failing = InkSnippetStore(directory: blocked)
        do {
            _ = try failing.add(drawing: drawing, selection: selection, title: "Failure")
            preconditionFailure("A failed write must not be reported as saved")
        } catch { precondition(failing.items.isEmpty) }
        let preserved = try Data(contentsOf: blocked)
        precondition(preserved == Data("preserve".utf8))

        // Clipped masks must survive the existing note cache, not just the library.
        let suite = "SimplePenNote.SnippetNote.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let notes = NoteStore(defaults: defaults, syncWithCloud: false)
        notes.currentPage.drawing = placed
        notes.savePages()
        let restoredDrawing = NoteStore(defaults: defaults, syncWithCloud: false).currentPage.drawing
        let restoredImage = try NotePNGRenderer.render(page: NotePage(drawing: restoredDrawing),
                                                      options: NoteImageExportOptions(background: .transparent, selection: targetRegion), showWatermark: false)
        precondition(pixel(restoredImage, x: 500, y: 200).a == 0 && pixel(restoredImage, x: 350, y: 200).r > 200)
        try store.delete(item)
        precondition(InkSnippetStore(directory: root).items.isEmpty, "Deletion must survive relaunch")
        precondition(InkSelection.hasInk(placed, in: targetRegion.rect), "Deleting a library item must not change an already inserted copy")

        let output = URL(fileURLWithPath: "/tmp/SimplePenNote-Snippets-QA", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, image) in [("selected", selected), ("free-selected", marked), ("saved", normalized), ("inserted", placedImage)] {
            let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent("\(name).png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, image, nil)
            precondition(CGImageDestinationFinalize(destination))
        }
        print("PASS: selection zoom/pan, exact crop, transformed eraser masks, no outside ink, immutable originals, vector placement, note cache, snippet relaunch/rename/delete, corrupt-file recovery, failed-write safety, demo isolation")
    }

    private static func makeStroke(y: CGFloat, color: NSColor) -> PKStroke {
        let points = (0...20).map { index in
            PKStrokePoint(location: CGPoint(x: CGFloat(index) * 20, y: y), timeOffset: Double(index) * 0.01,
                          size: CGSize(width: 12, height: 12), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    private static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, a: Int) {
        let sample = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))!
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return (Int(bytes[0]), Int(bytes[3]))
    }
}
