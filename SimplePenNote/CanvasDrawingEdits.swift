import PencilKit

@MainActor
enum CanvasDrawingEdits {
    static func apply(_ drawing: PKDrawing, to canvas: PKCanvasView, onChange: @escaping (PKDrawing) -> Void) {
        let previous = canvas.drawing
        canvas.drawing = drawing
        canvas.undoManager?.registerUndo(withTarget: canvas) { target in
            apply(previous, to: target, onChange: onChange)
        }
        onChange(drawing)
    }
}
