import SwiftUI
import PencilKit

struct ContentView: View {
    @StateObject private var noteStore = NoteStore()
    @State private var canvasView = PKCanvasView()
    
    @State private var selectedColor: Color = Color(red: 0.1, green: 0.1, blue: 0.1)
    @State private var selectedThickness: CGFloat = 4
    @State private var isEraserMode: Bool = false
    @State private var eraserType: PKEraserTool.EraserType = .vector // 지우개 타입 상태
    @State private var showSidebar = false
    
    let penColors: [Color] = [
        Color(red: 0.1, green: 0.1, blue: 0.1),
        Color(red: 1, green: 0.2, blue: 0.2),
        Color(red: 0.2, green: 0.4, blue: 1)
    ]
    
    var body: some View {
        ZStack {
            // 1. Paper Layer
            PaperBackgroundView(style: noteStore.currentPage.paperStyle)
            
            // 2. Drawing Layer
            PencilKitView(
                canvasView: $canvasView,
                paperStyle: noteStore.currentPage.paperStyle,
                selectedColor: $selectedColor,
                selectedThickness: $selectedThickness,
                isEraserMode: $isEraserMode,
                eraserType: $eraserType
            )
            
            // 3. Floating "Pill" Toolbar (최소 동선 툴바)
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
                        
                        // Smart Eraser Button (Tap to Switch Type)
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
                    
                    // Thickness Picker
                    HStack(spacing: 15) {
                        ForEach([2, 4, 8], id: \.self) { size in
                            Circle()
                                .fill(isEraserMode ? Color.pink.opacity(0.3) : selectedColor)
                                .frame(width: CGFloat(size) + 8, height: CGFloat(size) + 8)
                                .onTapGesture {
                                    if !isEraserMode {
                                        selectedThickness = CGFloat(size)
                                    }
                                }
                                .overlay(
                                    Circle().stroke(!isEraserMode && selectedThickness == CGFloat(size) ? Color.primary : Color.clear, lineWidth: 2).padding(-4)
                                )
                        }
                    }
                    
                    Divider().frame(height: 30)
                    
                    // Actions
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
            
            // 4. Sidebar Overlay
            if showSidebar {
                sidebarView
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .animation(.spring(), value: showSidebar)
        .animation(.easeInOut, value: isEraserMode)
        .animation(.easeInOut, value: eraserType)
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
                    Label("새 페이지", systemImage: "plus")
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                }
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(noteStore.pages.indices, id: \.self) { index in
                            HStack {
                                Text(noteStore.pages[index].title)
                                Spacer()
                                Menu {
                                    ForEach(PaperStyle.allCases) { style in
                                        Button(style.rawValue.capitalized) {
                                            noteStore.pages[index].paperStyle = style
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
            .padding()
            .frame(width: 300)
            .background(.ultraThinMaterial)
            .onTapGesture {}
        }
        .background(Color.black.opacity(0.1).onTapGesture { showSidebar = false })
        .ignoresSafeArea()
    }
    
    private func saveCurrentDrawing() {
        noteStore.pages[noteStore.currentPageIndex].drawing = canvasView.drawing
    }
}

#Preview {
    ContentView()
}
