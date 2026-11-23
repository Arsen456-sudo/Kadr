import Foundation

// All snapshots are value types. Encoding and atomic I/O run on one serial queue;
// a newer snapshot can never be overwritten by a slower, older write.
final class StateWriter {
    private let queue = DispatchQueue(label: "kadr.state-writer", qos: .utility)
    private let url: URL
    private var pending: LocalStore.State?
    private var revision = 0
    var onFailure: (() -> Void)?
    var onSuccess: (() -> Void)?
    init(url: URL) { self.url = url }
    func submit(_ snapshot: LocalStore.State) {
        queue.async { [self] in
            pending = snapshot; revision += 1; let version = revision
            queue.asyncAfter(deadline: .now() + 0.04) { [self] in
                guard revision == version else { return }
                do { try writePending() } catch { DispatchQueue.main.async { self.onFailure?() } }
            }
        }
    }
    private func writePending() throws {
        guard let pending else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(pending).write(to: url, options: .atomic)
        self.pending = nil
        DispatchQueue.main.async { self.onSuccess?() }
    }
    func flush() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do { try writePending(); continuation.resume() }
                catch { DispatchQueue.main.async { self.onFailure?() }; continuation.resume(throwing: error) }
            }
        }
    }
    func flushSync() throws { try queue.sync { try writePending() } }
}
