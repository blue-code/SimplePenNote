import SwiftUI
import PencilKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var noteStore = NoteStore()
    @StateObject private var lockManager = LockManager()
    @StateObject private var proStore = ProStore()
    @State private var canvasView = PKCanvasView()

    @State private var selectedColor: Color = Color(red: 0.1, green: 0.1, blue: 0.1)
    @State private var selectedThickness: CGFloat = 4
    @State private var isEraserMode: Bool = false
    @State private var eraserType: PKEraserTool.EraserType = .vector
    @State private var showSidebar = false
    @State private var showTrash = false
    @State private var showSettings = false
    @State private var showPaywall = false

    @State private var isExporting = false
    @State private var exportItems: [Any] = []
    @State private var didApplyLaunchOptions = false

    let penColors: [Color] = [
        Color(red: 0.1, green: 0.1, blue: 0.1),
        Color(red: 1, green: 0.2, blue: 0.2),
        Color(red: 0.2, green: 0.4, blue: 1)
    ]

    var body: some View {
        ZStack {
            mainContent
            if lockManager.isLocked {
                LockScreenView(lockManager: lockManager)
                    .transition(.opacity)
                    .zIndex(99)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lockManager.isLocked)
    }

    private var mainContent: some View {
        ZStack {
            ZoomableCanvasContainer(canvasView: $canvasView, paperStyle: noteStore.currentPage.paperStyle)

            PencilKitView(
                canvasView: $canvasView,
                paperStyle: noteStore.currentPage.paperStyle,
                selectedColor: $selectedColor,
                selectedThickness: $selectedThickness,
                isEraserMode: $isEraserMode,
                eraserType: $eraserType
            )

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
        .sheet(isPresented: $showTrash) {
            TrashView(noteStore: noteStore)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(lockManager: lockManager, proStore: proStore, showPaywall: $showPaywall)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(proStore: proStore)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background || phase == .inactive {
                saveCurrentDrawing()
                noteStore.flushNow()
                lockManager.lockIfEnabled()
            } else if phase == .active && !didApplyLaunchOptions {
                didApplyLaunchOptions = true
                applyLaunchOptions()
            }
        }
        .onDisappear {
            saveCurrentDrawing()
            noteStore.flushNow()
        }
    }

    var sidebarView: some View {
        HStack {
            Spacer()
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    Text("나의 노트").font(.title2).bold()
                    Spacer()
                    Button {
                        showTrash = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.secondary)
                    }
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 60)

                Button(action: {
                    if !proStore.isPro && noteStore.activePages.count >= ProStore.freePageLimit {
                        showPaywall = true
                        return
                    }
                    saveCurrentDrawing()
                    noteStore.addNewPage()
                    canvasView.drawing = PKDrawing()
                    canvasView.setZoomScale(1.0, animated: false)
                    showSidebar = false
                }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("새 페이지 추가")
                        if !proStore.isPro {
                            Spacer()
                            Text("\(noteStore.activePages.count) / \(ProStore.freePageLimit)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                }

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(noteStore.activePages) { page in
                            sidebarRow(for: page)
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

    @ViewBuilder
    private func sidebarRow(for page: NotePage) -> some View {
        let isCurrent = (currentIndex(of: page) == noteStore.currentPageIndex)
        HStack {
            TextField("제목", text: Binding(
                get: { page.title },
                set: { page.title = $0; noteStore.markDirty(page) }
            ))
            .font(.body)
            .fontWeight(isCurrent ? .bold : .regular)

            Spacer()

            Button {
                saveCurrentDrawing()
                exportNote(page: page)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(.blue)
            }

            Menu {
                ForEach(PaperStyle.allCases) { style in
                    Button(style.displayName) {
                        page.paperStyle = style
                        noteStore.markDirty(page)
                    }
                }
            } label: {
                Image(systemName: page.paperStyle.icon)
                    .foregroundColor(.secondary)
            }

            Button(role: .destructive) {
                if isCurrent { saveCurrentDrawing() }
                noteStore.softDelete(page)
                if let newIdx = noteStore.pages.firstIndex(where: { $0.id == noteStore.currentPage.id }) {
                    noteStore.currentPageIndex = newIdx
                    canvasView.drawing = noteStore.currentPage.drawing
                    canvasView.setZoomScale(1.0, animated: false)
                }
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(isCurrent ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
        .cornerRadius(8)
        .onTapGesture {
            saveCurrentDrawing()
            if let idx = currentIndex(of: page) {
                noteStore.currentPageIndex = idx
                canvasView.drawing = page.drawing
                canvasView.setZoomScale(1.0, animated: false)
                showSidebar = false
            }
        }
    }

    private func currentIndex(of page: NotePage) -> Int? {
        noteStore.pages.firstIndex { $0.id == page.id }
    }

    private func applyLaunchOptions() {
        #if DEBUG
        if DemoData.isEnabled {
            // Show the Cornell page (page 0) for the canvas screenshot — has a clear
            // template visible at this zoom and represents the app's primary use case.
            let demoIdx = 0
            if demoIdx < noteStore.pages.count {
                noteStore.currentPageIndex = demoIdx
                canvasView.drawing = noteStore.pages[demoIdx].drawing
            }
            canvasView.setZoomScale(0.45, animated: false)
            canvasView.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
        }
        guard let screen = DemoData.initialScreen else { return }
        switch screen {
        case "sidebar": showSidebar = true
        case "settings": showSettings = true
        case "trash": showTrash = true
        case "paywall": showPaywall = true
        default: break
        }
        #endif
    }

    private func saveCurrentDrawing() {
        if noteStore.currentPageIndex < noteStore.pages.count {
            noteStore.pages[noteStore.currentPageIndex].drawing = canvasView.drawing
            noteStore.savePages()
        }
    }

    @MainActor
    private func exportNote(page: NotePage) {
        let exportView = ExportContainer(page: page, showWatermark: !proStore.isPro)
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

// MARK: - Trash view

struct TrashView: View {
    @ObservedObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if noteStore.trashedPages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "trash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("휴지통이 비어 있습니다")
                            .font(.headline)
                        Text("삭제된 노트는 30일 후 자동으로 영구 삭제됩니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    List {
                        ForEach(noteStore.trashedPages) { page in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(page.title.isEmpty ? "(제목 없음)" : page.title)
                                        .font(.body)
                                    if let deletedAt = page.deletedAt {
                                        Text(daysRemainingText(deletedAt: deletedAt))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Button("복원") {
                                    noteStore.restore(page)
                                }
                                .buttonStyle(.bordered)
                                Button(role: .destructive) {
                                    noteStore.purge(page)
                                } label: {
                                    Image(systemName: "trash.fill")
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("휴지통")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func daysRemainingText(deletedAt: Date) -> String {
        let cutoff = deletedAt.addingTimeInterval(30 * 24 * 60 * 60)
        let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: cutoff).day ?? 0)
        return "\(days)일 후 영구 삭제"
    }
}

// MARK: - Export container

struct ExportContainer: View {
    let page: NotePage
    let showWatermark: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                PaperBackgroundView(style: page.paperStyle)
                Image(uiImage: page.drawing.image(from: CGRect(x: 0, y: 0, width: 3000, height: 5000), scale: 1.0))
                    .resizable()
            }
            if showWatermark {
                Text("SimplePenNote")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray.opacity(0.45))
                    .padding(12)
            }
        }
        .frame(width: 1500, height: 2500)
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
