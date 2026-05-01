import SwiftUI
import PencilKit
import CloudKit
import Combine

// MARK: - PaperStyle

enum PaperStyle: String, CaseIterable, Identifiable, Codable {
    case blank, grid, lines, cornell, weekly, study
    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .blank: return "무지"
        case .grid: return "모눈"
        case .lines: return "줄글"
        case .cornell: return "코넬 노트"
        case .weekly: return "위클리"
        case .study: return "오답 노트"
        }
    }

    var icon: String {
        switch self {
        case .blank: return "square"
        case .grid: return "square.grid.3x3"
        case .lines: return "line.horizontal.3"
        case .cornell: return "rectangle.split.2x1"
        case .weekly: return "calendar.badge.clock"
        case .study: return "doc.text.magnifyingglass"
        }
    }
}

// MARK: - NotePage

class NotePage: Identifiable, ObservableObject, Codable {
    var id: UUID
    @Published var title: String
    @Published var drawing: PKDrawing
    @Published var paperStyle: PaperStyle
    @Published var createdAt: Date
    @Published var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, drawing, paperStyle, createdAt, deletedAt
        case legacyDate = "date"
    }

    init(id: UUID = UUID(),
         title: String = "새로운 노트",
         drawing: PKDrawing = PKDrawing(),
         paperStyle: PaperStyle = .grid,
         createdAt: Date = Date(),
         deletedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.drawing = drawing
        self.paperStyle = paperStyle
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        let drawingData = try c.decode(Data.self, forKey: .drawing)
        drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        paperStyle = try c.decode(PaperStyle.self, forKey: .paperStyle)
        // Backward-compatible: old cache used "date" instead of "createdAt"
        if let created = try c.decodeIfPresent(Date.self, forKey: .createdAt) {
            createdAt = created
        } else if let legacy = try c.decodeIfPresent(Date.self, forKey: .legacyDate) {
            createdAt = legacy
        } else {
            createdAt = Date()
        }
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(drawing.dataRepresentation(), forKey: .drawing)
        try c.encode(paperStyle, forKey: .paperStyle)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}

// MARK: - CloudKit constants

private enum CK {
    static let containerID = "iCloud.com.blueCode.SimplePenNote"
    static let recordType = "NotePage"
    enum Field {
        static let title = "title"
        static let paperStyle = "paperStyle"
        static let createdAt = "createdAt"
        static let deletedAt = "deletedAt"
        static let drawing = "drawing"
    }
}

// MARK: - NotePage <-> CKRecord

extension NotePage {
    func toCKRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: CK.recordType, recordID: recordID)
        record[CK.Field.title] = title as CKRecordValue
        record[CK.Field.paperStyle] = paperStyle.rawValue as CKRecordValue
        record[CK.Field.createdAt] = createdAt as CKRecordValue
        if let deletedAt {
            record[CK.Field.deletedAt] = deletedAt as CKRecordValue
        }
        // Drawing → CKAsset via temp file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(id.uuidString).pkdrawing")
        do {
            try drawing.dataRepresentation().write(to: tempURL, options: .atomic)
            record[CK.Field.drawing] = CKAsset(fileURL: tempURL)
        } catch {
            // Drawing write failed — record will be saved without drawing data
        }
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> NotePage? {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        let title = record[CK.Field.title] as? String ?? "노트"
        let paperStyleRaw = record[CK.Field.paperStyle] as? String ?? "blank"
        let paperStyle = PaperStyle(rawValue: paperStyleRaw) ?? .blank
        let createdAt = record[CK.Field.createdAt] as? Date ?? record.creationDate ?? Date()
        let deletedAt = record[CK.Field.deletedAt] as? Date

        var drawing = PKDrawing()
        if let asset = record[CK.Field.drawing] as? CKAsset,
           let url = asset.fileURL,
           let data = try? Data(contentsOf: url),
           let parsed = try? PKDrawing(data: data) {
            drawing = parsed
        }
        return NotePage(id: id, title: title, drawing: drawing,
                        paperStyle: paperStyle, createdAt: createdAt, deletedAt: deletedAt)
    }
}

// MARK: - NoteStore

@MainActor
class NoteStore: ObservableObject {
    @Published var pages: [NotePage] = []
    @Published var currentPageIndex: Int = 0
    @Published var isInitialSyncing: Bool = false

    private lazy var container = CKContainer(identifier: CK.containerID)
    private var database: CKDatabase { container.privateCloudDatabase }

    private let localCacheKey = "SimplePenNote_LocalCache_v2"
    private let didMigrateFromKVSKey = "SimplePenNote_DidMigrateFromKVS_v1"
    private let legacyKVSKey = "SimplePenNote_Pages"

    private var pendingCloudSync = Set<UUID>()

    init() {
        #if DEBUG
        if DemoData.isEnabled {
            self.pages = DemoData.buildPages()
            self.currentPageIndex = 0
            return
        }
        #endif

        loadFromLocalCache()
        if pages.filter({ $0.deletedAt == nil }).isEmpty {
            let first = NotePage(title: "첫 영감", paperStyle: .grid)
            pages.append(first)
            pendingCloudSync.insert(first.id)
            saveLocalCache()
        }

        Task { [weak self] in
            await self?.migrateFromKVSIfNeeded()
            await self?.fetchAllFromCloud()
        }
    }

    // MARK: - Public API

    var currentPage: NotePage {
        let active = activePages
        if active.isEmpty {
            let p = NotePage()
            pages.append(p)
            currentPageIndex = pages.count - 1
            return p
        }
        if currentPageIndex >= pages.count || pages[currentPageIndex].deletedAt != nil {
            currentPageIndex = pages.firstIndex(where: { $0.deletedAt == nil }) ?? 0
        }
        return pages[currentPageIndex]
    }

    var activePages: [NotePage] {
        pages.filter { $0.deletedAt == nil }
    }

    var trashedPages: [NotePage] {
        pages.filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    func addNewPage() {
        let new = NotePage(title: "노트 \(activePages.count + 1)")
        pages.append(new)
        currentPageIndex = pages.count - 1
        pendingCloudSync.insert(new.id)
        saveLocalCache()
        scheduleFlush()
    }

    /// Save current drawing on the active canvas. Local cache is updated immediately;
    /// CloudKit upload is debounced (2.5s) and triggered on flush points.
    /// For sidebar edits to non-current pages, callers should use markDirty(_:) instead.
    func savePages() {
        if currentPageIndex < pages.count {
            pendingCloudSync.insert(pages[currentPageIndex].id)
        }
        saveLocalCache()
        scheduleFlush()
    }

    /// Mark a page for immediate cloud sync (used when changing paperStyle, title, etc.)
    func markDirty(_ page: NotePage) {
        pendingCloudSync.insert(page.id)
        saveLocalCache()
        scheduleFlush()
    }

    /// Soft delete — page goes to trash with deletedAt = now.
    func softDelete(_ page: NotePage) {
        page.deletedAt = Date()
        pendingCloudSync.insert(page.id)
        if currentPageIndex < pages.count, pages[currentPageIndex].id == page.id {
            currentPageIndex = pages.firstIndex(where: { $0.deletedAt == nil }) ?? 0
        }
        // Ensure at least one active page remains.
        if activePages.isEmpty {
            let fresh = NotePage(title: "새 노트", paperStyle: .grid)
            pages.append(fresh)
            currentPageIndex = pages.count - 1
            pendingCloudSync.insert(fresh.id)
        }
        saveLocalCache()
        scheduleFlush()
    }

    /// Restore from trash.
    func restore(_ page: NotePage) {
        page.deletedAt = nil
        pendingCloudSync.insert(page.id)
        saveLocalCache()
        scheduleFlush()
    }

    /// Permanently delete a page (called from trash or by purge).
    func purge(_ page: NotePage) {
        let id = page.id
        pages.removeAll { $0.id == id }
        saveLocalCache()
        Task { [weak self] in
            await self?.deleteFromCloud(recordName: id.uuidString)
        }
    }

    /// Auto-purge: remove trashed pages older than 30 days.
    func purgeExpiredTrash() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let expired = pages.filter { ($0.deletedAt ?? .distantFuture) < cutoff }
        for page in expired {
            purge(page)
        }
    }

    /// Public flush entry point — call on backgrounding, page switch, etc.
    func flushNow() {
        Task { [weak self] in
            await self?.flushPendingCloudSync()
        }
    }

    // MARK: - Local cache

    private func loadFromLocalCache() {
        guard let data = UserDefaults.standard.data(forKey: localCacheKey),
              let decoded = try? JSONDecoder().decode([NotePage].self, from: data) else {
            return
        }
        self.pages = decoded
    }

    private func saveLocalCache() {
        guard let data = try? JSONEncoder().encode(pages) else { return }
        UserDefaults.standard.set(data, forKey: localCacheKey)
    }

    // MARK: - Migration from old NSUbiquitousKeyValueStore

    private func migrateFromKVSIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: didMigrateFromKVSKey) else { return }
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        if let data = store.data(forKey: legacyKVSKey),
           let oldPages = try? JSONDecoder().decode([NotePage].self, from: data) {
            // Merge into local pages by id (don't duplicate).
            for old in oldPages where !pages.contains(where: { $0.id == old.id }) {
                pages.append(old)
                pendingCloudSync.insert(old.id)
            }
            saveLocalCache()
            store.removeObject(forKey: legacyKVSKey)
            store.synchronize()
        }
        UserDefaults.standard.set(true, forKey: didMigrateFromKVSKey)
    }

    // MARK: - Cloud operations

    private func fetchAllFromCloud() async {
        isInitialSyncing = true
        defer { isInitialSyncing = false }

        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: CK.recordType, predicate: predicate)
        do {
            var fetched: [NotePage] = []
            var cursor: CKQueryOperation.Cursor?
            let (matchResults, nextCursor) = try await database.records(matching: query, resultsLimit: 100)
            cursor = nextCursor
            for (_, result) in matchResults {
                if case .success(let record) = result, let p = NotePage.fromCKRecord(record) {
                    fetched.append(p)
                }
            }
            while let c = cursor {
                let (more, next) = try await database.records(continuingMatchFrom: c, resultsLimit: 100)
                cursor = next
                for (_, result) in more {
                    if case .success(let record) = result, let p = NotePage.fromCKRecord(record) {
                        fetched.append(p)
                    }
                }
            }

            mergeFromCloud(fetched: fetched)
            // Now flush anything pending (local-only pages that haven't been pushed).
            await flushPendingCloudSync()
            // Auto-purge expired trash.
            purgeExpiredTrash()
        } catch {
            // Likely: no iCloud account, network error, or schema not yet deployed.
            // Local cache continues working.
        }
    }

    /// Merge cloud pages into local. Cloud is source of truth for known IDs;
    /// pages that exist locally but not in cloud are pushed up (pending).
    private func mergeFromCloud(fetched: [NotePage]) {
        var merged: [UUID: NotePage] = [:]
        for p in pages { merged[p.id] = p }
        for cloudPage in fetched {
            // Cloud version wins for existing ids (last-write-wins via record modificationDate is implicit).
            merged[cloudPage.id] = cloudPage
        }
        // Pages only present locally (not in cloud) need to be pushed.
        let cloudIDs = Set(fetched.map { $0.id })
        for p in pages where !cloudIDs.contains(p.id) {
            pendingCloudSync.insert(p.id)
        }
        pages = Array(merged.values).sorted { $0.createdAt < $1.createdAt }
        // Recover currentPageIndex
        if pages.isEmpty {
            let fresh = NotePage(title: "첫 영감", paperStyle: .grid)
            pages.append(fresh)
            pendingCloudSync.insert(fresh.id)
            currentPageIndex = 0
        } else if currentPageIndex >= pages.count {
            currentPageIndex = max(0, pages.count - 1)
        }
        saveLocalCache()
    }

    private func flushPendingCloudSync() async {
        let snapshot = pendingCloudSync
        pendingCloudSync.removeAll()
        for id in snapshot {
            guard let page = pages.first(where: { $0.id == id }) else { continue }
            let record = page.toCKRecord()
            do {
                _ = try await database.modifyRecords(saving: [record], deleting: [],
                                                     savePolicy: .changedKeys, atomically: false)
            } catch {
                // Re-queue on failure.
                pendingCloudSync.insert(id)
            }
        }
    }

    private func deleteFromCloud(recordName: String) async {
        let recordID = CKRecord.ID(recordName: recordName)
        do {
            _ = try await database.modifyRecords(saving: [], deleting: [recordID],
                                                 savePolicy: .changedKeys, atomically: false)
        } catch {
            // Will retry on next purge cycle.
        }
    }

    // MARK: - Throttled flush

    private var flushTask: Task<Void, Never>?

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5s
            guard !Task.isCancelled else { return }
            await self?.flushPendingCloudSync()
        }
    }
}
