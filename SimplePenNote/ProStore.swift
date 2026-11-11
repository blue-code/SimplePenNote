import SwiftUI
import StoreKit

@MainActor
final class ProStore: ObservableObject {
    nonisolated static let productID = "com.blueCode.SimplePenNote.pro"
    nonisolated static let freePageLimit = 5

    @Published private(set) var isPro = false
    @Published private(set) var product: Product?
    @Published var purchaseError: String?
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var hasLoadedEntitlements = false
    @Published private(set) var productLoadError: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var hasPendingPurchase = false

    var isBusy: Bool { isPurchasing || isRestoring }
    var canPurchase: Bool {
        product != nil && hasLoadedEntitlements && !isPro && !isBusy && !hasPendingPurchase
    }

    private var transactionListener: Task<Void, Never>?
    private var isRefreshing = false
    private var entitlementRefreshGeneration = 0

    init() {
        transactionListener = listenForTransactions()
        Task { [weak self] in await self?.refresh() }
    }

    deinit { transactionListener?.cancel() }

    /// Entitlements are checked independently of the product request, so a catalog
    /// failure never prevents a previous purchaser from using Pro offline.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await refreshEntitlement()
        await loadProduct()
    }

    private func loadProduct() async {
        guard !isLoadingProduct else { return }
        isLoadingProduct = true
        productLoadError = nil
        defer { isLoadingProduct = false }
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first { $0.id == Self.productID && $0.type == .nonConsumable }
            if product == nil {
                productLoadError = String(localized: "현재 스토어에서 Pro 상품을 불러올 수 없습니다. 잠시 후 다시 시도해 주세요.")
            }
        } catch {
            productLoadError = String(localized: "스토어에 연결하지 못했습니다. 인터넷 연결을 확인하고 다시 시도해 주세요.")
        }
    }

    private func refreshEntitlement() async {
        entitlementRefreshGeneration += 1
        let generation = entitlementRefreshGeneration
        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                found = true
            }
        }
        // A transaction update or a newer refresh can arrive while iterating.
        guard generation == entitlementRefreshGeneration else { return }
        #if DEBUG
        if DemoData.isPro { found = true }
        #endif
        isPro = found
        hasLoadedEntitlements = true
        if found {
            hasPendingPurchase = false
            statusMessage = nil
        }
    }

    func purchase() async {
        guard canPurchase, let product else { return }
        isPurchasing = true
        purchaseError = nil
        statusMessage = nil
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let result):
                await handleTransaction(result)
            case .userCancelled:
                break
            case .pending:
                hasPendingPurchase = true
                statusMessage = String(localized: "구매 승인을 기다리고 있습니다. 승인되면 Pro가 자동으로 활성화됩니다.")
            @unknown default:
                purchaseError = String(localized: "구매 상태를 확인하지 못했습니다. 구매 복원을 시도해 주세요.")
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restore() async {
        guard !isBusy else { return }
        isRestoring = true
        purchaseError = nil
        statusMessage = nil
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            statusMessage = isPro ? String(localized: "Pro 구매를 복원했습니다.") : String(localized: "현재 Apple 계정에서 복원할 Pro 구매를 찾지 못했습니다.")
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func handleTransaction(_ result: VerificationResult<StoreKit.Transaction>) async {
        switch result {
        case .verified(let transaction):
            guard transaction.productID == Self.productID else { return }
            // Invalidate older reads, then deliver before finishing the transaction.
            entitlementRefreshGeneration += 1
            isPro = transaction.revocationDate == nil
            hasLoadedEntitlements = true
            hasPendingPurchase = false
            statusMessage = nil
            await transaction.finish()
            await refreshEntitlement()
        case .unverified(let transaction, _):
            guard transaction.productID == Self.productID else { return }
            purchaseError = String(localized: "구매 정보를 검증하지 못했습니다. Pro가 활성화되지 않았다면 구매 복원을 시도해 주세요.")
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                await self?.handleTransaction(result)
            }
        }
    }
}

// MARK: - Paywall

enum PaywallContext: String, Identifiable {
    case general, pageLimit, cleanExport, batchExport, transparentExport, snippetLibrary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "기록은 자유롭게,\n공유는 깔끔하게.")
        case .pageLimit: return String(localized: "다음 아이디어도\n계속 기록하세요.")
        case .cleanExport: return String(localized: "내 필기만 담아\n깔끔하게 공유하세요.")
        case .batchExport: return String(localized: "여러 장의 기록을\n하나의 PDF로.")
        case .transparentExport: return String(localized: "배경 없이,\n내 스케치만 쏙.")
        case .snippetLibrary: return String(localized: "한 번 그려두고,\n계속 꺼내 쓰세요.")
        }
    }

    var subtitle: String {
        switch self {
        case .general: return String(localized: "떠오른 생각을 마음껏 쓰고, 원하는 곳에 꺼내 쓰세요.")
        case .pageLimit: return String(localized: "무료 페이지 \(ProStore.freePageLimit)장을 모두 사용했습니다. Pro로 제한 없이 이어가세요.")
        case .cleanExport: return String(localized: "짧은 메모와 스케치를 워터마크 없이 깔끔하게 공유하세요.")
        case .batchExport: return String(localized: "흩어진 노트를 한 파일로 모아 보관하고 공유하세요.")
        case .transparentExport: return String(localized: "투명 PNG로 저장하거나 복사해 메시지, 문서, 디자인에 붙여넣으세요.")
        case .snippetLibrary: return String(localized: "자주 쓰는 화살표, 체크 표시와 손글씨를 보관하고 다른 노트에 다시 넣으세요.")
        }
    }
}

struct PaywallView: View {
    @ObservedObject var proStore: ProStore
    var context: PaywallContext = .general
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("SimplePenNote Pro", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.indigo)
                        Text(context.title)
                            .font(.largeTitle.bold())
                            .fixedSize(horizontal: false, vertical: true)
                        Text(context.subtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 22) {
                        benefitRow("square.stack.3d.up", "페이지 제한 없이", "짧은 메모와 떠오른 아이디어를 원하는 만큼 기록")
                        benefitRow("square.and.arrow.up", "워터마크 없는 PNG · PDF", "내 필기만 깔끔하게 저장하고 공유")
                        benefitRow("square.on.circle", "배경 없는 투명 PNG", "스케치만 저장하거나 복사해 다른 앱에 붙여넣기")
                        benefitRow("square.stack.3d.up.fill", "나만의 손글씨 보관함", "이 기기에 저장하고 다른 노트에 필기 원본으로 다시 넣기")
                        benefitRow("doc.on.doc", "여러 페이지를 하나의 PDF로", "선택한 노트를 한 파일로 묶어 내보내기")
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 22))

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("한 번 결제, 계속 사용").font(.headline)
                            Text("구독이나 정기 결제 없이, 같은 Apple 계정에서 구매를 복원할 수 있습니다.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Text("무료 버전에서도 페이지 \(ProStore.freePageLimit)장, 모든 기본 서식, 워터마크가 있는 PNG·PDF 내보내기를 사용할 수 있습니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) { purchaseControls }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .accessibilityIdentifier("paywall.close")
                }
            }
            .task { await proStore.refresh() }
            .onChange(of: proStore.isPro) { _, isPro in
                if isPro { dismiss() }
            }
            .alert("구매 확인",
                   isPresented: Binding(get: { proStore.purchaseError != nil },
                                        set: { if !$0 { proStore.purchaseError = nil } })) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(proStore.purchaseError ?? "")
            }
        }
    }

    /// Store captures show the offer even though demo mode unlocks Pro for the other screens.
    private var isDemoOffer: Bool {
        #if DEBUG
        return DemoData.isEnabled
        #else
        return false
        #endif
    }

    private var purchaseControls: some View {
        VStack(spacing: 12) {
            if proStore.isPro && !isDemoOffer {
                Label("Pro 사용 중", systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(.indigo)
                Button("계속 기록하기") { dismiss() }
            } else {
                if let message = proStore.statusMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("paywall.status")
                }
                if proStore.product == nil {
                    if proStore.isLoadingProduct || !proStore.hasLoadedEntitlements {
                        ProgressView("스토어 정보 확인 중")
                    } else {
                        Text(proStore.productLoadError ?? String(localized: "스토어 정보를 확인해 주세요."))
                            .font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("스토어 다시 불러오기") { Task { await proStore.refresh() } }
                            .accessibilityIdentifier("paywall.retry")
                    }
                }
                Button {
                    Task { await proStore.purchase() }
                } label: {
                    HStack(spacing: 10) {
                        if proStore.isPurchasing { ProgressView().tint(.white) }
                        Text(purchaseButtonTitle).font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(!proStore.canPurchase && !isDemoOffer)
                .accessibilityIdentifier("paywall.purchase")

                HStack(spacing: 20) {
                    Button {
                        Task { await proStore.restore() }
                    } label: {
                        HStack(spacing: 6) {
                            if proStore.isRestoring { ProgressView() }
                            Text("구매 복원")
                        }
                    }
                    .disabled(proStore.isBusy)
                    .accessibilityIdentifier("paywall.restore")
                    Button("무료로 계속 사용") { dismiss() }
                        .disabled(proStore.isPurchasing)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private var purchaseButtonTitle: String {
        #if DEBUG
        // Store captures: the StoreKit test price is USD in every locale, so leave it out.
        if DemoData.isEnabled { return String(localized: "Pro 잠금 해제") }
        #endif
        if proStore.isPurchasing { return String(localized: "구매 진행 중") }
        if proStore.hasPendingPurchase { return String(localized: "구매 승인 대기 중") }
        guard let product = proStore.product else { return String(localized: "Pro 잠금 해제") }
        return String(localized: "\(product.displayPrice) · 평생 Pro 잠금 해제")
    }

    private func benefitRow(_ icon: String, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.indigo)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
