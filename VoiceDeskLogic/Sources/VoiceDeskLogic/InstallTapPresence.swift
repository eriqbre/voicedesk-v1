import Foundation

/// HAL retains this for the life of `installTap`. `deinit` means HAL
/// released the block. SET missing only. Do not put the tap back
/// from deinit — that raced leftover created (9b3d42b 53s).
public final class InstallTapHold: @unchecked Sendable {
    private let onRelease: @Sendable () -> Void

    fileprivate init(onRelease: @escaping @Sendable () -> Void) {
        self.onRelease = onRelease
    }

    deinit {
        onRelease()
    }
}

/// Generation-guarded HAL install-block presence. Our own removeTap
/// must `invalidate` first so leftover drain-time reinstall does not
/// leave the next hold marked released. Object-left inject is
/// `removeTap` only — it does not flip a storage bit.
public final class InstallTapPresence: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var releasedGeneration: Int?

    public init() {}

    public var isReleased: Bool {
        lock.lock()
        defer { lock.unlock() }
        return releasedGeneration == generation
    }

    public func nextHold() -> InstallTapHold {
        lock.lock()
        generation += 1
        let captured = generation
        lock.unlock()
        return InstallTapHold { [self] in
            self.lock.lock()
            self.releasedGeneration = captured
            self.lock.unlock()
        }
    }

    /// Call before our removeTap / teardown. In-flight deinit of the
    /// old hold must not mark the next install missing.
    public func invalidate() {
        lock.lock()
        generation += 1
        lock.unlock()
    }
}
