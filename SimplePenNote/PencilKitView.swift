import SwiftUI
import PencilKit

struct PencilKitView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var toolPicker: PKToolPicker
    @Binding var selectedColor: Color
    @Binding var selectedThickness: CGFloat
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        
        // Setup initial tool
        updateTool()
        
        toolPicker.addObserver(canvasView)
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        canvasView.becomeFirstResponder()
        
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        updateTool()
    }
    
    private func updateTool() {
        let uiColor = UIColor(selectedColor)
        let tool = PKInkingTool(.pen, color: uiColor, width: selectedThickness)
        canvasView.tool = tool
    }
}
