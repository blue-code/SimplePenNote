import SwiftUI
import PencilKit

struct ContentView: View {
    @StateObject private var noteStore = NoteStore()
    @State private var canvasView = PKCanvasView()
    @State private var toolPicker = PKToolPicker()
    
    @State private var selectedColor: Color = .black
    @State private var selectedThickness: CGFloat = 5
    @State private var showSidebar = true
    
    let colors: [Color] = [.black, .red, .blue]
    let thicknesses: [CGFloat] = [2, 5, 10]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                
                HStack(spacing: 0) {
                    // Main Canvas Area
                    VStack(spacing: 0) {
                        // Custom Toolbar
                        HStack(spacing: 24) {
                            // Colors
                            HStack(spacing: 12) {
                                ForEach(colors, id: \.self) { color in
                                    Button {
                                        selectedColor = color
                                    } label: {
                                        Circle()
                                            .fill(color)
                                            .frame(width: 32, height: 32)
                                            .overlay(
                                                Circle()
                                                    .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 2)
                                                    .padding(-4)
                                            )
                                    }
                                }
                            }
                            
                            Divider().frame(height: 32)
                            
                            // Thickness
                            HStack(spacing: 16) {
                                ForEach(thicknesses, id: \.self) { thickness in
                                    Button {
                                        selectedThickness = thickness
                                    } label: {
                                        Circle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 24 + (thickness * 0.5), height: 24 + (thickness * 0.5))
                                            .overlay(
                                                Circle()
                                                    .fill(Color.primary)
                                                    .frame(width: thickness, height: thickness)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .stroke(selectedThickness == thickness ? Color.blue : Color.clear, lineWidth: 2)
                                                    .padding(-4)
                                            )
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            // Undo/Redo
                            HStack(spacing: 16) {
                                Button {
                                    canvasView.undoManager?.undo()
                                } label: {
                                    Image(systemName: "arrow.uturn.backward.circle")
                                        .font(.title2)
                                }
                                
                                Button {
                                    canvasView.undoManager?.redo()
                                } label: {
                                    Image(systemName: "arrow.uturn.forward.circle")
                                        .font(.title2)
                                }
                                
                                Button {
                                    canvasView.drawing = PKDrawing()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.title2)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        
                        // Canvas
                        PencilKitView(
                            canvasView: $canvasView,
                            toolPicker: $toolPicker,
                            selectedColor: $selectedColor,
                            selectedThickness: $selectedThickness
                        )
                        .background(Color.white)
                        .cornerRadius(12)
                        .padding(16)
                    }
                    
                    // Right Sidebar (Page List)
                    if showSidebar {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("목록")
                                    .font(.headline)
                                Spacer()
                                Button {
                                    addNewPage()
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                }
                            }
                            .padding()
                            
                            List {
                                ForEach(noteStore.pages.indices, id: \.self) { index in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(noteStore.pages[index].title)
                                                .font(.body)
                                                .fontWeight(noteStore.currentPageIndex == index ? .bold : .regular)
                                            Text(noteStore.pages[index].date, style: .date)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if noteStore.currentPageIndex == index {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        switchPage(to: index)
                                    }
                                }
                                .onDelete(perform: deletePage)
                            }
                            .listStyle(.plain)
                        }
                        .frame(width: 250)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .transition(.move(edge: .trailing))
                    }
                }
            }
            .navigationTitle("Simple Pen Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation {
                            showSidebar.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                }
            }
        }
        .onAppear {
            switchPage(to: 0)
        }
    }
    
    private func switchPage(to index: Int) {
        // Save current drawing
        noteStore.pages[noteStore.currentPageIndex].drawing = canvasView.drawing
        
        // Switch index
        noteStore.currentPageIndex = index
        
        // Load new drawing
        canvasView.drawing = noteStore.pages[index].drawing
    }
    
    private func addNewPage() {
        // Save current drawing
        noteStore.pages[noteStore.currentPageIndex].drawing = canvasView.drawing
        
        // Add new page
        noteStore.addNewPage()
        
        // Clear canvas
        canvasView.drawing = PKDrawing()
    }
    
    private func deletePage(at indexSet: IndexSet) {
        noteStore.deletePage(at: indexSet)
        canvasView.drawing = noteStore.currentPage.drawing
    }
}

#Preview {
    ContentView()
}
