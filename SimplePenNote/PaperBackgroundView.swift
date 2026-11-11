import SwiftUI

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
            case .blank: Color.clear
            }
        }
    }
}

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
