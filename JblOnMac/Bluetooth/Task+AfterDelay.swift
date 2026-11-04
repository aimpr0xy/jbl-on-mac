extension Task where Success == Void, Failure == Never {
    /// Runs `action` once `duration` has passed, unless the returned task is cancelled first.
    static func afterDelay(_ duration: Duration, _ action: @escaping @MainActor () -> Void) -> Task {
        Task { @MainActor in
            do { try await Task<Never, Never>.sleep(for: duration) } catch { return }
            guard !Task<Never, Never>.isCancelled else { return }
            action()
        }
    }
}
