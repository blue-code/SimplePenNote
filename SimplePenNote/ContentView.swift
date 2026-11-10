import SwiftUI
import PencilKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var noteStore = NoteStore()
    @StateObject private var lockManager = LockManager()
    @StateObject private var proStore = ProStore()
    @State private var canvasView = PKCanvasView()
    @State private var selectedColor: Color = Color(white: 0.1)
    @State private var selectedThickness: CGFloat = 4
    @State private var isEraserMode = false
    @State private var eraserType: PKEraserTool.EraserType = .vector
    @State private var showSidebar = false
    @State private var showTrash = false
    @State private var showSettings = false
    @State private var paywallContext: PaywallContext?
    @State private var showTemplates = false
    @State private var showBatchExport = false
    @State private var exportPage: NotePage?
    @State private var sharePayload: SharePayload?
    @State private var pendingExport: ExportRequest?
    @State private var exportTask: Task<Void, Never>?
    @State private var isPreparingExport = false
    @State private var exportProgress = 0
    @State private var exportTotal = 0
    @State private var pendingPaywall: PaywallContext?
    @State private var exportError: String?
    @State private var hasLoadedCanvas = false
    @State private var loadedPageID: UUID?
    @State private var searchText = ""

    private struct SharePayload: Identifiable {
        let id = UUID()
        let items: [Any]
    }

    private struct ExportRequest {
        let pages: [NotePage]
        let format: NoteExportFormat
    }

    private let penColors: [Color] = [Color(white: 0.1), .red, .blue, .green, .purple]

    var body: some View {
        ZStack {
            mainContent
                .allowsHitTesting(!isPreparingExport)
                .disabled(isPreparingExport)
            if isPreparingExport {
                Color.black.opacity(0.15).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView(value: Double(exportProgress), total: Double(max(1, exportTotal)))
                    Text("노트 내보내는 중").font(.headline)
                    Text("\(exportProgress) / \(exportTotal)페이지").font(.subheadline).foregroundStyle(.secondary)
                    Button("취소") { exportTask?.cancel() }
                }
                .padding(28)
                .frame(maxWidth: 300)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .shadow(radius: 20)
            }
            if lockManager.isLocked {
                LockScreenView(lockManager: lockManager).zIndex(99)
            }
        }
    }

    private var mainContent: some View {
        GeometryReader { proxy in
            canvasContent
                .onChange(of: proxy.size, initial: true) { _, size in
                    fitPage(size: size)
                }
        }
        .safeAreaInset(edge: .top, spacing: 0) { canvasHeader }
        .safeAreaInset(edge: .bottom, spacing: 0) { drawingToolbar }
        .overlay(alignment: .trailing) {
            if showSidebar { sidebarView.transition(.move(edge: .trailing)) }
        }
        .animation(.easeInOut(duration: 0.2), value: showSidebar)
        .sheet(item: $sharePayload) { ActivityViewController(activityItems: $0.items) }
        .sheet(isPresented: $showTrash) { TrashView(noteStore: noteStore) }
        .sheet(isPresented: $showSettings, onDismiss: finishSheet) {
            SettingsView(lockManager: lockManager, proStore: proStore) {
                pendingPaywall = .general
            }
        }
        .sheet(item: $paywallContext) { PaywallView(proStore: proStore, context: $0) }
        .sheet(isPresented: $showTemplates, onDismiss: finishSheet) {
            TemplatePickerView { style in
                guard proStore.isPro || noteStore.activePages.count < ProStore.freePageLimit else {
                    pendingPaywall = .pageLimit
                    return
                }
                saveCurrentDrawing()
                noteStore.addNewPage(paperStyle: style)
                loadCurrentDrawing()
                showSidebar = false
            }
        }
        .sheet(item: $exportPage, onDismiss: finishSheet) { page in
            ExportOptionsView(page: page, isPro: proStore.isPro) { format in
                pendingExport = ExportRequest(pages: [page], format: format)
                exportPage = nil
            } onUpgrade: {
                exportPage = nil
                pendingPaywall = .cleanExport
            }
        }
        .sheet(isPresented: $showBatchExport, onDismiss: finishSheet) {
            BatchExportView(pages: noteStore.activePages) { pages in
                showBatchExport = false
                guard proStore.isPro else { pendingPaywall = .batchExport; return }
                pendingExport = ExportRequest(pages: pages, format: .pdf)
            }
        }
        .alert("내보내기 실패", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(exportError ?? "") }
        .onAppear {
            guard !hasLoadedCanvas else { return }
            loadCurrentDrawing()
            hasLoadedCanvas = true
            applyLaunchOptions()
        }
        .onChange(of: noteStore.cloudMergeRevision) { _, _ in loadCurrentDrawing() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                saveCurrentDrawing()
                noteStore.flushNow()
                lockManager.lockIfEnabled()
            } else if phase == .active {
                Task { await proStore.refresh() }
            }
        }
    }

    private var canvasContent: some View {
        ZStack {
            ZoomableCanvasContainer(canvasView: $canvasView, paperStyle: noteStore.currentPage.paperStyle)
                .clipped()
            PencilKitView(
                canvasView: $canvasView,
                paperStyle: noteStore.currentPage.paperStyle,
                selectedColor: $selectedColor,
                selectedThickness: $selectedThickness,
                isEraserMode: $isEraserMode,
                eraserType: $eraserType,
                onDrawingChange: { drawing in
                    guard hasLoadedCanvas, drawing.dataRepresentation() != noteStore.currentPage.drawing.dataRepresentation() else { return }
                    noteStore.currentPage.drawing = drawing
                    noteStore.savePages()
                }
            )
        }
    }

    private var canvasHeader: some View {
        HStack(spacing: 14) {
            Button { saveCurrentDrawing(); showSidebar.toggle() } label: {
                Image(systemName: "sidebar.right")
            }.accessibilityLabel("나의 노트 열기")
            VStack(alignment: .leading, spacing: 2) {
                Text(noteStore.currentPage.title.isEmpty ? "제목 없는 노트" : noteStore.currentPage.title)
                    .font(.headline).lineLimit(1)
                Text(noteStore.currentPage.paperStyle.displayName)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { requestNewPage() } label: { Image(systemName: "plus.square") }
                .accessibilityLabel("템플릿으로 새 노트 만들기")
            Button { saveCurrentDrawing(); exportPage = noteStore.currentPage } label: {
                Image(systemName: "square.and.arrow.up")
            }.accessibilityLabel("현재 노트 내보내기")
        }
        .font(.title3)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var drawingToolbar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ForEach(penColors, id: \.self) { color in
                    Button { selectedColor = color; isEraserMode = false } label: {
                        Circle().fill(color).frame(width: 26, height: 26)
                            .padding(3)
                            .overlay(Circle().stroke(!isEraserMode && selectedColor == color ? Color.primary : .clear, lineWidth: 2))
                    }.accessibilityLabel(color == .red ? "빨간 펜" : color == .blue ? "파란 펜" : color == .green ? "초록 펜" : color == .purple ? "보라 펜" : "검정 펜")
                }
                Menu {
                    ForEach([CGFloat(2), 4, 8, 14], id: \.self) { width in
                        Button { selectedThickness = width; isEraserMode = false } label: {
                            Label("펜 굵기 \(Int(width))", systemImage: selectedThickness == width ? "checkmark" : "pencil.tip")
                        }
                    }
                } label: { Image(systemName: "lineweight") }
                .accessibilityLabel("펜 굵기 선택")
                Button {
                    if isEraserMode { eraserType = eraserType == .vector ? .bitmap : .vector }
                    isEraserMode = true
                } label: {
                    Image(systemName: eraserType == .vector ? "eraser.line.dashed" : "eraser.fill")
                        .foregroundStyle(isEraserMode ? Color.pink : .primary)
                }.accessibilityLabel("지우개, 다시 누르면 방식 전환")
            }
            HStack(spacing: 30) {
                Button { canvasView.undoManager?.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .accessibilityLabel("실행 취소")
                Button { canvasView.undoManager?.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .accessibilityLabel("다시 실행")
                Button { fitPage() } label: { Label("한눈에 보기", systemImage: "arrow.down.right.and.arrow.up.left") }
                    .font(.caption)
            }
        }
        .font(.title3)
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private var sidebarView: some View {
        GeometryReader { proxy in
            ZStack(alignment: .trailing) {
                Color.black.opacity(0.2).onTapGesture { showSidebar = false }
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("나의 노트").font(.title2.bold())
                        Spacer()
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("설정")
                        Button { showSidebar = false } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("노트 목록 닫기")
                    }
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("노트 제목 검색", text: $searchText)
                    }.padding(10).background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    Button { requestNewPage() } label: {
                        HStack {
                            Label("새 노트 만들기", systemImage: "plus")
                            Spacer()
                            Text(proStore.isPro ? "Pro" : "\(noteStore.activePages.count) / \(ProStore.freePageLimit)")
                                .font(.caption.bold())
                        }.padding(14).background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if filteredPages.isEmpty {
                                Text("검색 결과가 없습니다").foregroundStyle(.secondary).padding(.vertical, 24)
                            }
                            ForEach(filteredPages) { page in
                                NoteLibraryRow(page: page, isCurrent: page.id == noteStore.currentPage.id,
                                    onSelect: { selectPage(page) },
                                    onRename: { noteStore.markDirty(page) },
                                    onStyle: { style in page.paperStyle = style; noteStore.markDirty(page) },
                                    onExport: { saveCurrentDrawing(); exportPage = page },
                                    onDuplicate: { duplicatePage(page) },
                                    onDelete: {
                                        saveCurrentDrawing()
                                        noteStore.softDelete(page)
                                        loadCurrentDrawing()
                                    })
                            }
                        }
                    }
                    if !proStore.isPro {
                        Button { presentPaywall(.general) } label: {
                            HStack(alignment: .top) {
                                Image(systemName: "sparkles")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("노트에 한계를 두지 마세요").font(.subheadline.bold())
                                    Text("무제한 노트 · 깔끔한 출력 · PDF로 묶기")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption)
                            }.padding(14).background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                    HStack {
                        Button { saveCurrentDrawing(); requestBatchExport() } label: {
                            Label("PDF로 묶기", systemImage: "doc.on.doc")
                        }
                        Spacer()
                        Button { showTrash = true } label: { Image(systemName: "trash") }
                            .accessibilityLabel("휴지통")
                    }.font(.subheadline).padding(.vertical, 4)
                }
                .padding(20)
                .frame(width: min(380, proxy.size.width), height: proxy.size.height)
                .background(.regularMaterial)
            }
        }
    }

    private var filteredPages: [NotePage] {
        noteStore.activePages.filter { searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private func presentPaywall(_ context: PaywallContext) {
        paywallContext = context
    }

    private func requestNewPage() {
        guard proStore.isPro || noteStore.activePages.count < ProStore.freePageLimit else {
            presentPaywall(.pageLimit); return
        }
        showTemplates = true
    }

    private func requestBatchExport() {
        guard proStore.isPro else { presentPaywall(.batchExport); return }
        showBatchExport = true
    }

    private func duplicatePage(_ page: NotePage) {
        guard proStore.isPro || noteStore.activePages.count < ProStore.freePageLimit else {
            presentPaywall(.pageLimit); return
        }
        saveCurrentDrawing()
        noteStore.duplicatePage(page)
        loadCurrentDrawing()
        showSidebar = false
    }

    private func selectPage(_ page: NotePage) {
        saveCurrentDrawing()
        noteStore.flushNow()
        if let index = noteStore.pages.firstIndex(where: { $0.id == page.id }) {
            noteStore.currentPageIndex = index
            loadCurrentDrawing()
            showSidebar = false
        }
    }

    private func loadCurrentDrawing() {
        let page = noteStore.currentPage
        let switchedPage = loadedPageID != page.id
        if canvasView.drawing.dataRepresentation() != page.drawing.dataRepresentation() {
            canvasView.drawing = page.drawing
            canvasView.undoManager?.removeAllActions()
        } else if switchedPage {
            canvasView.undoManager?.removeAllActions()
        }
        loadedPageID = page.id
        if switchedPage { fitPage() }
    }

    private func fitPage(size: CGSize? = nil) {
        let viewport = size ?? canvasView.bounds.size
        guard viewport.width > 0, viewport.height > 0 else { return }
        let scale = min(viewport.width / NoteCanvas.size.width, viewport.height / NoteCanvas.size.height)
        canvasView.setZoomScale(max(0.05, min(1, scale)), animated: false)
        canvasView.setContentOffset(.zero, animated: false)
    }

    private func saveCurrentDrawing() {
        guard hasLoadedCanvas,
              canvasView.drawing.dataRepresentation() != noteStore.currentPage.drawing.dataRepresentation() else { return }
        noteStore.currentPage.drawing = canvasView.drawing
        noteStore.savePages()
    }

    private func startExport(_ request: ExportRequest) {
        // Freeze the selected content while a multi-page export yields to the UI.
        let pages = request.pages.map {
            NotePage(id: $0.id, title: $0.title, drawing: $0.drawing,
                     paperStyle: $0.paperStyle, createdAt: $0.createdAt)
        }
        let showWatermark = !proStore.isPro
        exportTotal = pages.count
        exportProgress = 0
        isPreparingExport = true
        exportTask = Task { @MainActor in
            defer {
                isPreparingExport = false
                exportTask = nil
            }
            do {
                let url: URL
                if request.format == .pdf && pages.count > 1 {
                    url = try await NoteExporter.exportPDF(pages: pages, showWatermark: showWatermark) {
                        exportProgress = $0
                    }
                } else {
                    try Task.checkCancellation()
                    url = try NoteExporter.export(pages: pages, format: request.format, showWatermark: showWatermark)
                }
                sharePayload = SharePayload(items: [url])
            } catch is CancellationError {
                // A cancelled job removes its unfinished file and returns to the notes.
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func finishSheet() {
        if let context = pendingPaywall {
            pendingPaywall = nil
            presentPaywall(context)
        } else if let request = pendingExport {
            pendingExport = nil
            startExport(request)
        }
    }

    private func applyLaunchOptions() {
        #if DEBUG
        guard DemoData.isEnabled else { return }
        switch DemoData.initialScreen {
        case "sidebar": showSidebar = true
        case "settings": showSettings = true
        case "trash": showTrash = true
        case "paywall": presentPaywall(.general)
        case "templates": showTemplates = true
        case "export": exportPage = noteStore.currentPage
        default: break
        }
        #endif
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

struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
