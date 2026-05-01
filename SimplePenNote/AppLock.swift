import SwiftUI
import LocalAuthentication

@MainActor
final class LockManager: ObservableObject {
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }
    @Published var isLocked: Bool

    private static let enabledKey = "SimplePenNote_AppLockEnabled"

    init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        self.isEnabled = enabled
        self.isLocked = enabled
    }

    func lockIfEnabled() {
        if isEnabled { isLocked = true }
    }

    /// Prompt biometric authentication. On success, unlock.
    func authenticate() async {
        let context = LAContext()
        context.localizedFallbackTitle = "암호 입력"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No biometrics or passcode set on the device — fail open to avoid bricking.
            isLocked = false
            return
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                           localizedReason: "노트 잠금 해제")
            if success { isLocked = false }
        } catch {
            // User cancelled or failed — remain locked.
        }
    }

    /// Authenticate and turn the lock on.
    func enable() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                           localizedReason: "앱 잠금을 활성화합니다")
            if success { isEnabled = true }
            return success
        } catch {
            return false
        }
    }

    /// Authenticate and turn the lock off.
    func disable() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                           localizedReason: "앱 잠금을 해제합니다")
            if success {
                isEnabled = false
                isLocked = false
            }
            return success
        } catch {
            return false
        }
    }
}

// MARK: - Lock screen overlay

struct LockScreenView: View {
    @ObservedObject var lockManager: LockManager

    var body: some View {
        ZStack {
            Color(red: 0.98, green: 0.97, blue: 0.95)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
                Text("SimplePenNote")
                    .font(.title2).bold()
                Text("잠금 해제 후 사용하세요.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Button {
                    Task { await lockManager.authenticate() }
                } label: {
                    Label("Face ID로 잠금 해제", systemImage: "faceid")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(10)
                }
            }
        }
        .task {
            await lockManager.authenticate()
        }
    }
}

// MARK: - Settings sheet

struct SettingsView: View {
    @ObservedObject var lockManager: LockManager
    @ObservedObject var proStore: ProStore
    @Binding var showPaywall: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Pro") {
                    if proStore.isPro {
                        Label("Pro 사용 중", systemImage: "sparkles")
                            .foregroundColor(.indigo)
                    } else {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showPaywall = true
                            }
                        } label: {
                            Label("SimplePenNote Pro로 업그레이드", systemImage: "sparkles")
                        }
                        Button {
                            Task { await proStore.restore() }
                        } label: {
                            Label("구매 복원", systemImage: "arrow.clockwise")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("보안") {
                    Toggle(isOn: Binding(
                        get: { lockManager.isEnabled },
                        set: { newVal in
                            Task {
                                if newVal {
                                    _ = await lockManager.enable()
                                } else {
                                    _ = await lockManager.disable()
                                }
                            }
                        }
                    )) {
                        Label("앱 잠금", systemImage: "faceid")
                    }
                    Text("앱을 다시 열 때 Face ID 또는 Touch ID로 잠금을 해제합니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("정보") {
                    Link(destination: URL(string: "https://blue-code.github.io/legal/simplepennote/privacy.html")!) {
                        Label("개인정보처리방침", systemImage: "hand.raised")
                    }
                    Link(destination: URL(string: "https://blue-code.github.io/legal/simplepennote/support.html")!) {
                        Label("고객지원", systemImage: "questionmark.circle")
                    }
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
