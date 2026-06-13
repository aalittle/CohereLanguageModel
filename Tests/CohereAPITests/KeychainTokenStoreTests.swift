#if canImport(Security)
import Foundation
import Security
import Testing
@testable import CohereAPI

/// In-memory ``KeychainBackend`` that emulates the real Keychain's status
/// semantics by default, with knobs to force error statuses and inject raw
/// (non-UTF8) bytes — enough to drive every branch in `KeychainTokenStore`
/// without touching the login keychain.
final class FakeKeychainBackend: KeychainBackend, @unchecked Sendable {
    // The store's methods are synchronous, so a lock (not an actor) fits the
    // protocol; it guards the storage map and the call counters.
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private(set) var updateCallCount = 0

    // When set, the matching operation returns this status instead of its
    // emulated result — used to reach the `unhandled(status)` branches.
    var forcedCopyStatus: OSStatus?
    var forcedAddStatus: OSStatus?
    var forcedUpdateStatus: OSStatus?
    var forcedDeleteStatus: OSStatus?

    private func key(_ service: String, _ account: String) -> String {
        "\(service)\u{0}\(account)"
    }

    /// Inject arbitrary bytes (e.g. invalid UTF8) to test the decode path.
    func seedRaw(_ data: Data, service: String, account: String) {
        lock.withLock { storage[key(service, account)] = data }
    }

    func copyData(service: String, account: String) -> (status: OSStatus, data: Data?) {
        lock.withLock {
            let data = storage[key(service, account)]
            if let forcedCopyStatus { return (forcedCopyStatus, data) }
            return data == nil ? (errSecItemNotFound, nil) : (errSecSuccess, data)
        }
    }

    func add(service: String, account: String, data: Data, accessible: String) -> OSStatus {
        lock.withLock {
            if let forcedAddStatus { return forcedAddStatus }
            let k = key(service, account)
            if storage[k] != nil { return errSecDuplicateItem }
            storage[k] = data
            return errSecSuccess
        }
    }

    func update(service: String, account: String, data: Data) -> OSStatus {
        lock.withLock {
            updateCallCount += 1
            if let forcedUpdateStatus { return forcedUpdateStatus }
            let k = key(service, account)
            guard storage[k] != nil else { return errSecItemNotFound }
            storage[k] = data
            return errSecSuccess
        }
    }

    func delete(service: String, account: String) -> OSStatus {
        lock.withLock {
            if let forcedDeleteStatus { return forcedDeleteStatus }
            let k = key(service, account)
            return storage.removeValue(forKey: k) == nil ? errSecItemNotFound : errSecSuccess
        }
    }
}

@Suite struct KeychainTokenStoreTests {
    private func store(_ backend: FakeKeychainBackend) -> KeychainTokenStore {
        KeychainTokenStore(service: "test.service", accessible: "test.accessible", backend: backend)
    }

    @Test func writeThenReadRoundTrips() async throws {
        let store = store(FakeKeychainBackend())
        try await store.write("sk-live-42", account: "cohere")
        #expect(try await store.read(account: "cohere") == "sk-live-42")
    }

    @Test func readMissingAccountReturnsNil() async throws {
        let store = store(FakeKeychainBackend())
        #expect(try await store.read(account: "absent") == nil)
    }

    @Test func writingExistingAccountTakesTheUpdatePath() async throws {
        let backend = FakeKeychainBackend()
        let store = store(backend)
        try await store.write("first", account: "cohere")
        try await store.write("second", account: "cohere")  // add → duplicate → update
        #expect(backend.updateCallCount == 1)
        #expect(try await store.read(account: "cohere") == "second")
    }

    @Test func deleteRemovesTheToken() async throws {
        let store = store(FakeKeychainBackend())
        try await store.write("doomed", account: "cohere")
        try await store.delete(account: "cohere")
        #expect(try await store.read(account: "cohere") == nil)
    }

    @Test func deletingMissingAccountSucceeds() async throws {
        // errSecItemNotFound is treated as success, not an error.
        let store = store(FakeKeychainBackend())
        try await store.delete(account: "never-existed")
    }

    @Test func nonUTF8StoredBytesThrowUnexpectedData() async throws {
        let backend = FakeKeychainBackend()
        backend.seedRaw(Data([0xFF, 0xFE, 0xFD]), service: "test.service", account: "cohere")
        await #expect(throws: KeychainError.unexpectedData) {
            _ = try await store(backend).read(account: "cohere")
        }
    }

    @Test func successStatusWithNoDataThrowsUnexpectedData() async throws {
        let backend = FakeKeychainBackend()
        backend.forcedCopyStatus = errSecSuccess  // success but storage is empty → nil data
        await #expect(throws: KeychainError.unexpectedData) {
            _ = try await store(backend).read(account: "cohere")
        }
    }

    @Test func unexpectedReadStatusThrowsUnhandled() async throws {
        let backend = FakeKeychainBackend()
        backend.forcedCopyStatus = errSecParam
        await #expect(throws: KeychainError.unhandled(errSecParam)) {
            _ = try await store(backend).read(account: "cohere")
        }
    }

    @Test func addFailureThrowsUnhandled() async throws {
        let backend = FakeKeychainBackend()
        backend.forcedAddStatus = errSecParam
        await #expect(throws: KeychainError.unhandled(errSecParam)) {
            try await store(backend).write("x", account: "cohere")
        }
    }

    @Test func updateFailureAfterDuplicateThrowsUnhandled() async throws {
        let backend = FakeKeychainBackend()
        let store = store(backend)
        try await store.write("first", account: "cohere")  // now present
        backend.forcedUpdateStatus = errSecParam            // next write: add→dup→update fails
        await #expect(throws: KeychainError.unhandled(errSecParam)) {
            try await store.write("second", account: "cohere")
        }
    }

    @Test func deleteFailureThrowsUnhandled() async throws {
        let backend = FakeKeychainBackend()
        backend.forcedDeleteStatus = errSecParam
        await #expect(throws: KeychainError.unhandled(errSecParam)) {
            try await store(backend).delete(account: "cohere")
        }
    }
}
#endif
