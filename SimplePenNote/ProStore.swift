import SwiftUI
import StoreKit

@MainActor
final class ProStore: ObservableObject {
    static let productID = "com.blueCode.SimplePenNote.pro"
    static let freePageLimit = 5

    @Published var isPro: Bool = false
    @Published var product: Product?
    @Published var purchaseError: String?
    @Published var isPurchasing: Bool = false

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
        Task { await refresh() }
    }

    deinit {
        transactionListener?.cancel()
    }

    func refresh() async {
        await loadProduct()
        await refreshEntitlement()
    }

    private func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            self.product = products.first
        } catch {
            // Network or App Store error — UI shows price as "—"
        }
    }

    private func refreshEntitlement() async {
        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == Self.productID {
                found = true
            }
        }
        self.isPro = found
    }

    func purchase() async {
        guard let product else {
            purchaseError = "스토어에서 상품을 불러오지 못했습니다."
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    await tx.finish()
                    await refreshEntitlement()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let tx) = result {
                    await tx.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
    }
}

// MARK: - Paywall

struct PaywallView: View {
    @ObservedObject var proStore: ProStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundColor(.indigo)
                Text("SimplePenNote Pro")
                    .font(.title).bold()
                VStack(alignment: .leading, spacing: 12) {
                    benefitRow("무제한 페이지", "노트를 자유롭게 늘리세요")
                    benefitRow("워터마크 없는 내보내기", "PNG·PDF 깔끔하게 출력")
                    benefitRow("일회 결제, 영구 사용", "구독 없음, 동일 Apple ID 모든 기기")
                }
                .padding(.horizontal, 32)
                Spacer()

                if proStore.isPro {
                    Text("이미 Pro 사용자입니다 ✨")
                        .font(.headline)
                        .foregroundColor(.indigo)
                        .padding(.bottom, 32)
                } else {
                    Button {
                        Task { await proStore.purchase() }
                    } label: {
                        HStack {
                            if proStore.isPurchasing {
                                ProgressView().tint(.white)
                            } else {
                                Text(displayPriceText).bold()
                                Text("으로 Pro 잠금 해제")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.indigo)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(proStore.product == nil || proStore.isPurchasing)
                    .padding(.horizontal, 24)

                    Button("구매 복원") {
                        Task { await proStore.restore() }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .alert("구매 오류",
                   isPresented: Binding(get: { proStore.purchaseError != nil },
                                        set: { if !$0 { proStore.purchaseError = nil } })) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(proStore.purchaseError ?? "")
            }
        }
    }

    /// Real StoreKit price when available; in demo/screenshot mode shows a fixed
    /// localized price so screenshots match App Store metadata regardless of
    /// simulator storefront.
    private var displayPriceText: String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-DemoMode") { return "₩4,400" }
        #endif
        return proStore.product?.displayPrice ?? "—"
    }

    private func benefitRow(_ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.indigo)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}
