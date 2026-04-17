import SwiftUI
import PencilKit

struct ContentView: View {
    @StateObject private var noteStore = NoteStore()
    @State private var canvasView = PKCanvasView()
    
    @State private var selectedColor: Color = Color(red: 0.1, green: 0.1, blue: 0.1)
    @State private var selectedThickness: CGFloat = 4
    @State private var isEraserMode: Bool = false
    @State private var eraserType: PKEraserTool.EraserType = .vector
    @State private var showSidebar = false
    
    @State private var isExporting = false
    @State private var exportItems: [Any] = []
    
    let penColors: [Color] = [
        Color(red: 0.1, green: 0.1, blue: 0.1),
        Color(red: 1, green: 0.2, blue: 0.2),
        Color(red: 0.2, green: 0.4, blue: 1)
    ]
    
    var body: some View {
        ZStack {
            PaperBackgroundView(style: noteStore.currentPage.paperStyle)
            
            PencilKitView(
                canvasView: $canvasView,
                paperStyle: noteStore.currentPage.paperStyle,
                selectedColor: $selectedColor,
                selectedThickness: $selectedThickness,
                isEraserMode: $isEraserMode,
                eraserType: $eraserType
            )
            
            // Floating Toolbar
            VStack {
                Spacer()
                HStack(spacing: 20) {
                    HStack(spacing: 12) {
                        ForEach(penColors, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .shadow(radius: 2)
                                .scaleEffect(!isEraserMode && selectedColor == color ? 1.2 : 1.0)
                                .opacity(isEraserMode ? 0.4 : 1.0)
                                .onTapGesture {
                                    isEraserMode = false
                                    selectedColor = color
                                }
                        }
                        
                        Button {
                            if isEraserMode {
                                eraserType = (eraserType == .vector) ? .bitmap : .vector
                            } else {
                                isEraserMode = true
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isEraserMode ? Color.pink.opacity(0.15) : Color.clear)
                                    .frame(width: 44, height: 36)
                                
                                VStack(spacing: 1) {
                                    Image(systemName: eraserType == .vector ? "eraser.line.dashed" : "eraser.fill")
                                        .font(.system(size: 16, weight: .bold))
                                    Text(eraserType == .vector ? "OBJ" : "PIX")
                                        .font(.system(size: 8, weight: .heavy))
                                }
                                .foregroundColor(isEraserMode ? .pink : .secondary)
                            }
                        }
                    }
                    
                    Divider().frame(height: 30)
                    
                    HStack(spacing: 15) {
                        ForEach([2, 4, 8], id: \.self) { size in
                            Circle()
                                .fill(isEraserMode ? Color.pink.opacity(0.3) : selectedColor)
                                .frame(width: CGFloat(size) + 8, height: CGFloat(size) + 8)
                                .onTapGesture {
                                    if !isEraserMode { selectedThickness = CGFloat(size) }
                                }
                                .overlay(
                                    Circle().stroke(!isEraserMode && selectedThickness == CGFloat(size) ? Color.primary : Color.clear, lineWidth: 2).padding(-4)
                                )
                        }
                    }
                    
                    Divider().frame(height: 30)
                    
                    HStack(spacing: 15) {
                        Button(action: { canvasView.undoManager?.undo() }) {
                            Image(systemName: "arrow.uturn.backward").foregroundColor(.primary)
                        }
                        
                        Button(action: { showSidebar.toggle() }) {
                            Image(systemName: "list.bullet").foregroundColor(.primary)
                        }
                    }
                }
                .padding(.horizontal, 25)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
                .padding(.bottom, 30)
            }
            
            if showSidebar {
                sidebarView
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .animation(.spring(), value: showSidebar)
        .animation(.easeInOut, value: isEraserMode)
        .sheet(isPresented: $isExporting) {
            ActivityViewController(activityItems: exportItems)
        }
        .onDisappear {
            saveCurrentDrawing()
        }
    }
    
    var sidebarView: some View {
        HStack {
            Spacer()
            VStack(alignment: .leading, spacing: 20) {
                Text("나의 노트").font(.title2).bold().padding(.top, 60)
                
                Button(action: {
                    saveCurrentDrawing()
                    noteStore.addNewPage()
                    canvasView.drawing = PKDrawing()
                    showSidebar = false
                }) {
                    Label("새 페이지 추가", systemImage: "plus")
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                }
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(noteStore.pages.indices, id: \.self) { index in
                            VStack(spacing: 0) {
                                HStack {
                                    TextField("제목", text: $noteStore.pages[index], onEditingChanged: { _ in
                                        noteStore.savePages()
                                    })
                                    .font(.body)
                                    .fontWeight(noteStore.currentPageIndex == index ? .bold : .regular)
                                    
                                    Spacer()
                                    
                                    Button {
                                        exportNote(at: index)
                                    } label: {
                                        Image(systemName: "square.and.arrow.up")
                                            .foregroundColor(.blue)
                                    }
                                    
                                    Menu {
                                        ForEach(PaperStyle.allCases) { style in
                                            Button(style.displayName) {
                                                noteStore.pages[index].paperStyle = style
                                                noteStore.savePages()
                                            }
                                        }
                                    } label: {
                                        Image(systemName: noteStore.pages[index].paperStyle.icon)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding()
                                .background(noteStore.currentPageIndex == index ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                                .cornerRadius(8)
                                .onTapGesture {
                                    saveCurrentDrawing()
                                    noteStore.currentPageIndex = index
                                    canvasView.drawing = noteStore.pages[index].drawing
                                    showSidebar = false
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(width: 350)
            .background(.ultraThinMaterial)
        }
        .background(Color.black.opacity(0.1).onTapGesture { showSidebar = false })
        .ignoresSafeArea()
    }
    
    private func saveCurrentDrawing() {
        if noteStore.currentPageIndex < noteStore.pages.count {
            noteStore.pages[noteStore.currentPageIndex].drawing = canvasView.drawing
            noteStore.savePages()
        }
    }
    
    private func exportNote(at index: Int) {
        let drawing = noteStore.pages[index].drawing
        // 배경을 포함하여 이미지 생성
        let rect = drawing.bounds.isEmpty ? CGRect(x: 0, y: 0, width: 500, height: 500) : drawing.bounds
        if let image = drawing.image(from: rect, scale: 2.0).withBackground(color: .white) {
            exportItems = [image]
            isExporting = true
        }
    }
}

// TextField 바인딩 헬퍼
extension TextField where Label == Text {
    init(_ title: String, text: Binding<NotePage>, onEditingChanged: @escaping (Bool) -> Void) {
        self.init(title, text: Binding(
            get: { text.wrappedValue.title },
            set: { text.wrappedValue.title = $0 }
        ), onEditingChanged: onEditingChanged)
    }
}

// UIImage 배경 추가 헬퍼 (생략)
extension UIImage {
    func withBackground(color: UIColor) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        let rect = CGRect(origin: .zero, size: size)
        color.setFill()
        UIRectFill(rect)
        draw(in: rect)
        let res = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return res
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView()
}
