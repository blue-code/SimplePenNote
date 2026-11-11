import Foundation

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

enum NoteCanvas {
    static let size = CGSize(width: 3000, height: 5000)
}

struct NoteImageExportOptions: Hashable {
    enum Area: String, CaseIterable { case content, page }
    enum Background: String, CaseIterable { case paper, transparent }

    var area: Area = .content
    var background: Background = .paper

    static let fullPage = Self(area: .page, background: .paper)
}

/// Export geometry uses drawing coordinates, including strokes outside the paper.
/// It never mutates, translates or clips the saved drawing.
struct NoteImageLayout {
    let sourceRect: CGRect
    let outputSize: CGSize
    let contentRect: CGRect
    let scale: CGFloat
    let hasFooter: Bool

    init(drawingBounds: CGRect, options: NoteImageExportOptions, showWatermark: Bool) {
        let page = CGRect(origin: .zero, size: NoteCanvas.size)
        let validInk = !drawingBounds.isNull && !drawingBounds.isEmpty &&
            [drawingBounds.minX, drawingBounds.minY, drawingBounds.width, drawingBounds.height].allSatisfy { $0.isFinite }
        let cropped = options.area == .content && validInk
        sourceRect = cropped ? drawingBounds.insetBy(dx: -24, dy: -24).integral : page
        hasFooter = cropped && showWatermark
        let footer: CGFloat = hasFooter ? 40 : 0
        scale = cropped ? min(2, 2500 / sourceRect.width, (2500 - footer) / sourceRect.height) : 0.5
        let size = CGSize(width: ceil(sourceRect.width * scale), height: ceil(sourceRect.height * scale))
        outputSize = CGSize(width: max(hasFooter ? 180 : 1, size.width), height: max(1, size.height + footer))
        contentRect = CGRect(x: (outputSize.width - size.width) / 2, y: 0, width: size.width, height: size.height)
    }
}
