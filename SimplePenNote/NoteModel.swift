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
        case .blank: return String(localized: "무지")
        case .grid: return String(localized: "모눈")
        case .lines: return String(localized: "줄글")
        case .cornell: return String(localized: "코넬 노트")
        case .weekly: return String(localized: "위클리")
        case .study: return String(localized: "오답 노트")
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
         title: String = String(localized: "새로운 노트"),
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
    func toCKRecord() throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: CK.recordType, recordID: recordID)
        record[CK.Field.title] = title as CKRecordValue
        record[CK.Field.paperStyle] = paperStyle.rawValue as CKRecordValue
        record[CK.Field.createdAt] = createdAt as CKRecordValue
        // Explicitly clear the tombstone when restoring a cloud-backed page.
        record[CK.Field.deletedAt] = deletedAt as CKRecordValue?
        // Drawing → CKAsset via temp file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(id.uuidString)-\(UUID().uuidString).pkdrawing")
        try drawing.dataRepresentation().write(to: tempURL, options: .atomic)
        record[CK.Field.drawing] = CKAsset(fileURL: tempURL)
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> NotePage? {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        let title = record[CK.Field.title] as? String ?? String(localized: "노트")
        let paperStyleRaw = record[CK.Field.paperStyle] as? String ?? "blank"
        let paperStyle = PaperStyle(rawValue: paperStyleRaw) ?? .blank
        let createdAt = record[CK.Field.createdAt] as? Date ?? record.creationDate ?? Date()
        let deletedAt = record[CK.Field.deletedAt] as? Date

        // An unreadable asset must not replace a good local drawing with a blank.
        guard let asset = record[CK.Field.drawing] as? CKAsset,
              let url = asset.fileURL,
              let data = try? Data(contentsOf: url),
              let drawing = try? PKDrawing(data: data) else { return nil }
        return NotePage(id: id, title: title, drawing: drawing,
                        paperStyle: paperStyle, createdAt: createdAt, deletedAt: deletedAt)
    }
}

// MARK: - NoteStore

@MainActor
class NoteStore: ObservableObject {
    @Published var pages: [NotePage] = []
    @Published var currentPageIndex: Int = 0 {
        didSet { persistCurrentSelection() }
    }
    @Published var isInitialSyncing: Bool = false
    @Published private(set) var cloudMergeRevision: Int = 0

    private lazy var container = CKContainer(identifier: CK.containerID)
    private var database: CKDatabase { container.privateCloudDatabase }

    private let localCacheKey = "SimplePenNote_LocalCache_v2"
    private let pendingSyncKey = "SimplePenNote_PendingSync_v1"
    private let pendingDeletionKey = "SimplePenNote_PendingDeletion_v1"
    private let selectionKey = "SimplePenNote_CurrentPage_v1"

    private var pendingCloudSync = Set<UUID>()
    private var pendingCloudDeletion = Set<UUID>()
    // Revisions prevent a completed upload from clearing edits made during its await.
    private var localRevisions: [UUID: UInt64] = [:]
    private var isFlushing = false
    private let defaults: UserDefaults
    private let syncWithCloud: Bool
    private let isDemoMode: Bool

    init(defaults: UserDefaults = .standard, syncWithCloud: Bool = true) {
        #if DEBUG
        self.isDemoMode = DemoData.isEnabled
        #else
        self.isDemoMode = false
        #endif
        self.defaults = defaults
        self.syncWithCloud = syncWithCloud && !isDemoMode
        #if DEBUG
        if isDemoMode {
            self.pages = DemoData.buildPages()
            self.currentPageIndex = 0
            return
        }
        #endif

        loadPendingOperations()
        loadFromLocalCache()
        if pages.filter({ $0.deletedAt == nil }).isEmpty {
            let first = NotePage(title: String(localized: "첫 영감"), paperStyle: .blank)
            pages.append(first)
            currentPageIndex = pages.count - 1
            enqueueSync(first.id)
            saveLocalCache()
        }

        if syncWithCloud {
            Task { [weak self] in
                await self?.fetchAllFromCloud()
            }
        }
    }

    // MARK: - Public API

    var currentPage: NotePage {
        let active = activePages
        if active.isEmpty {
            addNewPage()
            return pages[currentPageIndex]
        }
        if !pages.indices.contains(currentPageIndex) || pages[currentPageIndex].deletedAt != nil {
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

    func addNewPage(title: String? = nil, paperStyle: PaperStyle = .grid) {
        let new = NotePage(title: title ?? String(localized: "노트 \(activePages.count + 1)"), paperStyle: paperStyle)
        pages.append(new)
        currentPageIndex = pages.count - 1
        enqueueSync(new.id)
        saveLocalCache()
        scheduleFlush()
    }

    func duplicatePage(_ page: NotePage) {
        let copy = NotePage(title: String(localized: "\(page.title) 복사본"), drawing: page.drawing,
                            paperStyle: page.paperStyle)
        pages.append(copy)
        currentPageIndex = pages.count - 1
        enqueueSync(copy.id)
        saveLocalCache()
        scheduleFlush()
    }

    /// Save current drawing on the active canvas. Local cache is updated immediately;
    /// CloudKit upload is debounced (2.5s) and triggered on flush points.
    /// For sidebar edits to non-current pages, callers should use markDirty(_:) instead.
    func savePages() {
        if pages.indices.contains(currentPageIndex) {
            enqueueSync(pages[currentPageIndex].id)
        }
        saveLocalCache()
        scheduleFlush()
    }

    /// Mark a page for immediate cloud sync (used when changing paperStyle, title, etc.)
    func markDirty(_ page: NotePage) {
        objectWillChange.send()
        enqueueSync(page.id)
        saveLocalCache()
        scheduleFlush()
    }

    /// Soft delete — page goes to trash with deletedAt = now.
    func softDelete(_ page: NotePage) {
        objectWillChange.send()
        page.deletedAt = Date()
        enqueueSync(page.id)
        if pages.indices.contains(currentPageIndex), pages[currentPageIndex].id == page.id {
            currentPageIndex = pages.firstIndex(where: { $0.deletedAt == nil }) ?? 0
        }
        // Ensure at least one active page remains.
        if activePages.isEmpty {
            let fresh = NotePage(title: String(localized: "새 노트"), paperStyle: .grid)
            pages.append(fresh)
            currentPageIndex = pages.count - 1
            enqueueSync(fresh.id)
        }
        saveLocalCache()
        scheduleFlush()
    }

    /// Restore from trash.
    func restore(_ page: NotePage) {
        objectWillChange.send()
        page.deletedAt = nil
        enqueueSync(page.id)
        saveLocalCache()
        scheduleFlush()
    }

    /// Permanently delete a page (called from trash or by purge).
    func purge(_ page: NotePage) {
        let selectedID = pages.indices.contains(currentPageIndex) ? pages[currentPageIndex].id : nil
        let id = page.id
        pages.removeAll { $0.id == id }
        pendingCloudSync.remove(id)
        localRevisions.removeValue(forKey: id)
        pendingCloudDeletion.insert(id)
        recoverSelection(preferredID: selectedID)
        saveLocalCache()
        flushNow()
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
        guard let data = defaults.data(forKey: localCacheKey),
              let decoded = try? JSONDecoder().decode([NotePage].self, from: data) else {
            return
        }
        self.pages = decoded
        let selectedID = defaults.string(forKey: selectionKey).flatMap(UUID.init(uuidString:))
        if let selectedID, let index = pages.firstIndex(where: { $0.id == selectedID && $0.deletedAt == nil }) {
            currentPageIndex = index
        } else {
            currentPageIndex = pages.firstIndex(where: { $0.deletedAt == nil }) ?? 0
        }
    }

    private func persistCurrentSelection() {
        guard !isDemoMode, pages.indices.contains(currentPageIndex) else { return }
        defaults.set(pages[currentPageIndex].id.uuidString, forKey: selectionKey)
    }

    private func loadPendingOperations() {
        pendingCloudSync = Set((defaults.stringArray(forKey: pendingSyncKey) ?? [])
            .compactMap(UUID.init(uuidString:)))
        pendingCloudDeletion = Set((defaults.stringArray(forKey: pendingDeletionKey) ?? [])
            .compactMap(UUID.init(uuidString:)))
    }

    private func savePendingOperations() {
        guard !isDemoMode else { return }
        defaults.set(pendingCloudSync.map(\.uuidString), forKey: pendingSyncKey)
        defaults.set(pendingCloudDeletion.map(\.uuidString), forKey: pendingDeletionKey)
    }

    private func enqueueSync(_ id: UUID) {
        pendingCloudSync.insert(id)
        localRevisions[id, default: 0] += 1
    }

    private func recoverSelection(preferredID: UUID?) {
        if let preferredID, let index = pages.firstIndex(where: { $0.id == preferredID && $0.deletedAt == nil }) {
            currentPageIndex = index
        } else if let index = pages.firstIndex(where: { $0.deletedAt == nil }) {
            currentPageIndex = index
        } else {
            let fresh = NotePage(title: String(localized: "첫 영감"), paperStyle: .blank)
            pages.append(fresh)
            enqueueSync(fresh.id)
            currentPageIndex = pages.count - 1
        }
    }

    private func saveLocalCache() {
        guard !isDemoMode else { return }
        guard let data = try? JSONEncoder().encode(pages) else { return }
        defaults.set(data, forKey: localCacheKey)
        savePendingOperations()
        persistCurrentSelection()
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
            isInitialSyncing = false
            // Now flush anything pending (local-only pages that haven't been pushed).
            await flushPendingCloudSync()
            // Auto-purge expired trash.
            purgeExpiredTrash()
        } catch {
            // Likely: no iCloud account, network error, or schema not yet deployed.
            // Local cache continues working. Preserve the queue for a later flush.
        }
    }

    /// Keep local edits queued for upload; refresh unmodified pages from iCloud.
    private func mergeFromCloud(fetched: [NotePage]) {
        let selectedID = pages.indices.contains(currentPageIndex) ? pages[currentPageIndex].id : nil
        var merged = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0) })
        for cloudPage in fetched where !pendingCloudDeletion.contains(cloudPage.id) {
            if !pendingCloudSync.contains(cloudPage.id) {
                merged[cloudPage.id] = cloudPage
            }
        }
        let cloudIDs = Set(fetched.map(\.id))
        for page in pages where !cloudIDs.contains(page.id) && !pendingCloudDeletion.contains(page.id) {
            pendingCloudSync.insert(page.id)
        }
        pages = merged.values.filter { !pendingCloudDeletion.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
        recoverSelection(preferredID: selectedID)
        saveLocalCache()
        cloudMergeRevision += 1
    }

    private func flushPendingCloudSync() async {
        // A fetch started before an upload can otherwise merge its stale snapshot
        // after that upload has cleared the local dirty flag.
        guard syncWithCloud, !isInitialSyncing, !isFlushing else { return }
        isFlushing = true
        defer {
            isFlushing = false
            savePendingOperations()
        }

        // Keep operations queued until CloudKit confirms each result, including
        // partial failures returned by a non-atomic modifyRecords call.
        for id in pendingCloudDeletion {
            let recordID = CKRecord.ID(recordName: id.uuidString)
            do {
                let result = try await database.modifyRecords(saving: [], deleting: [recordID],
                                                              savePolicy: .changedKeys, atomically: false)
                if let deleted = result.deleteResults[recordID] {
                    do {
                        try deleted.get()
                        pendingCloudDeletion.remove(id)
                    } catch let error as CKError where error.code == .unknownItem {
                        pendingCloudDeletion.remove(id)
                    }
                }
            } catch let error as CKError where error.code == .unknownItem {
                pendingCloudDeletion.remove(id)
            } catch {
                // Durable queue retries on the next flush or app launch.
            }
        }

        for id in pendingCloudSync {
            guard !pendingCloudDeletion.contains(id), let page = pages.first(where: { $0.id == id }) else {
                pendingCloudSync.remove(id)
                continue
            }
            let revision = localRevisions[id, default: 0]
            do {
                let record = try page.toCKRecord()
                defer {
                    if let url = (record[CK.Field.drawing] as? CKAsset)?.fileURL {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
                let result = try await database.modifyRecords(saving: [record], deleting: [],
                                                              savePolicy: .changedKeys, atomically: false)
                if let saved = result.saveResults[record.recordID] {
                    _ = try saved.get()
                    if localRevisions[id, default: 0] == revision {
                        pendingCloudSync.remove(id)
                    }
                }
            } catch {
                // Never discard the local drawing or its pending upload on failure.
            }
        }
    }

    // MARK: - Throttled flush

    private var flushTask: Task<Void, Never>?

    private func scheduleFlush() {
        guard syncWithCloud else { return }
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5s
            guard !Task.isCancelled else { return }
            await self?.flushPendingCloudSync()
        }
    }
}
