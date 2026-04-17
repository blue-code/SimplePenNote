import SwiftUI
import PencilKit

struct PencilKitView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    let paperStyle: PaperStyle
    @Binding var selectedColor: Color
    @Binding var selectedThickness: CGFloat
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        updateTool()
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        updateTool()
    }
    
    private func updateTool() {
        let tool = PKInkingTool(.pen, color: UIColor(selectedColor), width: selectedThickness)
        canvasView.tool = tool
    }
}

// 배경 패턴 뷰
struct PaperBackgroundView: View {
    let style: PaperStyle
    
    var body: some View {
        ZStack {
            Color(red: 0.98, green: 0.97, blue: 0.95) // 따뜻한 미색 종이
            
            switch style {
            case .grid:
                GridView()
            case .lines:
                LinesView()
            case .blank:
                EmptyView()
            }
        }
        .ignoresSafeArea()
    }
}

struct GridView: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 30
            for x in stride(from: 0, to: size.width, by: step) {
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }, with: .color(Color.blue.opacity(0.1)), lineWidth: 0.5)
            }
            for y in stride(from: 0, to: size.height, by: step) {
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }, with: .color(Color.blue.opacity(0.1)), lineWidth: 0.5)
            }
        }
    }
}

struct LinesView: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 35
            for y in stride(from: 100, to: size.height, by: step) {
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }, with: .color(Color.gray.opacity(0.2)), lineWidth: 0.8)
            }
        }
    }
}
