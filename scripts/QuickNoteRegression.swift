import ImageIO
import UniformTypeIdentifiers

@MainActor
enum QuickNoteRegression {
    static func run() throws {
        let suite = "SimplePenNote.QuickRegression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = QuickNotePreferences(defaults: defaults)
        precondition(preferences.penColor == .ink && preferences.penWidth == 4 && preferences.paperStyle == .blank)
        preferences.penColor = .purple
        preferences.penWidth = 8
        preferences.paperStyle = .lines
        let restored = QuickNotePreferences(defaults: defaults)
        precondition(restored.penColor == .purple && restored.penWidth == 8 && restored.paperStyle == .lines)
        let demo = QuickNotePreferences(defaults: defaults, persistChanges: false)
        demo.penColor = .red
        precondition(QuickNotePreferences(defaults: defaults).penColor == .purple, "Demo must not change saved preferences")
        defaults.set("removed-color", forKey: "QuickNote.penColor")
        defaults.set(-100, forKey: "QuickNote.penWidth")
        precondition(QuickNotePreferences(defaults: defaults).penColor == .ink)
        precondition(QuickNotePreferences(defaults: defaults).penWidth == 4)

        let empty = NoteImageLayout(drawingBounds: .null, options: .init(), showWatermark: true)
        precondition(empty.outputSize == CGSize(width: 1500, height: 2500))
        let outside = CGRect(x: -80, y: 4900, width: 900, height: 500)
        let crop = NoteImageLayout(drawingBounds: outside, options: .init(), showWatermark: false)
        precondition(crop.sourceRect.contains(outside), "Content cropping must retain ink outside the paper")
        precondition(crop.sourceRect.minX == -104 && crop.sourceRect.maxY == 5424)
        let long = NoteImageLayout(drawingBounds: CGRect(x: 0, y: 0, width: 200, height: 100000), options: .init(), showWatermark: true)
        precondition(long.outputSize.width <= 2500 && long.outputSize.height <= 2500)

        let drawing = stroke(from: CGPoint(x: 700, y: 1000), to: CGPoint(x: 1300, y: 1000))
        let page = NotePage(drawing: drawing, paperStyle: .blank)
        let full = try NotePNGRenderer.render(page: page, options: .fullPage, showWatermark: false)
        precondition(full.width == 1500 && full.height == 2500)
        precondition(pixel(full, x: 500, y: 500).r > pixel(full, x: 500, y: 500).g + 100, "PNG ink orientation and position")
        precondition(pixel(full, x: 500, y: 550).g > 200)
        let cropped = try NotePNGRenderer.render(page: page, options: .init(), showWatermark: false)
        precondition(cropped.width * cropped.height < full.width * full.height / 2, "Short notes should export without a full page of whitespace")
        let transparentOptions = NoteImageExportOptions(area: .content, background: .transparent)
        let transparent = try NotePNGRenderer.render(page: page, options: transparentOptions, showWatermark: false)
        precondition(pixel(transparent, x: 0, y: 0).a == 0, "Transparent PNG must retain a zero-alpha border")
        let center = pixel(transparent, x: transparent.width / 2, y: transparent.height / 2)
        precondition(center.a > 200 && center.r > center.g + 100, "Transparent PNG must retain opaque colored ink")
        precondition(pixel(cropped, x: 0, y: 0).a == 255, "Paper exports must be opaque")
        let data = CFDataCreateMutable(nil, 0)!
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, transparent, nil)
        precondition(CGImageDestinationFinalize(destination))
        let decoded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data, nil)!, 0, nil)!
        precondition(pixel(decoded, x: 0, y: 0).a == 0, "Alpha must survive PNG encoding")

        let edgePage = NotePage(drawing: stroke(from: CGPoint(x: -40, y: 5100), to: CGPoint(x: 500, y: 5100)), paperStyle: .grid)
        let edge = try NotePNGRenderer.render(page: edgePage, options: transparentOptions, showWatermark: false)
        precondition(pixel(edge, x: edge.width / 2, y: edge.height / 2).a > 200, "Off-paper ink must remain visible")
        let blankPaper = try NotePNGRenderer.render(page: NotePage(paperStyle: .blank), options: .fullPage, showWatermark: false)
        let linedPaper = try NotePNGRenderer.render(page: NotePage(paperStyle: .lines), options: .fullPage, showWatermark: false)
        let differences = (48...51).map { abs(pixel(blankPaper, x: 50, y: $0).r - pixel(linedPaper, x: 50, y: $0).r) }
        precondition(differences.max()! > 0, "Paper rules must retain their original coordinates")
        let cropLayout = NoteImageLayout(drawingBounds: drawing.bounds, options: .init(), showWatermark: false)
        let linedCrop = try NotePNGRenderer.render(page: NotePage(drawing: drawing, paperStyle: .lines), options: .init(), showWatermark: false)
        let sampleX = Int(10 * cropLayout.scale)
        let ruleY = Int((940 - cropLayout.sourceRect.minY) * cropLayout.scale)
        let cropDifferences = ((ruleY - 2)...(ruleY + 2)).map { abs(pixel(cropped, x: sampleX, y: $0).r - pixel(linedCrop, x: sampleX, y: $0).r) }
        precondition(cropDifferences.max()! > 0, "Cropped paper rules must stay aligned with global ink coordinates")
        let marked = try NotePNGRenderer.render(page: page, options: .init(), showWatermark: true)
        precondition(marked.height == cropped.height + 40, "Free crop watermark must have a separate footer")

        let directory = URL(fileURLWithPath: "/tmp/SimplePenNote-QuickCapture-QA", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, image) in [("full", full), ("cropped", cropped), ("transparent", transparent), ("marked", marked), ("outside", edge)] {
            let url = directory.appendingPathComponent("\(name).png")
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, image, nil)
            precondition(CGImageDestinationFinalize(destination))
        }
        print("PASS: saved pen/paper preferences, invalid defaults, demo isolation, crop bounds, empty fallback, size limits, ink coordinates, alpha round-trip, outside-paper ink, paper alignment, free watermark footer")
        print("PNG samples: \(directory.path)")
    }

    private static func stroke(from start: CGPoint, to end: CGPoint) -> PKDrawing {
        let points = (0...12).map { index in
            PKStrokePoint(location: CGPoint(x: start.x + (end.x - start.x) * CGFloat(index) / 12, y: start.y),
                          timeOffset: Double(index) * 0.01, size: CGSize(width: 70, height: 70),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .red), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
    }

    private static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let sample = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))!
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]), Int(bytes[3]))
    }
}
