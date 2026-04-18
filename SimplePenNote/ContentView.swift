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
            // 1. Zoomable Background Layer
            ZoomableCanvasContainer(canvasView: $canvasView, paperStyle: noteStore.currentPage.paperStyle)
            
            // 2. Drawing Layer (PencilKit handles Zoom natively)
            PencilKitView(
                canvasView: $canvasView,
                paperStyle: noteStore.currentPage.paperStyle,
                selectedColor: $selectedColor,
                selectedThickness: $selectedThickness,
                isEraserMode: $isEraserMode,
                eraserType: $eraserType
            )
            
            // 3. Floating Toolbar (UI)
            VStack {
                Spacer()
                HStack(spacing: 20) {
                    // Pen & Eraser Switchers
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
                    
                    // Zoom Reset Button (편의성 추가)
                    Button {
                        withAnimation {
                            canvasView.setZoomScale(1.0, animated: true)
                        }
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
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
                    canvasView.setZoomScale(1.0, animated: false) // 새 페이지는 줌 초기화
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
                                    TextField("제목", text: Binding(
                                        get: { noteStore.pages[index].title },
                                        set: { noteStore.pages[index].title = $0; noteStore.savePages() }
                                    ))
                                    .font(.body)
                                    .fontWeight(noteStore.currentPageIndex == index ? .bold : .regular)
                                    
                                    Spacer()
                                    
                                    Button {
                                        saveCurrentDrawing()
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
                                    canvasView.setZoomScale(1.0, animated: false)
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
    
    @MainActor
    private func exportNote(at index: Int) {
        let page = noteStore.pages[index]
        
        // 내보내기 시에는 전체 영역을 렌더링하도록 컨테이너 사이즈 조정
        let exportView = ExportContainer(page: page)
        let renderer = ImageRenderer(content: exportView)
        renderer.scale = 2.0 
        
        var items: [Any] = []
        if let image = renderer.uiImage { items.append(image) }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(page.title).pdf")
        renderer.render { size, context in
            var box = CGRect(origin: .zero, size: size)
            guard let pdfContext = CGContext(tempURL as CFURL, mediaBox: &box, nil) else { return }
            pdfContext.beginPDFPage(nil)
            context(pdfContext)
            pdfContext.endPDFPage()
            pdfContext.closePDF()
            items.append(tempURL)
        }
        
        if !items.isEmpty {
            exportItems = items
            isExporting = true
        }
    }
}

struct ExportContainer: View {
    let page: NotePage
    var body: some View {
        ZStack {
            PaperBackgroundView(style: page.paperStyle)
            // 전체 캔버스 영역(3000x5000) 렌더링
            Image(uiImage: page.drawing.image(from: CGRect(x: 0, y: 0, width: 3000, height: 5000), scale: 1.0))
                .resizable()
        }
        .frame(width: 1500, height: 2500) // 출력물은 절반 크기로 압축하여 선명도 유지
    }
}

// ActivityViewController 및 헬퍼 확장 코드는 이전과 동일...
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
