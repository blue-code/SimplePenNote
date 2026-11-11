import SwiftUI
import PencilKit

struct InkPlacementOverlay: View {
    let item: InkSnippet
    let preview: UIImage?
    @Binding var center: CGPoint
    let scale: CGFloat
    @StateObject private var viewport: CanvasSyncObject
    @State private var dragStart: CGPoint?

    init(item: InkSnippet, preview: UIImage?, center: Binding<CGPoint>, scale: CGFloat, canvasView: PKCanvasView) {
        self.item = item; self.preview = preview; _center = center; self.scale = scale
        _viewport = StateObject(wrappedValue: CanvasSyncObject(canvasView: canvasView))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.001).contentShape(Rectangle())
            Group {
                if let preview { Image(uiImage: preview).resizable().scaledToFit() }
                else { Rectangle().fill(.indigo.opacity(0.1)) }
            }
            .frame(width: item.size.width * scale * viewport.zoomScale, height: item.size.height * scale * viewport.zoomScale)
            .overlay(Rectangle().stroke(.indigo, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .position(x: center.x * viewport.zoomScale - viewport.contentOffset.x,
                      y: center.y * viewport.zoomScale - viewport.contentOffset.y)
        }
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil { dragStart = center }
                guard let start = dragStart else { return }
                center = CGPoint(x: start.x + value.translation.width / viewport.zoomScale,
                                 y: start.y + value.translation.height / viewport.zoomScale)
            }.onEnded { _ in dragStart = nil })
        .clipped()
        .accessibilityLabel("손글씨 배치 미리보기")
        .accessibilityHint("끌어서 위치를 옮기고 아래에서 크기를 조절하세요. 기본 위치는 화면 가운데입니다.")
        .accessibilityIdentifier("canvas.placement")
    }
}
