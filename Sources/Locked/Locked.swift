import Foundation

/// A thread-safe wrapper for a value of type `T`.
///
/// Access the protected value using `read(_:)` or `mutate(_:)` closures, which automatically
/// acquire and release the lock. Each closure invocation is atomic and the lock is held only
/// for the duration of the closure.
///
/// For extended lock acquisition, use `acquireIntoHandle()` to get an RAII `AcquisitionHandle`.
public class Locked<T>: @unchecked Sendable {
	private let lock = NSLock()
	private var inner: T

	public init(_ inner: consuming T) {
		self.inner = inner
	}

	public final func read<R>(in f: (borrowing T) throws -> R) rethrows -> R {
		try self.lock.withLock {
			try f(self.inner)
		}
	}

	public final func mutate<R>(in f: (inout T) throws -> R) rethrows -> R {
		try self.lock.withLock {
			try f(&self.inner)
		}
	}
}

public extension Locked {
	struct AcquisitionHandle: ~Copyable {
		private let parent: Locked
		public var resource: T {
			_read {
				yield self.parent.inner
			}
			nonmutating _modify {
				yield &self.parent.inner
			}
		}

		fileprivate init(parent: Locked) {
			self.parent = parent
		}

		public consuming func release() {}

		deinit {
			self.parent.lock.unlock()
		}
	}

	final func acquireIntoHandle() -> AcquisitionHandle {
		self.lock.lock()
		return AcquisitionHandle(parent: self)
	}
}

/// Convenience subclass providing implicit access patterns that are easy to misuse.
public class LockedWithImplicitAccess<T>: Locked<T>, @unchecked Sendable {
	/// Dictionary subscript. Each access is independently atomic but multiple accesses are not atomic together.
	public subscript<K, V>(key: K) -> V? where T == Dictionary<K, V> {
		get { self.read { $0[key] }}
		set { self.mutate { $0[key] = newValue }}
	}
}
