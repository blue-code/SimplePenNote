import XCTest
import PencilKit
import Combine
import CloudKit
@testable import SimplePenNote

@MainActor
final class NoteStoreTests: XCTestCase {
    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "SimplePenNoteTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func sampleDrawing() -> PKDrawing {
        let point = PKStrokePoint(location: CGPoint(x: 10, y: 20), timeOffset: 0,
                                  size: CGSize(width: 3, height: 3), opacity: 1,
                                  force: 1, azimuth: 0, altitude: .pi / 2)
        let path = PKStrokePath(controlPoints: [point], creationDate: Date())
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
    }

    func testLaunchRestoresDrawingAndSelectedPage() throws {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = NotePage(title: "Handwriting", drawing: sampleDrawing())
        let selected = NotePage(title: "Selected", paperStyle: .weekly)
        defaults.set(try JSONEncoder().encode([first, selected]), forKey: "SimplePenNote_LocalCache_v2")
        defaults.set(selected.id.uuidString, forKey: "SimplePenNote_CurrentPage_v1")

        let store = NoteStore(defaults: defaults, syncWithCloud: false)

        XCTAssertEqual(store.currentPage.id, selected.id)
        XCTAssertEqual(store.pages.first?.drawing.strokes.count, 1)
        XCTAssertEqual(store.currentPage.paperStyle, .weekly)
        store.currentPageIndex = -1
        XCTAssertEqual(store.currentPage.id, first.id)
    }

    func testTemplateCreationAndDuplicatePreserveOriginalDrawing() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteStore(defaults: defaults, syncWithCloud: false)
        store.addNewPage(title: "Lecture", paperStyle: .cornell)
        let original = store.currentPage
        original.drawing = sampleDrawing()
        store.savePages()

        store.duplicatePage(original)
        let duplicate = store.currentPage
        XCTAssertNotEqual(duplicate.id, original.id)
        XCTAssertEqual(duplicate.paperStyle, .cornell)
        XCTAssertEqual(duplicate.drawing.strokes.count, 1)
        duplicate.drawing = PKDrawing()
        store.markDirty(duplicate)

        let relaunched = NoteStore(defaults: defaults, syncWithCloud: false)
        XCTAssertEqual(relaunched.currentPage.id, duplicate.id)
        XCTAssertEqual(relaunched.pages.first(where: { $0.id == original.id })?.drawing.strokes.count, 1)
        XCTAssertEqual(relaunched.currentPage.drawing.strokes.count, 0)
    }

    func testPurgingEarlierPageKeepsSelectedPageAndPersistsDeletion() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteStore(defaults: defaults, syncWithCloud: false)
        let earlier = store.currentPage
        store.addNewPage(title: "Keep selected", paperStyle: .study)
        let selectedID = store.currentPage.id

        store.softDelete(earlier)
        store.purge(earlier)

        XCTAssertEqual(store.currentPage.id, selectedID)
        let relaunched = NoteStore(defaults: defaults, syncWithCloud: false)
        XCTAssertEqual(relaunched.currentPage.id, selectedID)
        XCTAssertFalse(relaunched.pages.contains(where: { $0.id == earlier.id }))
        XCTAssertTrue(defaults.stringArray(forKey: "SimplePenNote_PendingDeletion_v1")?.contains(earlier.id.uuidString) == true)
    }

    func testDeletingLastPageCreatesUsablePageAndRestoreKeepsDrawing() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteStore(defaults: defaults, syncWithCloud: false)
        let original = store.currentPage
        original.drawing = sampleDrawing()
        store.savePages()

        store.softDelete(original)
        XCTAssertEqual(store.activePages.count, 1)
        XCTAssertNotEqual(store.currentPage.id, original.id)
        store.restore(original)
        XCTAssertEqual(store.activePages.count, 2)
        XCTAssertEqual(original.drawing.strokes.count, 1)
        XCTAssertTrue(defaults.stringArray(forKey: "SimplePenNote_PendingSync_v1")?.contains(original.id.uuidString) == true)
    }

    func testRestoredPageClearsCloudTombstoneAndPreservesDrawingAsset() throws {
        let page = NotePage(drawing: sampleDrawing(), deletedAt: Date())
        page.deletedAt = nil
        let record = try page.toCKRecord()
        defer {
            if let url = (record["drawing"] as? CKAsset)?.fileURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        XCTAssertNil(record["deletedAt"])
        XCTAssertTrue(record.changedKeys().contains("deletedAt"))
        let restored = try XCTUnwrap(NotePage.fromCKRecord(record))
        XCTAssertNil(restored.deletedAt)
        XCTAssertEqual(restored.drawing.strokes.count, 1)
    }

    func testPageMetadataEditsNotifyStoreObservers() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteStore(defaults: defaults, syncWithCloud: false)
        var notified = false
        let observation = store.objectWillChange.sink { notified = true }
        defer { observation.cancel() }

        store.currentPage.paperStyle = .study
        store.markDirty(store.currentPage)

        XCTAssertTrue(notified)
        let relaunched = NoteStore(defaults: defaults, syncWithCloud: false)
        XCTAssertEqual(relaunched.currentPage.paperStyle, .study)
    }
}
