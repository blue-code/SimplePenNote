import SwiftUI
import PencilKit

struct InkSelectionOverlay: View {
    @Binding var selection: NoteSelection?
    @StateObject private var viewport: CanvasSyncObject
    let onFinished: () -> Void

    init(canvasView: PKCanvasView, selection: Binding<NoteSelection?>, onFinished: @escaping () -> Void) {
        _selection = selection
        _viewport = StateObject(wrappedValue: CanvasSyncObject(canvasView: canvasView))
        self.onFinished = onFinished
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001).contentShape(Rectangle())
                if let selection {
                    let rect = selection.rect.applying(CGAffineTransform(a: viewport.zoomScale, b: 0, c: 0, d: viewport.zoomScale,
                                                                         tx: -viewport.contentOffset.x, ty: -viewport.contentOffset.y))
                    Rectangle().fill(.indigo.opacity(0.08))
                        .overlay(Rectangle().stroke(.indigo, style: StrokeStyle(lineWidth: 2, dash: [7, 4])))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in update(value, in: proxy.size) }
                .onEnded { value in update(value, in: proxy.size); onFinished() })
            .clipped()
            .accessibilityElement()
            .accessibilityLabel("부분 선택 영역")
            .accessibilityHint("필요한 부분을 사각형으로 드래그하세요. 아래 전체 필기 선택 버튼도 사용할 수 있습니다.")
            .accessibilityIdentifier("canvas.selection")
        }
    }

    private func update(_ value: DragGesture.Value, in size: CGSize) {
        func clamped(_ point: CGPoint) -> CGPoint {
            CGPoint(x: min(max(0, point.x), size.width), y: min(max(0, point.y), size.height))
        }
        selection = NoteSelection(rect: InkSelection.canvasRect(from: clamped(value.startLocation), to: clamped(value.location),
                                                               zoom: viewport.zoomScale, offset: viewport.contentOffset))
    }
}
