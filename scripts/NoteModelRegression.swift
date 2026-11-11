import AppKit

extension NoteStore {
    static func runReliabilityChecks() throws {
        let suite = "SimplePenNote.ModelRegression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let point = PKStrokePoint(location: CGPoint(x: 10, y: 20), timeOffset: 0,
                                  size: CGSize(width: 3, height: 3), opacity: 1,
                                  force: 1, azimuth: 0, altitude: .pi / 2)
        let stroke = PKStroke(ink: PKInk(.pen, color: .black),
                              path: PKStrokePath(controlPoints: [point], creationDate: Date()))
        let first = NotePage(title: "Local drawing", drawing: PKDrawing(strokes: [stroke]),
                             paperStyle: .study, createdAt: Date(timeIntervalSince1970: 200))
        let second = NotePage(title: "Selected page", paperStyle: .weekly,
                              createdAt: Date(timeIntervalSince1970: 100))
        defaults.set(try JSONEncoder().encode([first, second]), forKey: "SimplePenNote_LocalCache_v2")
        defaults.set(second.id.uuidString, forKey: "SimplePenNote_CurrentPage_v1")
        defaults.set([first.id.uuidString], forKey: "SimplePenNote_PendingSync_v1")
        let store = NoteStore(defaults: defaults, syncWithCloud: false)
        precondition(store.currentPage.id == second.id, "Selection must restore at launch")
        precondition(store.pages.first?.drawing.strokes.count == 1, "Drawing must load from cache")
        let stale = NotePage(id: first.id, title: "Stale cloud", createdAt: first.createdAt)
        store.mergeFromCloud(fetched: [stale, second])
        precondition(store.pages.first(where: { $0.id == first.id })?.drawing.strokes.count == 1,
                     "Queued local drawing must survive stale cloud merge")
        precondition(store.currentPage.id == second.id, "Cloud sorting must retain selected UUID")
        store.currentPageIndex = -1
        precondition(store.currentPage.deletedAt == nil, "Negative index must recover safely")
        store.addNewPage(title: "Cornell test", paperStyle: .cornell)
        precondition(store.currentPage.title == "Cornell test" && store.currentPage.paperStyle == .cornell)
        store.duplicatePage(first)
        precondition(store.currentPage.id != first.id && store.currentPage.drawing.strokes.count == 1)
        let duplicateID = store.currentPage.id
        store.softDelete(second)
        store.purge(second)
        precondition(store.currentPage.id == duplicateID, "Purging an earlier index must preserve selection")
        let relaunched = NoteStore(defaults: defaults, syncWithCloud: false)
        precondition(relaunched.pendingCloudSync.contains(first.id), "Pending uploads must survive relaunch")
        precondition(relaunched.pendingCloudDeletion.contains(second.id), "Failed deletions must survive relaunch")
        relaunched.mergeFromCloud(fetched: [second])
        precondition(!relaunched.pages.contains(where: { $0.id == second.id }), "Deleted cloud notes must not resurrect")
        let brokenRecord = CKRecord(recordType: "NotePage", recordID: CKRecord.ID(recordName: UUID().uuidString))
        precondition(NotePage.fromCKRecord(brokenRecord) == nil, "Unreadable assets must not become blank pages")
        print("PASS: launch drawing, selection, stale merge, negative index, templates, duplication, durable uploads/deletions, no resurrection, corrupt asset checks")
    }
}

@main struct RegressionRunner {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        try NoteStore.runReliabilityChecks()
        try QuickNoteRegression.run()
        try InkSnippetRegression.run()
    }
}
