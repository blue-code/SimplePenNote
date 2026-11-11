import Foundation
import PencilKit
import Combine

struct InkSnippet: Identifiable {
    let id: UUID
    var title: String
    let drawing: PKDrawing
    let size: CGSize
    let createdAt: Date

    var page: NotePage { NotePage(id: id, title: title, drawing: drawing, paperStyle: .blank, createdAt: createdAt) }
    var imageOptions: NoteImageExportOptions {
        NoteImageExportOptions(background: .transparent, selection: NoteSelection(rect: CGRect(origin: .zero, size: size)))
    }

    /// Place a copy at the visible center while retaining vector ink and masks.
    func drawing(centeredAt center: CGPoint, fitting size: CGSize) -> PKDrawing {
        let scale = min(1, max(1, size.width) / self.size.width, max(1, size.height) / self.size.height)
        return drawing(centeredAt: center, scale: scale)
    }

    func drawing(centeredAt center: CGPoint, scale: CGFloat) -> PKDrawing {
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                         tx: center.x - self.size.width * scale / 2,
                                         ty: center.y - self.size.height * scale / 2)
        return drawing.transformed(using: transform)
    }
}

enum InkSnippetError: LocalizedError {
    case emptySelection, invalidFile, requiresPro
    var errorDescription: String? {
        switch self {
        case .requiresPro: return String(localized: "Pro 권한을 확인한 뒤 다시 시도해 주세요.")
        case .emptySelection: return String(localized: "선택한 범위에 필기가 없습니다. 범위를 다시 골라 주세요.")
        case .invalidFile: return String(localized: "손글씨 항목을 읽을 수 없습니다. 원본 파일은 그대로 보관합니다.")
        }
    }
}

/// Each item is an atomic, independently recoverable file in Application Support.
/// The library is local; inserting ink into a note uses the existing note sync.
@MainActor
final class InkSnippetStore: ObservableObject {
    @Published private(set) var items: [InkSnippet] = []
    @Published private(set) var loadWarning: String?
    private let directory: URL
    private let persistChanges: Bool

    private struct Document: Codable {
        var version = 1
        let id: UUID
        let title: String
        let drawing: Data
        let width: CGFloat
        let height: CGFloat
        let createdAt: Date
    }

    #if DEBUG
    /// App Store capture content; never written to disk.
    func loadDemo(_ demo: [InkSnippet]) { items = demo }
    #endif

    init(directory: URL? = nil, persistChanges: Bool = true) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SimplePenNote/InkSnippets", isDirectory: true)
        self.persistChanges = persistChanges
        if persistChanges { reload() }
    }

    @discardableResult
    func add(drawing: PKDrawing, selection: NoteSelection, title: String) throws -> InkSnippet {
        let clipped = InkSelection.drawing(from: drawing, in: selection)
        let size = selection.rect.size
        guard InkSelection.hasInk(clipped, in: CGRect(origin: .zero, size: size)) else { throw InkSnippetError.emptySelection }
        let item = InkSnippet(id: UUID(), title: Self.cleanTitle(title), drawing: clipped, size: size, createdAt: Date())
        try write(item)
        items.insert(item, at: 0)
        return item
    }

    func rename(_ item: InkSnippet, title: String) throws {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items[index]
        updated.title = Self.cleanTitle(title)
        try write(updated)
        items[index] = updated
    }

    func delete(_ item: InkSnippet) throws {
        let url = fileURL(id: item.id)
        if persistChanges, FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        items.removeAll { $0.id == item.id }
    }

    private static func cleanTitle(_ title: String) -> String {
        let value = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        return value.isEmpty ? String(localized: "내 손글씨") : value
    }

    private func fileURL(id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).inksnippet") }

    private func write(_ item: InkSnippet) throws {
        guard persistChanges else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let document = Document(id: item.id, title: item.title, drawing: item.drawing.dataRepresentation(),
                                width: item.size.width, height: item.size.height, createdAt: item.createdAt)
        try JSONEncoder().encode(document).write(to: fileURL(id: item.id), options: .atomic)
    }

    private func reload() {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "inksnippet" {
                do {
                    let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: file))
                    let size = CGSize(width: document.width, height: document.height)
                    guard document.version == 1, document.width >= 1, document.height >= 1, UUID(uuidString: file.deletingPathExtension().lastPathComponent) == document.id,
                          let region = NoteSelection(rect: CGRect(origin: .zero, size: size)) else { throw InkSnippetError.invalidFile }
                    let drawing = try PKDrawing(data: document.drawing)
                    guard !drawing.strokes.isEmpty else { throw InkSnippetError.invalidFile }
                    items.append(InkSnippet(id: document.id, title: Self.cleanTitle(document.title), drawing: drawing,
                                            size: region.rect.size, createdAt: document.createdAt))
                } catch { loadWarning = String(localized: "일부 손글씨를 불러오지 못했습니다. 원본 파일은 유지됩니다.") }
            }
            items.sort { $0.createdAt > $1.createdAt }
        } catch { loadWarning = String(localized: "손글씨 보관함을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.") }
    }
}
