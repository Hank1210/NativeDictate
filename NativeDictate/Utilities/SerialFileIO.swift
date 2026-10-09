import Foundation

/// Runs synchronous Foundation file operations on a private serial queue.
///
/// Actor isolation protects store state, but a synchronous `Data.write` can
/// still execute on the caller's thread until it returns. When that caller is
/// the Main Actor, a slow atomic write also delays overlay timers and hotkeys.
/// This helper preserves submission order while allowing the caller to suspend.
nonisolated final class SerialFileIO: @unchecked Sendable {
    private let queue: DispatchQueue

    init(label: String, qos: DispatchQoS = .utility) {
        queue = DispatchQueue(label: label, qos: qos)
    }

    func perform<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// `FileManager` is documented for concurrent use but does not yet declare a
/// Sendable conformance. Stores only use this reference from their private
/// serial file-I/O queue.
nonisolated final class SerialFileManagerReference: @unchecked Sendable {
    let value: FileManager

    init(_ value: FileManager) {
        self.value = value
    }
}
