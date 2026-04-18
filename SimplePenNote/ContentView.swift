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
        
        // 현재 화면 크기 기준으로 렌더링 영역 설정
        let exportView = ExportContainer(page: page)
        let renderer = ImageRenderer(content: exportView)
        renderer.scale = 3.0 // 고해상도
        
        var items: [Any] = []
        
        // 1. 이미지 생성
        if let image = renderer.uiImage {
            items.append(image)
        }
        
        // 2. PDF 생성
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

// 렌더링용 컨테이너: 배경 + 펜 선을 합쳐줌
struct ExportContainer: View {
    let page: NotePage
    
    var body: some View {
        ZStack {
            // 배경 템플릿 포함
            PaperBackgroundView(style: page.paperStyle)
            
            // 펜 선 렌더링 (배경 투명하게 하여 위에 얹음)
            let drawingImage = page.drawing.image(from: page.drawing.bounds, scale: 2.0)
            Image(uiImage: drawingImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(20) // 여백
        }
        .frame(width: 800, height: 1100) // 표준 출력 사이즈 고정
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
