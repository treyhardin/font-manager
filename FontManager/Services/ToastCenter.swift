import Foundation

/// Shared transient notification surface. Long operations use `begin`/`update`/`finish`
/// with a token (so a newer operation's updates win and stale ones are ignored);
/// quick notifications use `flash`.
@MainActor
final class ToastCenter: ObservableObject {
    @Published var toast: Toast?

    struct Toast: Identifiable {
        let id = UUID()
        var message: String
        var state: State
        var revealURL: URL?

        enum State {
            case working
            case success
            case failure
        }
    }

    private var activeToken = 0
    private var dismissTask: Task<Void, Never>?

    /// Begin a long-running operation; returns a token to scope later updates.
    @discardableResult
    func begin(_ message: String) -> Int {
        dismissTask?.cancel()
        activeToken &+= 1
        toast = Toast(message: message, state: .working)
        return activeToken
    }

    func update(_ token: Int, message: String) {
        guard token == activeToken else { return }
        toast?.message = message
    }

    func finish(_ token: Int, success: Bool, message: String, reveal: URL? = nil) {
        guard token == activeToken else { return }
        toast = Toast(message: message, state: success ? .success : .failure, revealURL: reveal)
        scheduleDismiss(after: success ? 6 : 8)
    }

    /// Show an instant notification (no working phase), e.g. activation results.
    func flash(_ message: String, isError: Bool = false, reveal: URL? = nil) {
        dismissTask?.cancel()
        activeToken &+= 1
        toast = Toast(message: message, state: isError ? .failure : .success, revealURL: reveal)
        scheduleDismiss(after: isError ? 6 : 4)
    }

    func dismiss() {
        dismissTask?.cancel()
        toast = nil
    }

    private func scheduleDismiss(after seconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
