import XCTest
@testable import SimplePenNote

final class FoldPostureTests: XCTestCase {
    private let inner = CGSize(width: 900, height: 1000)

    func testNoFoldIsFlat() {
        XCTAssertEqual(FoldPosture.classify(folds: [], in: inner), .flat)
    }

    func testHorizontalFoldIsTabletop() {
        let fold = CGRect(x: 0, y: 480, width: 900, height: 40)
        XCTAssertEqual(FoldPosture.classify(folds: [fold], in: inner), .tabletop(fold: fold))
    }

    func testVerticalFoldIsBook() {
        let fold = CGRect(x: 430, y: 0, width: 40, height: 1000)
        XCTAssertEqual(FoldPosture.classify(folds: [fold], in: inner), .book(fold: fold))
    }

    func testFoldIsClippedToContainer() {
        let fold = CGRect(x: -20, y: 480, width: 940, height: 40)
        XCTAssertEqual(FoldPosture.classify(folds: [fold], in: inner),
                       .tabletop(fold: CGRect(x: 0, y: 480, width: 900, height: 40)))
    }

    func testFoldTooCloseToEdgeStaysFlat() {
        // A pane narrower than the minimum can't hold the canvas or the library.
        let fold = CGRect(x: 0, y: 120, width: 900, height: 40)
        XCTAssertEqual(FoldPosture.classify(folds: [fold], in: inner), .flat)
    }

    func testPartialOrMultipleFoldsStayFlat() {
        let partial = CGRect(x: 0, y: 480, width: 400, height: 40)
        XCTAssertEqual(FoldPosture.classify(folds: [partial], in: inner), .flat)
        let a = CGRect(x: 0, y: 480, width: 900, height: 40)
        let b = CGRect(x: 430, y: 0, width: 40, height: 1000)
        XCTAssertEqual(FoldPosture.classify(folds: [a, b], in: inner), .flat)
    }

    func testFoldOutsideContainerStaysFlat() {
        // The window doesn't overlap the hinge (e.g. side-by-side multitasking).
        let fold = CGRect(x: 1200, y: 0, width: 40, height: 1000)
        XCTAssertEqual(FoldPosture.classify(folds: [fold], in: inner), .flat)
    }
}
