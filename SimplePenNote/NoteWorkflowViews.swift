import SwiftUI

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
    let isPro: Bool
    let onExport: (NoteExportFormat) -> Void
    let onUpgrade: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(page.title.isEmpty ? "제목 없는 노트" : page.title, systemImage: page.paperStyle.icon)
                    Text(isPro ? "워터마크 없이 종이와 필기를 함께 내보냅니다." : "무료 내보내기에는 SimplePenNote 워터마크가 표시됩니다.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("파일 형식 선택") {
                    Button { onExport(.pdf) } label: {
                        Label("PDF 문서로 공유", systemImage: "doc.richtext")
                    }
                    Button { onExport(.png) } label: {
                        Label("PNG 이미지로 공유", systemImage: "photo")
                    }
                }
                if !isPro {
                    Section {
                        Button(action: onUpgrade) {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("워터마크 없이 내보내기", systemImage: "sparkles").font(.headline)
                                Text("Pro 일회 구매로 깔끔하게 공유하세요.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle("내보내기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
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
