import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct NoteLibraryRow: View {
    @ObservedObject var page: NotePage
    let isCurrent: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onStyle: (PaperStyle) -> Void
    let onExport: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: onSelect) {
                    Image(systemName: page.paperStyle.icon)
                        .font(.title3).frame(width: 36, height: 36)
                        .background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }.accessibilityLabel("\(page.title) 열기")
                TextField("제목 없는 노트", text: Binding(get: { page.title }, set: { page.title = $0; onRename() }))
                    .font(.subheadline.weight(isCurrent ? .bold : .medium))
                    .submitLabel(.done)
                Menu {
                    Button("노트 열기", systemImage: "pencil", action: onSelect)
                    Button("내보내기", systemImage: "square.and.arrow.up", action: onExport)
                    Button("복제", systemImage: "doc.on.doc", action: onDuplicate)
                    Menu("종이 바꾸기", systemImage: "square.grid.2x2") {
                        ForEach(PaperStyle.allCases) { style in
                            Button(style.displayName, systemImage: style.icon) { onStyle(style) }
                        }
                    }
                    Button("휴지통으로 이동", systemImage: "trash", role: .destructive, action: onDelete)
                } label: { Image(systemName: "ellipsis").padding(8) }
                .accessibilityLabel("\(page.title) 작업")
            }
            Button(action: onSelect) {
                HStack {
                    Text(page.paperStyle.displayName)
                    Spacer()
                    if isCurrent { Text("편집 중").foregroundStyle(.indigo) }
                    else { Text(page.createdAt, style: .date) }
                }.font(.caption).foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(12)
        .background(isCurrent ? Color.indigo.opacity(0.06) : Color.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isCurrent ? Color.indigo.opacity(0.35) : .clear))
    }
}

struct TemplatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (PaperStyle) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("오늘의 기록에 맞는 종이")
                        .font(.title2.bold())
                    Text("모든 템플릿은 무료입니다. 나중에 종이를 바꿔도 필기는 그대로 남습니다.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 16)], spacing: 16) {
                        ForEach(PaperStyle.allCases) { style in
                            Button {
                                dismiss()
                                onSelect(style)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    PaperPreview(style: style).frame(height: 140)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08)))
                                    Text(style.displayName).font(.headline)
                                    Text(style.purpose).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(24)
            }
            .navigationTitle("새 노트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
        }
    }
}

private struct PaperPreview: View {
    let style: PaperStyle
    var body: some View {
        GeometryReader { proxy in
            PaperBackgroundView(style: style)
                .frame(width: 600, height: 800)
                .scaleEffect(proxy.size.width / 600, anchor: .topLeading)
        }.clipped().accessibilityHidden(true)
    }
}

extension PaperStyle {
    var purpose: String {
        switch self {
        case .blank: return "자유로운 스케치와 아이디어"
        case .grid: return "수식, 도형, 반듯한 필기"
        case .lines: return "일기와 긴 글 기록"
        case .cornell: return "핵심 단서와 요약 정리"
        case .weekly: return "한 주의 일정과 할 일"
        case .study: return "문제와 풀이를 나란히"
        }
    }
}

struct ExportOptionsView: View {
    @ObservedObject var page: NotePage
    @ObservedObject var proStore: ProStore
    let onExport: (NoteExportFormat, NoteImageExportOptions) -> Void
    let onUpgrade: (PaywallContext, NoteImageExportOptions) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var options: NoteImageExportOptions
    @State private var preview: UIImage?
    @State private var previewError: String?
    @State private var copyStatus: String?

    init(page: NotePage, proStore: ProStore, initialOptions: NoteImageExportOptions = .init(),
         onExport: @escaping (NoteExportFormat, NoteImageExportOptions) -> Void,
         onUpgrade: @escaping (PaywallContext, NoteImageExportOptions) -> Void) {
        self.page = page
        self.proStore = proStore
        self.onExport = onExport
        self.onUpgrade = onUpgrade
        _options = State(initialValue: initialOptions)
    }

    private struct PreviewKey: Hashable {
        let options: NoteImageExportOptions
        let isPro: Bool
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(page.title.isEmpty ? "제목 없는 노트" : page.title, systemImage: page.paperStyle.icon)
                    Text(proStore.isPro ? "워터마크 없이 저장하고 공유합니다." : "무료 내보내기에는 SimplePenNote 워터마크가 표시됩니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("PNG 미리보기") {
                    ZStack {
                        TransparencyGrid()
                        if let preview {
                            Image(uiImage: preview).resizable().scaledToFit().padding(8)
                        } else if let previewError {
                            Text(previewError).font(.caption).padding()
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel(options.background == .transparent ? "투명 배경 PNG 미리보기" : "종이 배경 PNG 미리보기")
                    Toggle("필기 주변 여백 자동 제거", isOn: Binding(
                        get: { options.area == .content },
                        set: { options.area = $0 ? .content : .page }))
                        .accessibilityIdentifier("export.crop")
                    Toggle(isOn: Binding(get: { options.background == .transparent },
                                         set: { options.background = $0 ? .transparent : .paper })) {
                        HStack {
                            Text("투명 배경")
                            if !proStore.isPro { Text("Pro").font(.caption.bold()).foregroundStyle(.indigo) }
                        }
                    }.accessibilityIdentifier("export.transparent")
                    if page.drawing.strokes.isEmpty {
                        Text("빈 노트는 종이 전체를 내보냅니다. 투명 PNG는 필기를 추가한 뒤 사용할 수 있습니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("자동 자르기는 무료입니다. 투명 PNG는 배경 없이 필기와 스케치만 담습니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("저장 및 공유") {
                    Button {
                        if options.background == .transparent && !proStore.isPro {
                            onUpgrade(.transparentExport, options)
                        } else { onExport(.png, options) }
                    } label: { Label("PNG 이미지로 공유", systemImage: "photo") }
                    .disabled(options.background == .transparent && page.drawing.strokes.isEmpty)
                    Button(action: copyTransparentPNG) {
                        Label("투명 PNG 복사", systemImage: "doc.on.clipboard")
                    }
                    .disabled(page.drawing.strokes.isEmpty)
                    .accessibilityIdentifier("export.copyTransparent")
                    if let copyStatus {
                        Text(copyStatus).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("export.copyStatus")
                    }
                    Button { onExport(.pdf, .fullPage) } label: {
                        Label("PDF 문서로 공유", systemImage: "doc.richtext")
                    }
                    Text("PDF는 종이 전체를 한 페이지로 저장합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !proStore.isPro {
                    Section {
                        Button { onUpgrade(.cleanExport, options) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("워터마크 없이 내보내기", systemImage: "sparkles").font(.headline)
                                Text("Pro 일회 구매로 투명 PNG와 깔끔한 출력을 함께 사용하세요.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle("내보내기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .task(id: PreviewKey(options: options, isPro: proStore.isPro)) {
                do {
                    preview = try autoreleasepool {
                        let image = try NoteExporter.pngImage(page: page, options: options, showWatermark: !proStore.isPro)
                        let scale = min(1, 600 / max(image.size.width, image.size.height))
                        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                        let format = UIGraphicsImageRendererFormat()
                        format.scale = 1
                        format.opaque = false
                        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                            image.draw(in: CGRect(origin: .zero, size: size))
                        }
                    }
                    previewError = nil
                } catch {
                    preview = nil
                    previewError = error.localizedDescription
                }
            }
        }
        .presentationDetents([.large])
    }

    private func copyTransparentPNG() {
        var transparent = options
        transparent.background = .transparent
        guard proStore.isPro else { onUpgrade(.transparentExport, transparent); return }
        do {
            let data = try autoreleasepool {
                let image = try NoteExporter.pngImage(page: page, options: transparent, showWatermark: false)
                guard let data = image.pngData() else { throw NoteExportError.renderingFailed }
                return data
            }
            UIPasteboard.general.setData(data, forPasteboardType: UTType.png.identifier)
            options = transparent
            copyStatus = "투명 PNG를 복사했습니다. 다른 앱에 붙여넣으세요."
        } catch { copyStatus = error.localizedDescription }
    }
}

private struct TransparencyGrid: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let step: CGFloat = 12
            for row in 0..<Int(ceil(size.height / step)) {
                for column in 0..<Int(ceil(size.width / step)) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * step, y: CGFloat(row) * step, width: step, height: step)),
                                 with: .color(.gray.opacity(0.15)))
                }
            }
        }.accessibilityHidden(true)
    }
}

struct BatchExportView: View {
    let pages: [NotePage]
    let onExport: ([NotePage]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("선택한 노트를 하나의 PDF로 묶습니다. 아래 목록 순서대로 한 장씩 들어갑니다.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button(selectedIDs.count == pages.count ? "전체 선택 해제" : "전체 선택") {
                        selectedIDs = selectedIDs.count == pages.count ? [] : Set(pages.map(\.id))
                    }
                }
                Section("\(selectedIDs.count)개 선택") {
                    ForEach(pages) { page in
                        Button {
                            if selectedIDs.contains(page.id) { selectedIDs.remove(page.id) }
                            else { selectedIDs.insert(page.id) }
                        } label: {
                            HStack {
                                Image(systemName: selectedIDs.contains(page.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(page.id) ? .indigo : .secondary)
                                Text(page.title.isEmpty ? "제목 없는 노트" : page.title).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: page.paperStyle.icon).foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }.accessibilityAddTraits(selectedIDs.contains(page.id) ? .isSelected : [])
                    }
                }
            }
            .navigationTitle("PDF로 묶기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("\(selectedIDs.count)개 내보내기") { onExport(pages.filter { selectedIDs.contains($0.id) }) }
                        .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }
}
