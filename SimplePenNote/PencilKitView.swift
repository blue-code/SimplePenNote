import SwiftUI
import PencilKit

struct PencilKitView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    let paperStyle: PaperStyle
    @Binding var selectedColor: Color
    @Binding var selectedThickness: CGFloat
    @Binding var isEraserMode: Bool
    @Binding var eraserType: PKEraserTool.EraserType
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.overrideUserInterfaceStyle = .light
        updateTool()
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        updateTool()
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

// 배경 패턴 뷰 고도화
struct PaperBackgroundView: View {
    let style: PaperStyle
    
    var body: some View {
        ZStack {
            Color(red: 0.98, green: 0.97, blue: 0.95) // 미색 종이
            
            switch style {
            case .grid: GridView()
            case .lines: LinesView()
            case .cornell: CornellView()
            case .weekly: WeeklyView()
            case .study: StudyView() // 오답노트
            case .blank: EmptyView()
            }
        }
        .ignoresSafeArea()
    }
}

// 1. 코넬 노트 (Cornell Note)
struct CornellView: View {
    var body: some View {
        Canvas { context, size in
            let cueWidth: CGFloat = size.width * 0.25
            let summaryHeight: CGFloat = size.height * 0.2
            
            // 수직 라인 (Cue Column)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: cueWidth, y: 0))
                p.addLine(to: CGPoint(x: cueWidth, y: size.height - summaryHeight))
            }, with: .color(Color.red.opacity(0.15)), lineWidth: 1.5)
            
            // 수평 라인 (Summary Section)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: 0, y: size.height - summaryHeight))
                p.addLine(to: CGPoint(x: size.width, y: size.height - summaryHeight))
            }, with: .color(Color.red.opacity(0.15)), lineWidth: 1.5)
            
            // 본문 가이드 라인
            for y in stride(from: 100, to: size.height - summaryHeight, by: 35) {
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: cueWidth + 10, y: y))
                    p.addLine(to: CGPoint(x: size.width - 20, y: y))
                }, with: .color(Color.gray.opacity(0.1)), lineWidth: 0.5)
            }
        }
    }
}

// 2. 위클리 플래너 (Weekly Planner)
struct WeeklyView: View {
    var body: some View {
        Canvas { context, size in
            let colWidth = size.width / 4
            let rowHeight = size.height / 2
            
            // 그리드 그리기
            for i in 1...3 {
                let x = colWidth * CGFloat(i)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }, with: .color(Color.blue.opacity(0.1)), lineWidth: 1)
            }
            
            context.stroke(Path { p in
                p.move(to: CGPoint(x: 0, y: rowHeight))
                p.addLine(to: CGPoint(x: size.width, y: rowHeight))
            }, with: .color(Color.blue.opacity(0.1)), lineWidth: 1)
        }
    }
}

// 3. 오답 노트 (Study/Incorrect Answer Note)
struct StudyView: View {
    var body: some View {
        Canvas { context, size in
            let headerHeight: CGFloat = 80
            let splitX: CGFloat = size.width * 0.5
            
            // 구분선
            context.stroke(Path { p in
                p.move(to: CGPoint(x: splitX, y: headerHeight))
                p.addLine(to: CGPoint(x: splitX, y: size.height))
            }, with: .color(Color.blue.opacity(0.2)), lineWidth: 1.5)
            
            context.stroke(Path { p in
                p.move(to: CGPoint(x: 0, y: headerHeight))
                p.addLine(to: CGPoint(x: size.width, y: headerHeight))
            }, with: .color(Color.blue.opacity(0.2)), lineWidth: 1.5)
        }
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

struct EmptyView: View {
    var body: some View {
        Color.clear
    }
}
