import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
private final class SnippetThumbnailCache {
    static let shared = SnippetThumbnailCache()
    private let cache = NSCache<NSUUID, UIImage>()

    private init() { cache.totalCostLimit = 16 * 1024 * 1024 }

    func image(for item: InkSnippet) throws -> UIImage {
        if let image = cache.object(forKey: item.id as NSUUID) { return image }
        let image = UIImage(cgImage: try NotePNGRenderer.render(page: item.page, options: item.imageOptions,
                                                               showWatermark: false, maximumDimension: 320))
        cache.setObject(image, forKey: item.id as NSUUID, cost: Int(image.size.width * image.size.height * 4))
        return image
    }
}

struct InkSnippetLibraryView: View {
    @ObservedObject var store: InkSnippetStore
    @ObservedObject var proStore: ProStore
    let onInsert: (InkSnippet) -> Void
    let onUpgrade: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: InkSnippet?
    @State private var newTitle = ""
    @State private var deleting: InkSnippet?
    @State private var error: String?
    @State private var status: String?
    @State private var sharedFile: SharedFile?

    private struct SharedFile: Identifiable { let id = UUID(); let url: URL }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("한 번 그려두고, 필요할 때 다시 꺼내 쓰세요.")
                        .font(.headline)
                    Text("노트에서 부분 선택 → 미리보기 → 보관함에 저장을 누르세요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if !proStore.isPro {
                        Button(action: onUpgrade) {
                            Label("Pro로 손글씨 보관함 사용", systemImage: "sparkles")
                                .frame(maxWidth: .infinity).padding(14)
                        }.buttonStyle(.borderedProminent)
                    }
                    if let warning = store.loadWarning { Text(warning).font(.caption).foregroundStyle(.secondary) }
                    if store.items.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "square.stack.3d.up").font(.system(size: 42)).foregroundStyle(.indigo)
                            Text("자주 쓰는 손글씨를 모아보세요").font(.headline)
                            Text("체크 표시, 화살표, 짧은 문구와 작은 그림을 저장해 다른 노트나 앱에서 재사용할 수 있습니다.")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 36)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 14)], spacing: 14) {
                            ForEach(store.items) { item in
                                VStack(alignment: .leading, spacing: 10) {
                                    SnippetThumbnail(item: item).frame(height: 110)
                                    HStack {
                                        Text(item.title).font(.subheadline.bold()).lineLimit(2)
                                        Spacer(minLength: 0)
                                        Menu {
                                            Button("투명 PNG 복사", systemImage: "doc.on.clipboard") { copy(item) }
                                            Button("투명 PNG 공유", systemImage: "square.and.arrow.up") { share(item) }
                                            Button("이름 바꾸기", systemImage: "pencil") { newTitle = item.title; renaming = item }
                                            Button("삭제", systemImage: "trash", role: .destructive) { deleting = item }
                                        } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                                        .accessibilityLabel("\(item.title) 작업")
                                    }
                                    Button {
                                        guard proStore.isPro else { onUpgrade(); return }
                                        onInsert(item)
                                    } label: {
                                        Label("노트에 넣기", systemImage: "plus.square.on.square").frame(maxWidth: .infinity)
                                    }.buttonStyle(.bordered).font(.caption)
                                        .accessibilityLabel("\(item.title) 노트에 넣기")
                                }
                                .padding(12).background(Color.gray.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    if let status { Text(status).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("snippets.status") }
                    Text("보관함은 이 기기에 저장됩니다. 노트에 넣은 필기는 해당 노트와 함께 iCloud로 동기화됩니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .navigationTitle("손글씨 보관함")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .sheet(item: $sharedFile) { ActivityViewController(activityItems: [$0.url]) }
            .alert("이름 바꾸기", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { item in
                TextField("손글씨 이름", text: $newTitle)
                Button("저장") {
                    do { try store.rename(item, title: newTitle) } catch { self.error = error.localizedDescription }
                    renaming = nil
                }
                Button("취소", role: .cancel) { renaming = nil }
            }
            .confirmationDialog("이 손글씨를 보관함에서 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { item in
                Button("삭제", role: .destructive) {
                    do { try store.delete(item) } catch { self.error = error.localizedDescription }
                    deleting = nil
                }
                Button("취소", role: .cancel) { deleting = nil }
            } message: { _ in Text("노트에 이미 넣은 필기는 그대로 남습니다.") }
            .alert("보관함", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("확인", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private func copy(_ item: InkSnippet) {
        guard proStore.isPro else { onUpgrade(); return }
        do {
            let image = try NoteExporter.pngImage(page: item.page, options: item.imageOptions, showWatermark: false)
            guard let data = image.pngData() else { throw NoteExportError.renderingFailed }
            UIPasteboard.general.setData(data, forPasteboardType: UTType.png.identifier)
            status = String(localized: "\(item.title)을 투명 PNG로 복사했습니다.")
        } catch { self.error = error.localizedDescription }
    }

    private func share(_ item: InkSnippet) {
        guard proStore.isPro else { onUpgrade(); return }
        do {
            sharedFile = SharedFile(url: try NoteExporter.export(pages: [item.page], format: .png,
                                                                  showWatermark: false, imageOptions: item.imageOptions))
        } catch { self.error = error.localizedDescription }
    }
}

private struct SnippetThumbnail: View {
    let item: InkSnippet
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            TransparencyGrid()
            if let image { Image(uiImage: image).resizable().scaledToFit().padding(8) }
            else if failed { Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary) }
            else { ProgressView() }
        }.clipShape(RoundedRectangle(cornerRadius: 9))
            .accessibilityLabel("\(item.title) 미리보기")
            .task(id: item.id) {
                do { image = try SnippetThumbnailCache.shared.image(for: item) }
                catch { failed = true }
            }
    }
}
