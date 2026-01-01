@testable import Locked
import Testing

struct LockedTests {
	struct Person {
		var name: String
		var age: Int
	}

	struct TestError: Error {
		let message: String
	}

	@Test func basicAccess() {
		let locked = Locked(Person(name: "Alice", age: 30))

		let initialName = locked.read { $0.name }
		#expect(initialName == "Alice")

		locked.mutate { $0.age += 1 }
		locked.mutate { $0.age += 1 }
		locked.mutate { $0.name = "Bob" }

		let finalAge = locked.read { $0.age }
		let finalName = locked.read { $0.name }
		#expect(finalAge == 32)
		#expect(finalName == "Bob")
	}

	@Test func dictionarySubscript() {
		let locked = LockedWithImplicitAccess<[String: Int]>([:])

		// Set values
		locked["a"] = 1
		locked["b"] = 2
		locked["c"] = 3

		// Get values
		#expect(locked["a"] == 1)
		#expect(locked["b"] == 2)
		#expect(locked["c"] == 3)
		#expect(locked["nonexistent"] == nil)

		// Update value
		locked["a"] = 10
		locked["a"] = 20
		#expect(locked["a"] == 20)

		// Remove value
		locked["b"] = nil
		#expect(locked["b"] == nil)
		#expect(locked["a"] == 20)
		#expect(locked["c"] == 3)
	}

	@Test func throwingOperations() throws {
		let locked = Locked(Person(name: "Alice", age: 10))

		// Test that errors propagate from read
		#expect(throws: TestError.self) {
			try locked.read { _ throws -> Int in
				throw TestError(message: "error from read")
			}
		}

		// Test that errors propagate from mutate
		#expect(throws: TestError.self) {
			try locked.mutate { _ throws in
				throw TestError(message: "error from mutate")
			}
		}
	}

	@Test func acquisitionHandle() async {
		let locked = Locked(5)
		let handle = locked.acquireIntoHandle()

		#expect(handle.resource == 5)

		handle.resource += 10
		#expect(handle.resource == 15)

		let task = Task {
			locked.mutate { $0 = 999 }
		}

		await Task.yield()
		#expect(handle.resource == 15)

		handle.release()
		await task.value
		let value = locked.read { $0 }
		#expect(value == 999)
	}

	@Test func concurrentReads() async {
		let locked = Locked(0)

		await withTaskGroup(of: Int.self) { group in
			for _ in 0..<100 {
				group.addTask {
					locked.read { $0 }
				}
			}

			var count = 0
			for await _ in group {
				count += 1
			}

			#expect(count == 100)
		}
	}

	@Test func concurrentMutations() async {
		let locked = Locked(0)

		await withTaskGroup(of: Void.self) { group in
			for _ in 0..<100 {
				group.addTask {
					locked.mutate { $0 += 1 }
				}
			}

			await group.waitForAll()
		}

		let finalValue = locked.read { $0 }
		#expect(finalValue == 100)
	}

	@Test func concurrentDictionaryAccess() async {
		let locked = LockedWithImplicitAccess<[Int: Int]>([:])

		await withTaskGroup(of: Void.self) { group in
			for i in 0..<100 {
				group.addTask {
					locked[i] = i * 2
				}
			}

			await group.waitForAll()
		}

		let count = locked.read { $0.count }
		#expect(count == 100)

		for i in 0..<100 {
			#expect(locked[i] == i * 2)
		}
	}
}
