import Foundation

public final class Locked<T>: @unchecked Sendable {
	private let lock = NSLock()
	private var inner: T

	public init(_ inner: consuming T) {
		self.inner = inner
	}

	public func read<R>(in f: (borrowing T) throws -> R) rethrows -> R {
		try self.lock.withLock {
			try f(self.inner)
		}
	}

	public func mutate<R>(in f: (inout T) -> R) -> R {
		self.lock.withLock {
			f(&self.inner)
		}
	}

	public subscript<K, V>(key: K) -> V? where T == Dictionary<K, V> {
		get { self.read { $0[key] }}
		set { self.mutate { $0[key] = newValue }}
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

	func acquireIntoHandle() -> AcquisitionHandle {
		self.lock.lock()
		return AcquisitionHandle(parent: self)
	}
}
