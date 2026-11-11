import SwiftUI
import PencilKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var noteStore = NoteStore()
    @StateObject private var lockManager = LockManager()
    @StateObject private var proStore = ProStore()
    @State private var canvasView = PKCanvasView()
    @StateObject private var quickPreferences = QuickNotePreferences(persistChanges: {
        #if DEBUG
        return !DemoData.isEnabled
        #else
        return true
        #endif
    }())
    @StateObject private var snippetStore = InkSnippetStore(persistChanges: {
        #if DEBUG
        return !DemoData.isEnabled
        #else
        return true
        #endif
    }())
    @State private var isSelecting = false
    @State private var inkSelection: NoteSelection?
    @State private var selectionHasInk = false
    @State private var showSnippets = false
    @State private var returnToSnippets = false
    @State private var pendingSnippet: InkSnippet?
    @State private var placingSnippet: InkSnippet?
    @State private var placementCenter = CGPoint.zero
    @State private var placementBaseScale: CGFloat = 1
    @State private var placementMultiplier: CGFloat = 1
    @State private var placementPreview: UIImage?
    @State private var showPenOptions = false
    @State private var viewportPageID: UUID?
    @State private var savedViewports: [UUID: CanvasViewport] = [:]
    @State private var isEraserMode = false
    @State private var eraserType: PKEraserTool.EraserType = .vector
    @State private var showSidebar = false
    @State private var showTrash = false
    @State private var showSettings = false
    @State private var paywallContext: PaywallContext?
    @State private var showTemplates = false
    @State private var showBatchExport = false
    @State private var exportSheet: ExportSheetRequest?
    @State private var resumeExportSheet: ExportSheetRequest?
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
        var imageOptions = NoteImageExportOptions()
    }

    private struct ExportSheetRequest: Identifiable {
        let id = UUID()
        let page: NotePage
        var options = NoteImageExportOptions()
    }

    private struct CanvasViewport {
        let scale: CGFloat
        let offset: CGPoint
    }

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
                    prepareViewport(size: size)
                }
        }
        .safeAreaInset(edge: .top, spacing: 0) { canvasHeader.disabled(isSelecting || placingSnippet != nil) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelecting { selectionToolbar }
            else if placingSnippet != nil { placementToolbar }
            else { drawingToolbar }
        }
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
        .sheet(item: $paywallContext, onDismiss: {
            if let request = resumeExportSheet {
                resumeExportSheet = nil
                exportSheet = request
            } else if returnToSnippets {
                returnToSnippets = false
                showSnippets = true
            }
        }) { PaywallView(proStore: proStore, context: $0) }
        .sheet(isPresented: $showTemplates, onDismiss: finishSheet) {
            TemplatePickerView { style in createPage(style: style, fromSheet: true) }
        }
        .sheet(item: $exportSheet, onDismiss: finishSheet) { request in
            ExportOptionsView(page: request.page, proStore: proStore, initialOptions: request.options, onSaveSnippet: { title, options in
                try saveSnippet(title: title, options: options, page: request.page)
            }) { format, options in
                pendingExport = ExportRequest(pages: [request.page], format: format, imageOptions: options)
                exportSheet = nil
            } onUpgrade: { context, options in
                resumeExportSheet = ExportSheetRequest(page: request.page, options: options)
                pendingPaywall = context
                exportSheet = nil
            }
        }
        .sheet(isPresented: $showSnippets, onDismiss: finishSheet) {
            InkSnippetLibraryView(store: snippetStore, proStore: proStore) { item in
                guard proStore.isPro else { returnToSnippets = true; pendingPaywall = .snippetLibrary; showSnippets = false; return }
                pendingSnippet = item
                showSnippets = false
            } onUpgrade: {
                returnToSnippets = true
                pendingPaywall = .snippetLibrary
                showSnippets = false
            }
        }
        .sheet(isPresented: $showBatchExport, onDismiss: finishSheet) {
            BatchExportView(pages: noteStore.activePages) { pages in
                showBatchExport = false
                guard proStore.isPro else { pendingPaywall = .batchExport; return }
                pendingExport = ExportRequest(pages: pages, format: .pdf)
            }
        }
        .alert("작업을 완료하지 못했습니다", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
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
                selectedColor: quickPreferences.penColor.color,
                selectedThickness: quickPreferences.penWidth,
                isEraserMode: $isEraserMode,
                eraserType: $eraserType,
                onDrawingChange: { drawing in
                    guard hasLoadedCanvas, drawing.dataRepresentation() != noteStore.currentPage.drawing.dataRepresentation() else { return }
                    noteStore.currentPage.drawing = drawing
                    noteStore.savePages()
                }
            )
            .allowsHitTesting(!isSelecting && placingSnippet == nil)
            if isSelecting {
                InkSelectionOverlay(canvasView: canvasView, selection: $inkSelection) { validateSelection() }
            }
            if let item = placingSnippet {
                InkPlacementOverlay(item: item, preview: placementPreview, center: $placementCenter,
                                    scale: placementBaseScale * placementMultiplier, canvasView: canvasView)
            }
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
                .accessibilityLabel("바로 새 노트 만들기")
                .contextMenu { Button("종이를 골라 새 노트", systemImage: "square.grid.2x2") { requestTemplates() } }
            Button(action: beginSelection) { Image(systemName: "rectangle.dashed") }
                .accessibilityLabel("필기 부분 선택")
            Button { saveCurrentDrawing(); exportSheet = ExportSheetRequest(page: noteStore.currentPage) } label: {
                Image(systemName: "square.and.arrow.up")
            }.accessibilityLabel("현재 노트 내보내기")
        }
        .font(.title3)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var drawingToolbar: some View {
        VStack(spacing: 8) {
            if showPenOptions {
                HStack(spacing: 4) {
                    ForEach(NotePenColor.allCases) { pen in
                        Button { quickPreferences.penColor = pen; isEraserMode = false } label: {
                            Circle().fill(pen.color).frame(width: 24, height: 24).padding(5)
                                .overlay(Circle().stroke(!isEraserMode && quickPreferences.penColor == pen ? Color.primary : .clear, lineWidth: 2))
                                .frame(width: 44, height: 44)
                        }.accessibilityLabel(pen.label)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(QuickNotePreferences.widths, id: \.self) { width in
                            Button { quickPreferences.penWidth = width; isEraserMode = false } label: {
                                Label("펜 굵기 \(Int(width))", systemImage: quickPreferences.penWidth == width ? "checkmark" : "pencil.tip")
                            }
                        }
                    } label: { Image(systemName: "lineweight").frame(width: 44, height: 44) }
                    .accessibilityLabel("펜 굵기 선택")
                }
            }
            HStack(spacing: 0) {
                Button { isEraserMode = false } label: {
                    Image(systemName: "pencil.tip").foregroundStyle(.primary)
                        .overlay(alignment: .bottomTrailing) {
                            Circle().fill(quickPreferences.penColor.color).frame(width: 8, height: 8)
                                .overlay(Circle().stroke(Color.primary.opacity(0.4), lineWidth: 1))
                        }
                        .padding(8).background(!isEraserMode ? Color.indigo.opacity(0.1) : .clear, in: Circle())
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.accessibilityLabel("펜으로 쓰기")
                    .accessibilityValue("\(quickPreferences.penColor.label), 굵기 \(Int(quickPreferences.penWidth))")
                Button {
                    if isEraserMode { eraserType = eraserType == .vector ? .bitmap : .vector }
                    isEraserMode = true
                } label: {
                    Image(systemName: eraserType == .vector ? "eraser.line.dashed" : "eraser.fill")
                        .foregroundStyle(isEraserMode ? Color.pink : .primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.accessibilityLabel("지우개, 다시 누르면 방식 전환")
                Button { canvasView.undoManager?.undo() } label: {
                    Image(systemName: "arrow.uturn.backward").frame(maxWidth: .infinity, minHeight: 44)
                }.accessibilityLabel("실행 취소")
                Button { canvasView.undoManager?.redo() } label: {
                    Image(systemName: "arrow.uturn.forward").frame(maxWidth: .infinity, minHeight: 44)
                }.accessibilityLabel("다시 실행")
                Menu {
                    Button("쓰기 크기로 보기", systemImage: "pencil") { writingSize() }
                    Button("필기 한눈에 보기", systemImage: "arrow.down.right.and.arrow.up.left") { fitContent() }
                    Button("종이 전체 보기", systemImage: "rectangle") { fitPage() }
                } label: {
                    Image(systemName: "viewfinder").frame(maxWidth: .infinity, minHeight: 44)
                }.accessibilityLabel("보기 크기 선택")
                Button { withAnimation(.easeInOut(duration: 0.15)) { showPenOptions.toggle() } } label: {
                    Image(systemName: showPenOptions ? "chevron.down" : "slider.horizontal.3")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.accessibilityLabel(showPenOptions ? "펜 설정 접기" : "펜 설정 펼치기")
            }
        }
        .font(.title3)
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private var selectionToolbar: some View {
        VStack(spacing: 10) {
            Text("필요한 부분을 사각형으로 드래그하세요")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("취소") { isSelecting = false; inkSelection = nil }
                Spacer()
                Button("전체 필기 선택") {
                    inkSelection = NoteSelection(rect: canvasView.drawing.bounds.insetBy(dx: -12, dy: -12))
                    validateSelection()
                }.font(.subheadline)
                Spacer()
                Button("미리보기", action: previewSelection)
                    .font(.subheadline.bold()).disabled(!selectionHasInk || inkSelection == nil)
                    .accessibilityIdentifier("selection.preview")
            }
            if inkSelection != nil && !selectionHasInk {
                Text("필기가 있는 부분을 선택해 주세요.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14).background(.regularMaterial)
    }

    private var placementToolbar: some View {
        VStack(spacing: 8) {
            Text("끌어서 위치를 옮기고, 크기를 조절한 뒤 넣으세요.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("크기").font(.caption)
                Slider(value: $placementMultiplier, in: 0.25...2, step: 0.05).accessibilityLabel("손글씨 크기")
                Text("\(Int(placementMultiplier * 100))%").font(.caption.monospacedDigit()).frame(width: 42)
            }
            HStack {
                Button("취소") { placingSnippet = nil; placementPreview = nil }
                Spacer()
                Button("가운데 배치") { centerPlacement() }.font(.subheadline)
                Spacer()
                Button("노트에 넣기", action: commitPlacement).font(.subheadline.bold())
                    .accessibilityIdentifier("snippets.commitInsertion")
            }
        }.padding(14).frame(maxWidth: 560).frame(maxWidth: .infinity).background(.regularMaterial)
    }

    private func beginSelection() {
        saveCurrentDrawing()
        inkSelection = nil
        selectionHasInk = false
        isSelecting = true
    }

    private func validateSelection() {
        selectionHasInk = inkSelection.map { InkSelection.hasInk(canvasView.drawing, in: $0.rect) } ?? false
    }

    private func previewSelection() {
        guard let selection = inkSelection else { return }
        validateSelection()
        guard selectionHasInk else { return }
        saveCurrentDrawing()
        let page = noteStore.currentPage
        let frozen = NotePage(id: page.id, title: page.title, drawing: canvasView.drawing,
                              paperStyle: page.paperStyle, createdAt: page.createdAt)
        exportSheet = ExportSheetRequest(page: frozen, options: NoteImageExportOptions(selection: selection))
        isSelecting = false
        inkSelection = nil
    }

    private func saveSnippet(title: String, options: NoteImageExportOptions, page: NotePage) throws {
        guard proStore.isPro else { throw InkSnippetError.requiresPro }
        guard let selection = options.selection ?? NoteSelection(rect: page.drawing.bounds.insetBy(dx: -24, dy: -24)) else {
            throw InkSnippetError.emptySelection
        }
        try snippetStore.add(drawing: page.drawing, selection: selection, title: title)
    }

    private func beginPlacement(_ item: InkSnippet) {
        guard proStore.isPro else { returnToSnippets = true; presentPaywall(.snippetLibrary); return }
        do {
            placementPreview = UIImage(cgImage: try NotePNGRenderer.render(page: item.page, options: item.imageOptions,
                                                                          showWatermark: false, maximumDimension: 600))
            let viewport = canvasView.bounds.size
            let zoom = max(0.05, canvasView.zoomScale)
            placementBaseScale = min(1, max(1, viewport.width * 0.6) / (item.size.width * zoom),
                                    max(1, viewport.height * 0.6) / (item.size.height * zoom))
            placementMultiplier = 1
            centerPlacement()
            placingSnippet = item
        } catch { exportError = error.localizedDescription }
    }

    private func centerPlacement() {
        let zoom = max(0.05, canvasView.zoomScale)
        placementCenter = CGPoint(x: (canvasView.contentOffset.x + canvasView.bounds.width / 2) / zoom,
                                  y: (canvasView.contentOffset.y + canvasView.bounds.height / 2) / zoom)
    }

    private func commitPlacement() {
        guard let item = placingSnippet else { return }
        guard proStore.isPro else { presentPaywall(.snippetLibrary); return }
        let ink = item.drawing(centeredAt: placementCenter, scale: placementBaseScale * placementMultiplier)
        let page = noteStore.currentPage
        CanvasDrawingEdits.apply(canvasView.drawing.appending(ink), to: canvasView) { drawing in
            page.drawing = drawing
            noteStore.savePages()
        }
        placingSnippet = nil
        placementPreview = nil
        isEraserMode = false
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
                    Button("종이를 골라 새 노트", systemImage: "square.grid.2x2") { requestTemplates() }
                        .font(.subheadline)
                    Button("손글씨 보관함", systemImage: "square.stack.3d.up") {
                        saveCurrentDrawing()
                        showSidebar = false
                        showSnippets = true
                    }.font(.subheadline).accessibilityIdentifier("snippets.open")
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if filteredPages.isEmpty {
                                Text("검색 결과가 없습니다").foregroundStyle(.secondary).padding(.vertical, 24)
                            }
                            ForEach(filteredPages) { page in
                                NoteLibraryRow(page: page, isCurrent: page.id == noteStore.currentPage.id,
                                    onSelect: { selectPage(page) },
                                    onRename: { noteStore.markDirty(page) },
                                    onStyle: { style in page.paperStyle = style; quickPreferences.paperStyle = style; noteStore.markDirty(page) },
                                    onExport: { saveCurrentDrawing(); exportSheet = ExportSheetRequest(page: page) },
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
                                    Text("스케치를 자유롭게 꺼내 쓰세요").font(.subheadline.bold())
                                    Text("무제한 노트 · 투명 PNG · 손글씨 보관함")
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
        createPage(style: quickPreferences.paperStyle)
    }

    private func requestTemplates() {
        guard proStore.isPro || noteStore.activePages.count < ProStore.freePageLimit else {
            presentPaywall(.pageLimit); return
        }
        showTemplates = true
    }

    private func createPage(style: PaperStyle, fromSheet: Bool = false) {
        guard proStore.isPro || noteStore.activePages.count < ProStore.freePageLimit else {
            if fromSheet { pendingPaywall = .pageLimit } else { presentPaywall(.pageLimit) }
            return
        }
        saveCurrentDrawing()
        rememberViewport()
        quickPreferences.paperStyle = style
        isEraserMode = false
        noteStore.addNewPage(paperStyle: style)
        loadCurrentDrawing()
        showSidebar = false
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
        rememberViewport()
        noteStore.duplicatePage(page)
        loadCurrentDrawing()
        showSidebar = false
    }

    private func selectPage(_ page: NotePage) {
        saveCurrentDrawing()
        rememberViewport()
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
        if switchedPage { viewportPageID = nil; prepareViewport() }
    }

    private func rememberViewport() {
        guard let id = loadedPageID, viewportPageID == id else { return }
        savedViewports[id] = CanvasViewport(scale: canvasView.zoomScale, offset: canvasView.contentOffset)
    }

    private func prepareViewport(size: CGSize? = nil) {
        let viewport = size ?? canvasView.bounds.size
        guard viewport.width > 0, viewport.height > 0, let id = loadedPageID, viewportPageID != id else { return }
        viewportPageID = id
        if let saved = savedViewports[id] {
            canvasView.setZoomScale(saved.scale, animated: false)
            canvasView.setContentOffset(saved.offset, animated: false)
        } else if canvasView.drawing.strokes.isEmpty {
            writingSize()
        } else {
            fitContent(size: viewport)
        }
    }

    private func writingSize() {
        canvasView.setZoomScale(1, animated: false)
        canvasView.setContentOffset(.zero, animated: false)
    }

    private func fitContent(size: CGSize? = nil) {
        let viewport = size ?? canvasView.bounds.size
        let bounds = canvasView.drawing.bounds
        guard !bounds.isNull, !bounds.isEmpty, viewport.width > 0, viewport.height > 0 else { writingSize(); return }
        let padded = bounds.insetBy(dx: -30, dy: -30)
        let scale = max(0.05, min(1, viewport.width / padded.width, viewport.height / padded.height))
        canvasView.setZoomScale(scale, animated: false)
        canvasView.setContentOffset(CGPoint(x: max(0, padded.minX * scale), y: max(0, padded.minY * scale)), animated: false)
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
        // Recheck the current entitlement at the action boundary, including restored sheets.
        if request.format == .png, request.imageOptions.background == .transparent, !proStore.isPro {
            if let page = request.pages.first { resumeExportSheet = ExportSheetRequest(page: page, options: request.imageOptions) }
            presentPaywall(.transparentExport)
            return
        }
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
                    url = try NoteExporter.export(pages: pages, format: request.format, showWatermark: showWatermark, imageOptions: request.imageOptions)
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
        } else if let item = pendingSnippet {
            pendingSnippet = nil
            beginPlacement(item)
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
        case "export": exportSheet = ExportSheetRequest(page: noteStore.currentPage)
        case "selection": beginSelection()
        case "snippets": showSnippets = true
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
