import SwiftUI
import PencilKit

enum NoteCanvas {
    static let size = CGSize(width: 3000, height: 5000)
}

struct PencilKitView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    let paperStyle: PaperStyle
    @Binding var selectedColor: Color
    @Binding var selectedThickness: CGFloat
    @Binding var isEraserMode: Bool
    @Binding var eraserType: PKEraserTool.EraserType
    var onDrawingChange: (PKDrawing) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChange: onDrawingChange)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onDrawingChange: (PKDrawing) -> Void
        private var pendingSave: DispatchWorkItem?

        init(onDrawingChange: @escaping (PKDrawing) -> Void) {
            self.onDrawingChange = onDrawingChange
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // PencilKit emits changes while a stroke is still being drawn. Avoid
            // serializing the entire notebook at the display refresh rate.
            pendingSave?.cancel()
            let work = DispatchWorkItem { [weak self, weak canvasView] in
                guard let canvasView else { return }
                self?.onDrawingChange(canvasView.drawing)
            }
            pendingSave = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            pendingSave?.cancel()
            pendingSave = nil
            onDrawingChange(canvasView.drawing)
        }

        func cancelPendingSave() {
            pendingSave?.cancel()
            pendingSave = nil
        }
    }
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.delegate = context.coordinator
        // 기본 설정
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.overrideUserInterfaceStyle = .light
        
        // 줌 설정: 작은 iPhone에서도 전체 종이를 볼 수 있도록 축소 허용
        canvasView.minimumZoomScale = 0.05
        canvasView.maximumZoomScale = 5.0
        canvasView.bouncesZoom = true
        
        // 넉넉한 작업 공간 (A4 대비 약 10배 넓은 공간)
        canvasView.contentSize = NoteCanvas.size
        
        updateTool()
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.onDrawingChange = onDrawingChange
        updateTool()
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        coordinator.cancelPendingSave()
        uiView.delegate = nil
    }
    
    private func updateTool() {
        if isEraserMode {
            canvasView.tool = PKEraserTool(eraserType)
        } else {
            let tool = PKInkingTool(.pen, color: UIColor(selectedColor), width: selectedThickness)
            canvasView.tool = tool
        }
    }
}

// 줌과 스크롤에 동기화되는 배경 뷰 컨테이너
struct ZoomableCanvasContainer: View {
    @Binding var canvasView: PKCanvasView
    let paperStyle: PaperStyle
    
    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                // 1. 배경 레이어 (캔버스 크기와 동일하게 설정)
                PaperBackgroundView(style: paperStyle)
                    .frame(width: NoteCanvas.size.width, height: NoteCanvas.size.height)
                    // 캔버스의 스크롤/줌 변환을 배경에도 적용
                    .modifier(CanvasSyncModifier(canvasView: canvasView))
            }
        }
    }
}

// 캔버스의 움직임을 배경에 동기화시키는 모디파이어
struct CanvasSyncModifier: ViewModifier {
    @ObservedObject var syncObject: CanvasSyncObject
    
    init(canvasView: PKCanvasView) {
        self.syncObject = CanvasSyncObject(canvasView: canvasView)
    }
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(syncObject.zoomScale, anchor: .topLeading)
            .offset(x: -syncObject.contentOffset.x, y: -syncObject.contentOffset.y)
    }
}

// 캔버스 상태를 추적하는 객체
class CanvasSyncObject: ObservableObject {
    @Published var contentOffset: CGPoint = .zero
    @Published var zoomScale: CGFloat = 1.0
    private var cancellable: Any?
    
    init(canvasView: PKCanvasView) {
        // PKCanvasView는 UIScrollView를 상속하므로 델리게이트나 타이머로 감시 가능
        // 심플하게 매 프레임 업데이트되는 타이머로 위치 동기화 (가장 확실한 방법)
        cancellable = Timer.publish(every: 0.016, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self, weak canvasView] _ in
                guard let cv = canvasView else { return }
                if self?.contentOffset != cv.contentOffset || self?.zoomScale != cv.zoomScale {
                    self?.contentOffset = cv.contentOffset
                    self?.zoomScale = cv.zoomScale
                }
            }
    }
}

// 배경 패턴 뷰 (기존 코드 유지)
struct PaperBackgroundView: View {
    let style: PaperStyle
    
    var body: some View {
        ZStack {
            Color(red: 0.98, green: 0.97, blue: 0.95)
            switch style {
            case .grid: GridView()
            case .lines: LinesView()
            case .cornell: CornellView()
            case .weekly: WeeklyView()
            case .study: StudyView()
            case .blank: EmptyView()
            }
        }
    }
}

// 이하 배경 패턴 상세 뷰들 (CornellView, WeeklyView 등) 코드는 이전과 동일하므로 내부 크기만 확장 지원하도록 유지...
// (이전 답변의 CornellView, GridView 등 포함)
struct CornellView: View {
    var body: some View {
        Canvas { context, size in
            let cueWidth: CGFloat = size.width * 0.25
            let summaryHeight: CGFloat = size.height * 0.1
            context.stroke(Path { p in
                p.move(to: CGPoint(x: cueWidth, y: 0))
                p.addLine(to: CGPoint(x: cueWidth, y: size.height - summaryHeight))
            }, with: .color(Color.red.opacity(0.15)), lineWidth: 1.5)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: 0, y: size.height - summaryHeight))
                p.addLine(to: CGPoint(x: size.width, y: size.height - summaryHeight))
            }, with: .color(Color.red.opacity(0.15)), lineWidth: 1.5)
            for y in stride(from: 100, to: size.height - summaryHeight, by: 35) {
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: cueWidth + 10, y: y))
                    p.addLine(to: CGPoint(x: size.width - 20, y: y))
                }, with: .color(Color.gray.opacity(0.1)), lineWidth: 0.5)
            }
        }
    }
}
struct WeeklyView: View {
    var body: some View {
        Canvas { context, size in
            let colWidth = size.width / 4
            let rowHeight = size.height / 5 // 확장된 높이에 맞춰 조정
            for i in 1...3 {
                let x = colWidth * CGFloat(i)
                context.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }, with: .color(Color.blue.opacity(0.1)), lineWidth: 1)
            }
            for i in 1...5 {
                let y = rowHeight * CGFloat(i)
                context.stroke(Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(Color.blue.opacity(0.1)), lineWidth: 1)
            }
        }
    }
}
struct StudyView: View {
    var body: some View {
        Canvas { context, size in
            let splitX: CGFloat = size.width * 0.5
            context.stroke(Path { p in p.move(to: CGPoint(x: splitX, y: 0)); p.addLine(to: CGPoint(x: splitX, y: size.height)) }, with: .color(Color.blue.opacity(0.2)), lineWidth: 1.5)
            for y in stride(from: 80, to: size.height, by: 40) {
                context.stroke(Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(Color.blue.opacity(0.05)), lineWidth: 0.5)
            }
        }
    }
}
struct GridView: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 30
            for x in stride(from: 0, to: size.width, by: step) {
                context.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }, with: .color(Color.blue.opacity(0.1)), lineWidth: 0.5)
            }
            for y in stride(from: 0, to: size.height, by: step) {
                context.stroke(Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(Color.blue.opacity(0.1)), lineWidth: 0.5)
            }
        }
    }
}
struct LinesView: View {
    var body: some View {
        Canvas { context, size in
            for y in stride(from: 100, to: size.height, by: 35) {
                context.stroke(Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(Color.gray.opacity(0.2)), lineWidth: 0.8)
            }
        }
    }
}
struct EmptyView: View { var body: some View { Color.clear } }
