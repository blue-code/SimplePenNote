import XCTest
import StoreKit
import StoreKitTest
@testable import SimplePenNote

/// Exercises only Xcode's local StoreKit configuration. SKTestSession bypasses
/// the live App Store, and disableDialogs prevents payment UI during these tests.
@MainActor
final class ProStoreTests: XCTestCase {
    func testExternalVerifiedPurchaseUnlocksProThroughTransactionUpdates() async throws {
        let session = try makeSession()
        let store = ProStore()
        try await waitUntil("The configured product should load") {
            store.hasLoadedEntitlements && store.product != nil
        }
        XCTAssertFalse(store.isPro)
        XCTAssertTrue(store.canPurchase)
        XCTAssertEqual(store.product?.type, .nonConsumable)
        XCTAssertFalse(store.product?.displayPrice.isEmpty ?? true)

        try await session.buyProduct(identifier: ProStore.productID)

        // Do not manually refresh: this verifies the transaction listener delivers Pro.
        try await waitUntil("The verified transaction should unlock Pro") { store.isPro }
        XCTAssertFalse(store.canPurchase)
        XCTAssertNil(store.purchaseError)
    }

    func testExistingPurchaseIsRestoredByNewStoreEntitlementRefresh() async throws {
        let session = try makeSession()
        let transaction = try await session.buyProduct(identifier: ProStore.productID)
        await transaction.finish()

        let restoredStore = ProStore()
        await restoredStore.refresh()
        try await waitUntil("A new store should find the existing non-consumable purchase") {
            restoredStore.hasLoadedEntitlements && restoredStore.isPro
        }
        XCTAssertFalse(restoredStore.canPurchase)
        XCTAssertNil(restoredStore.purchaseError)
    }

    func testRefundRemovesProAndDoesNotRestoreRevokedEntitlement() async throws {
        let session = try makeSession()
        let store = ProStore()
        try await waitUntil("Initial entitlements should finish loading") { store.hasLoadedEntitlements }
        try await session.buyProduct(identifier: ProStore.productID)
        try await waitUntil("The local purchase should activate Pro") { store.isPro }
        let transaction = try XCTUnwrap(session.allTransactions().first {
            $0.productIdentifier == ProStore.productID
        })

        try session.refundTransaction(identifier: transaction.identifier)

        // Refund events must remove access without requiring an app restart.
        try await waitUntil("The refund update should revoke Pro") { !store.isPro }
        let newStore = ProStore()
        await newStore.refresh()
        try await waitUntil("The new store should finish checking entitlements") { newStore.hasLoadedEntitlements }
        XCTAssertFalse(newStore.isPro, "A refunded non-consumable must not be restored")
    }

    func testConcurrentPurchaseRequestsDeliverOnlyOneLocalTransaction() async throws {
        let session = try makeSession()
        let store = ProStore()
        try await waitUntil("The product should be ready for a local purchase") { store.canPurchase }

        async let first: Void = store.purchase()
        async let second: Void = store.purchase()
        _ = await (first, second)

        try await waitUntil("The purchase should deliver Pro") { store.isPro }
        XCTAssertEqual(session.allTransactions().filter { $0.productIdentifier == ProStore.productID }.count, 1)
        XCTAssertFalse(store.isPurchasing)
        XCTAssertNil(store.purchaseError)
    }

    private func makeSession() throws -> SKTestSession {
        let configurationURL = try XCTUnwrap(
            Bundle.main.url(forResource: "SimplePenNote", withExtension: "storekit")
                ?? Bundle(for: Self.self).url(forResource: "SimplePenNote", withExtension: "storekit")
        )
        let session = try SKTestSession(contentsOf: configurationURL)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        addTeardownBlock {
            session.clearTransactions()
            session.resetToDefaultState()
        }
        return session
    }

    private func waitUntil(_ message: String, timeout: TimeInterval = 10,
                           file: StaticString = #filePath, line: UInt = #line,
                           condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard condition() else {
            XCTFail(message, file: file, line: line)
            throw WaitError.timedOut
        }
    }

    private enum WaitError: Error { case timedOut }
}
