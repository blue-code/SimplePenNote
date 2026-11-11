#if DEBUG
import SwiftUI
import PencilKit

/// Demo data injected when launched with `-DemoMode 1` argument.
/// Used to generate App Store screenshots — never compiled in release builds.
enum DemoData {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-DemoMode")
    }

    static var initialScreen: String? {
        guard let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-OpenScreen"),
              idx + 1 < ProcessInfo.processInfo.arguments.count else { return nil }
        return ProcessInfo.processInfo.arguments[idx + 1]
    }

    /// Build a curated set of demo pages with realistic-looking strokes.
    static func buildPages() -> [NotePage] {
        var pages: [NotePage] = []

        pages.append(NotePage(
            title: "회의록 — 11/15 기획 미팅",
            drawing: cornellNotesDrawing(),
            paperStyle: .cornell,
            createdAt: Date().addingTimeInterval(-86400 * 5)
        ))
        pages.append(NotePage(
            title: "이번주 할 일",
            drawing: weeklyDrawing(),
            paperStyle: .weekly,
            createdAt: Date().addingTimeInterval(-86400 * 3)
        ))
        pages.append(NotePage(
            title: "수능 모의고사 오답노트",
            drawing: studyDrawing(),
            paperStyle: .study,
            createdAt: Date().addingTimeInterval(-86400 * 2)
        ))
        pages.append(NotePage(
            title: "아이디어 스케치",
            drawing: sketchDrawing(),
            paperStyle: .blank,
            createdAt: Date().addingTimeInterval(-86400)
        ))
        pages.append(NotePage(
            title: "오늘의 일기",
            drawing: lineDrawing(),
            paperStyle: .lines,
            createdAt: Date()
        ))

        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-DemoPageCount"),
           index + 1 < ProcessInfo.processInfo.arguments.count,
           let count = Int(ProcessInfo.processInfo.arguments[index + 1]), (1...5).contains(count) {
            return Array(pages.prefix(count))
        }
        return pages
    }

    // MARK: - Stroke builders

    private static func ink(color: UIColor = .black, width: CGFloat = 4) -> PKInk {
        PKInk(.pen, color: color)
    }

    private static func stroke(points: [CGPoint], color: UIColor = .black, width: CGFloat = 4) -> PKStroke {
        let strokePoints = points.enumerated().map { i, pt in
            PKStrokePoint(location: pt,
                          timeOffset: TimeInterval(i) * 0.01,
                          size: CGSize(width: width, height: width),
                          opacity: 1.0,
                          force: 0.7,
                          azimuth: 0,
                          altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: strokePoints, creationDate: Date())
        return PKStroke(ink: ink(color: color, width: width), path: path)
    }

    /// Smooth handwritten-looking line through control points.
    private static func handwriting(at origin: CGPoint, width w: CGFloat, height h: CGFloat,
                                    seed: Double = 0, color: UIColor = .black) -> PKStroke {
        var pts: [CGPoint] = []
        let steps = 60
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let x = origin.x + t * w + sin(t * 8 + seed) * 4
            let y = origin.y + sin(t * 12 + seed * 1.3) * h * 0.4 + cos(t * 6 + seed) * 6
            pts.append(CGPoint(x: x, y: y))
        }
        return stroke(points: pts, color: color)
    }

    private static func cornellNotesDrawing() -> PKDrawing {
        var strokes: [PKStroke] = []
        // Right side: notes
        for i in 0..<8 {
            let y = 220.0 + Double(i) * 70
            strokes.append(handwriting(at: CGPoint(x: 850, y: y), width: 1700, height: 18, seed: Double(i)))
        }
        // Left side: cues (shorter)
        for i in 0..<4 {
            let y = 250.0 + Double(i) * 140
            strokes.append(handwriting(at: CGPoint(x: 80, y: y), width: 600, height: 14, seed: Double(i) + 100))
        }
        // Summary at bottom
        for i in 0..<2 {
            let y = 4400.0 + Double(i) * 60
            strokes.append(handwriting(at: CGPoint(x: 80, y: y), width: 2700, height: 14, seed: Double(i) + 50))
        }
        return PKDrawing(strokes: strokes)
    }

    private static func weeklyDrawing() -> PKDrawing {
        var strokes: [PKStroke] = []
        let cellW = 750.0
        let cellH = 950.0
        for col in 0..<4 {
            for row in 0..<5 {
                let originX = Double(col) * cellW + 40
                let originY = Double(row) * cellH + 40
                let lines = Int.random(in: 1...3)
                for line in 0..<lines {
                    strokes.append(handwriting(
                        at: CGPoint(x: originX, y: originY + Double(line) * 50),
                        width: cellW - 80, height: 12,
                        seed: Double(col * 10 + row * 3 + line),
                        color: line == 0 ? UIColor(red: 0.2, green: 0.4, blue: 1, alpha: 1) : .black))
                }
            }
        }
        return PKDrawing(strokes: strokes)
    }

    private static func studyDrawing() -> PKDrawing {
        var strokes: [PKStroke] = []
        // Left: question
        for i in 0..<6 {
            let y = 200.0 + Double(i) * 80
            strokes.append(handwriting(at: CGPoint(x: 60, y: y), width: 1300, height: 16, seed: Double(i)))
        }
        // Right: answer (red ink)
        for i in 0..<5 {
            let y = 220.0 + Double(i) * 80
            strokes.append(handwriting(at: CGPoint(x: 1560, y: y), width: 1300, height: 16,
                                       seed: Double(i) + 10,
                                       color: UIColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)))
        }
        return PKDrawing(strokes: strokes)
    }

    private static func sketchDrawing() -> PKDrawing {
        var strokes: [PKStroke] = []
        // A loose figure / mind-map sketch
        // Center circle
        let center = CGPoint(x: 1500, y: 800)
        var circle: [CGPoint] = []
        for i in 0...60 {
            let theta = Double(i) / 60.0 * 2 * .pi
            circle.append(CGPoint(x: center.x + cos(theta) * 200, y: center.y + sin(theta) * 200))
        }
        strokes.append(stroke(points: circle, width: 5))

        // Branches
        for i in 0..<5 {
            let theta = Double(i) / 5.0 * 2 * .pi + 0.3
            let endX = center.x + cos(theta) * 700
            let endY = center.y + sin(theta) * 500
            strokes.append(stroke(points: [
                CGPoint(x: center.x + cos(theta) * 210, y: center.y + sin(theta) * 210),
                CGPoint(x: endX, y: endY)
            ], width: 4))
            // Small text-like at branch end
            strokes.append(handwriting(at: CGPoint(x: endX - 100, y: endY),
                                       width: 240, height: 8, seed: Double(i)))
        }
        // Center label-like scribble
        strokes.append(handwriting(at: CGPoint(x: center.x - 150, y: center.y),
                                   width: 300, height: 10, seed: 0))
        return PKDrawing(strokes: strokes)
    }

    private static func lineDrawing() -> PKDrawing {
        var strokes: [PKStroke] = []
        for i in 0..<14 {
            let y = 110.0 + Double(i) * 35
            let stops = i.isMultiple(of: 3) ? 1500.0 : Double.random(in: 1800...2700)
            strokes.append(handwriting(at: CGPoint(x: 80, y: y), width: stops - 80, height: 9, seed: Double(i)))
        }
        return PKDrawing(strokes: strokes)
    }
}
#endif
